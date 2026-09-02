# .NET NativeAOT

**documented**, not measured: the probe host had no .NET SDK.

---

## 1. Fully static: yes

```sh
dotnet publish -c Release -r linux-musl-x64 \
  -p:PublishAot=true \
  -p:StaticExecutable=true \
  -p:InvariantGlobalization=true \
  -p:StripSymbols=true
```

⭐ **`PublishAot` compiles to a native binary with no runtime dependency;
`StaticExecutable` links libc statically too.** With the `linux-musl-*` runtime
identifier the result has no `PT_INTERP`.

⚠ **`PublishAot` alone leaves libc dynamic.** Both properties are needed.

⚠ **Distinguish three things that are often confused:**

| | needs a runtime installed | one file | static |
| --- | --- | --- | --- |
| framework-dependent | ⛔ yes | no | no |
| self-contained, `PublishSingleFile` | no | yes | ⚠ **no**: it extracts and runs an embedded runtime |
| ⭐ `PublishAot` + `StaticExecutable` | no | yes | ⭐ yes |

⛔ **`PublishSingleFile` is not what this system means by a static binary.** It
is a self-extracting bundle that still needs a host libc, and on first run it
may unpack to a temporary directory.

## 2. libc

| runtime identifier | libc |
| --- | --- |
| ⭐ `linux-musl-x64`, `linux-musl-arm64` | musl |
| `linux-x64`, `linux-arm64` | glibc |

⭐ **The musl RIDs are the ones to use.** They are first-class and tested.

## 3. Compiler and toolchain

| | |
| --- | --- |
| the .NET SDK | ⛔ pin by image digest |
| ILCompiler | pulled as a NuGet package; ⛔ pinned by the lockfile |
| a native toolchain | clang plus a linker; on Alpine `build-base` and `musl-dev` |
| ⚠ also needed | `zlib-static`, and `openssl-libs-static` if TLS is used |

## 4. Cross-compilation

⚠ **NativeAOT does not cross-compile between architectures.** Cross-*libc* on
one architecture works; `linux-x64` to `linux-arm64` does not.

⭐ **Build in a container for the target architecture**, natively where a
runner exists.

## 5. CPU features

```
-p:IlcInstructionSet=x86-64-v2
```

⛔ The default is the architecture baseline, which is correct. Do not raise it
without publishing the baseline too.

## 6. External libraries

⛔ **P/Invoke to a shared library needs that library at run time**, which
defeats static linking. `DllImport` targets can be statically linked with
`DirectPInvoke`:

```xml
<DirectPInvoke Include="libfoo" />
<NativeLibrary Include="/usr/lib/libfoo.a" />
```

⚠ **Reflection and dynamic code are the real constraint**, exactly as with
GraalVM. NativeAOT does closed-world analysis.

⛔ **`System.Reflection.Emit` does not work at all.** Anything generating IL at
run time, including some serializers and ORMs, is incompatible. ⭐ Source
generators are the supported replacement, and `System.Text.Json` has one.

## 7. TLS and certificates

⚠ **.NET on Linux uses OpenSSL.** A static build needs static OpenSSL, and the
certificate store comes from the host through OpenSSL's paths.

⚠ **A NativeAOT binary that cannot find OpenSSL fails at first TLS use**, not at
start-up, so it passes a smoke test and fails in the field. `[verify].run`
should exercise a TLS path where the program does one.

## 8. DNS

Through libc. musl's resolver on the musl RIDs.

## 9. Locale

⛔ **`InvariantGlobalization=true` is effectively required for a small static
build**, because the alternative is shipping ICU.

⚠ **Invariant globalization changes behaviour**: culture-aware string
comparison, casing and date formatting all fall back to invariant rules. A
program that sorts user-visible strings will sort them differently. ⭐ It is the
right default for a command-line tool and wrong for anything locale-aware, and
the choice belongs in a `note`.

⭐ **The alternative is `-p:InvariantGlobalization=false` with the ICU data
shipped**, which works and adds tens of megabytes.

## 10. Plugins

⛔ `AssemblyLoadContext` and run-time assembly loading do not work in a
NativeAOT image.

## 11. Kernel

**documented**: inherits musl's floor.

## 12. Reproducibility

| control | |
| --- | --- |
| ⭐ `packages.lock.json` | commit it; ⛔ build with `--locked-mode` |
| ⭐ `-p:Deterministic=true` | the default for the managed compile |
| ⭐ `-p:ContinuousIntegrationBuild=true` | normalises embedded paths |
| ⚠ the native compile | less well characterised; treat as `unverified` until demonstrated |

⭐ **.NET has better reproducibility support than the JVM's native-image
path**, with explicit flags for it.

## 13. Debugging and size

`-p:StripSymbols=true` strips. ⚠ A hello-world NativeAOT binary is typically
1 MB to 3 MB with `InvariantGlobalization`, which is competitive; a real
application is larger.

`-p:IlcOptimizationPreference=Size` and `-p:TrimMode=full` reduce it further.

⚠ **Trimming can remove code reached only reflectively**, producing the same
class of run-time failure as GraalVM's closed-world analysis. Trim warnings are
worth treating as errors.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build]
image = "mcr.microsoft.com/dotnet/sdk@sha256:..."
deps  = ["build-base", "musl-dev", "zlib-static", "openssl-libs-static"]

[build.script]
run = """
dotnet restore --locked-mode
dotnet publish -c Release -r linux-musl-x64 --no-restore \
  -p:PublishAot=true \
  -p:StaticExecutable=true \
  -p:InvariantGlobalization=true \
  -p:StripSymbols=true \
  -p:ContinuousIntegrationBuild=true \
  -o out
"""

[verify]
run = ["--version"]
```

**Failure modes**

| symptom | cause |
| --- | --- |
| the binary is dynamic | ⛔ `StaticExecutable` omitted, or a glibc RID used |
| `PlatformNotSupportedException` at run time | `Reflection.Emit`; use source generators |
| a type is missing only in the published build | trimming removed a reflectively reached type |
| TLS fails at first use, not at start-up | static OpenSSL missing |
| strings sort unexpectedly | ⚠ `InvariantGlobalization`; expected, and it belongs in a note |
| ⛔ the "single file" build needs a libc | `PublishSingleFile` was used instead of `PublishAot` |

**⛔ When not to**: the program uses `Reflection.Emit` or loads assemblies at
run time; it needs full ICU behaviour and the size is unacceptable; it must be
cross-compiled to an architecture with no runner.
