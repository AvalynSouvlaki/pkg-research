# Zig

⭐ **measured** on the probe host, zig 0.13.0. Produced the **smallest** binary
of any toolchain measured, and doubles as a C cross toolchain for projects with
no Zig in them.

---

## 1. Fully static: yes

| recipe | bytes | PT_INTERP |
| --- | ---: | --- |
| ⭐ `zig build-exe -O ReleaseSmall -target x86_64-linux-musl` | **12,952** | none |
| ⭐ `zig cc -O2 -target x86_64-linux-musl` (C source) | 204,192 | none |

⭐ **12,952 bytes against musl-gcc's 24,744 for the equivalent program.**

## 2. libc

| target suffix | libc | note |
| --- | --- | --- |
| ⭐ `-musl` | musl, ⭐ statically by default | **the default here** |
| `-gnu` | glibc, ⭐ **version-selectable**: `-target x86_64-linux-gnu.2.17` | see below |
| `-none` | freestanding, no libc | |

⭐ **Zig's glibc version selection is a capability nothing else has.** Targeting
`gnu.2.17` produces a dynamically linked binary that runs on any glibc 2.17 or
newer, without needing an old build machine. That is the correct answer for the
rare package that must be dynamically linked against glibc, and it removes the
usual "build on the oldest distribution you support" workaround.

## 3. Compiler and linker

| | |
| --- | --- |
| compiler | `zig` itself, or `zig cc` and `zig c++` as clang drivers |
| linker | ⭐ `zig ld`, an lld derivative, built in |
| pin | ⛔ by image digest, or the exact tarball hashed as a `[[tool]]` |

⚠ **Zig's language is pre-1.0 and its standard library changes between minor
releases.** A Zig program that builds under 0.13 often does not build under
0.14. Pinning is not optional here in the way it is elsewhere.

## 4. Cross-compilation

⭐ **The reason Zig is in this project.** One 47 MB download replaces a matrix
of cross toolchains, including headers and libc sources for every target.

```sh
zig build-exe main.zig -O ReleaseSafe -target aarch64-linux-musl
zig cc  -target riscv64-linux-musl -O2 -static hello.c -o hello
zig c++ -target aarch64-macos      -O2 hello.cpp -o hello
zig cc  -target x86_64-windows-gnu -O2 hello.c   -o hello.exe
```

**Target triples**: `<arch>-<os>-<abi>`, shorter than the GNU form.
`zig targets | jq -r '.libc[]'` lists every supported combination.

⭐ **Used as `CC` for another ecosystem:**

```sh
export CC="zig cc -target aarch64-linux-musl"
export CXX="zig c++ -target aarch64-linux-musl"
cargo zigbuild --target aarch64-unknown-linux-musl
```

⚠ **Friction**, so it is not oversold: some autotools projects pass gcc-only
flags that `zig cc` rejects, and the usual workaround is a wrapper script that
filters them. Zig's C ABI support for less common targets is less exercised
than GCC's.

## 5. CPU features

```sh
zig build-exe main.zig -target x86_64-linux-musl -mcpu=x86_64_v2
```

⭐ **`-mcpu` takes an explicit feature list too**, for example
`-mcpu=baseline+avx2`, which is finer-grained than gcc's `-march` levels.

⛔ **`-mcpu=native` targets the runner.** Do not.

## 6. External libraries

Zig can compile C directly, so a C dependency is often built from source into
the binary rather than linked from a `.a`:

```zig
exe.addCSourceFile(.{ .file = b.path("vendor/foo.c"), .flags = &.{"-O2"} });
exe.linkLibC();
```

⭐ **This sidesteps the "is there a `-static` package" problem** that dominates
C static builds.

## 7. TLS and certificates

⚠ **The standard library's `std.crypto.tls` is usable and less battle-tested
than OpenSSL or rustls.** Root certificates are the caller's problem;
`std.crypto.Certificate.Bundle.rescan` reads the host store.

## 8. DNS

⚠ **`std.net` resolution is limited.** With musl linked, `getaddrinfo` is
available through libc. Pure-Zig resolution is less complete than Go's or
Rust's ecosystem options.

## 9. Locale

⭐ **Zig's standard library does not use the C locale.** Formatting is
locale-independent.

## 10. Plugins

⛔ **`std.DynLib` needs a dynamic loader**, so it does not work in a static
binary. Rare in Zig.

## 11. Kernel

**documented**: Zig targets Linux 3.16 and up by default; a `.<version>` suffix
on a `gnu` target selects a glibc, not a kernel.

## 12. Reproducibility

⭐ **Good by construction.** Paths in the binary are relative by default, and
the build system is a Zig program rather than a shell script, so there is less
opportunity for a timestamp to leak in.

⚠ **`build.zig` is arbitrary Zig code** and can embed anything, including a
timestamp. Same class of risk as Rust's `build.rs`.

⚠ **`zig build` caches aggressively in `~/.cache/zig`.** Set `--cache-dir` and
`--global-cache-dir` inside the workspace, or the cache lands outside `/build`
and a path can leak.

## 13. Debugging and size

| mode | for |
| --- | --- |
| `Debug` | development |
| ⭐ `ReleaseSafe` | ⭐ **the default here**: optimised, bounds checks kept |
| `ReleaseFast` | ⚠ optimised, safety checks removed |
| `ReleaseSmall` | ⚠ smallest, safety checks removed |

⛔ **`ReleaseSafe` is the default on purpose.** A packaging system distributing
to unknown users should not silently remove memory-safety checks for a few
percent. A package choosing `ReleaseFast` or `ReleaseSmall` states why in a
`note`.

⚠ **The measured 12,952 bytes was `ReleaseSmall`.** `ReleaseSafe` is larger,
and the honest comparison against musl-gcc's `-O2` is therefore not
like-for-like on safety.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build]
image = "docker.io/library/alpine@sha256:..."

[[tool]]
name   = "zig"
url    = "https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz"
sha256 = "..."

[build.script]
run = """
zig build-exe src/main.zig -O ReleaseSafe -target "$ZIG_TARGET" \
  --cache-dir /build/.zig-cache --global-cache-dir /build/.zig-global \
  -femit-bin=out/prog
"""
```

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ the project does not build on this Zig | the language moved; pin the version the project targets |
| `zig cc` rejects a flag | ⚠ an autotools project passing gcc-only flags; wrap and filter |
| the cache is outside the workspace | `--cache-dir` not set; a path can leak into the artefact |
| a glibc target produces a dynamic binary | ⭐ expected; use a `-musl` target, or pin the glibc version deliberately |

**⛔ When not to**: the project needs a Zig version newer than any pinned image
carries and the language has moved under it; the project uses `std.DynLib`.
