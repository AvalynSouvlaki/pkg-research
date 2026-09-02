# D

⭐ **partly measured**: `gdc` against glibc was measured here and **does not
link**. LDC against musl is **documented**, not measured.

---

## 1. Fully static: yes with LDC, ⛔ no with gdc against glibc

**Measured**, `experiments/20-static-matrix.sh`:

```
gdc -O2 -static hello.d
  libgphobos.a(elf.o): undefined reference to `__tls_get_addr'
  collect2: error: ld returned 1 exit status
```

⛔ **The reason is structural, not a missing package.** `libgphobos` resolves
thread-local storage ranges through `__tls_get_addr`, which the dynamic loader
provides and a fully static link does not. The same link also warns that
`dlopen` and `gethostbyname` in a static binary need the shared glibc it was
linked against, which is the glibc-static NSS problem again.

⭐ **Use LDC against musl.** LDC is the LLVM-based D compiler and it supports
`-static` with musl.

```sh
ldc2 -O2 -release --static -mtriple=x86_64-alpine-linux-musl app.d -of=app
```

⚠ **Not measured here**: the probe host had no LDC. The Alpine package is
`ldc`, and a recipe using it should verify the result with
`tools/elfprobe.py --expect-static`, which is mandatory anyway.

## 2. libc

| compiler | libc | static |
| --- | --- | --- |
| ⭐ LDC on Alpine | musl | ⭐ works |
| LDC on Debian | glibc | ⚠ inherits glibc-static limits |
| ⛔ gdc | glibc | ⛔ does not link, measured |
| DMD | glibc | ⚠ the reference compiler, weakest for this purpose |

**Runtime**: `druntime` plus `phobos` are D's standard library, statically
linked into the binary by default under LDC.

## 3. Compiler and linker

| | |
| --- | --- |
| ⭐ LDC (`ldc2`) | LLVM-based, best cross-compilation and optimisation |
| DMD | the reference; fastest compiles, weakest codegen |
| ⛔ gdc | GCC-based; measured failing for static glibc |
| linker | LLVM `lld` through LDC, or the system linker |

## 4. Cross-compilation

⭐ **LDC cross-compiles with `-mtriple`**, and needs a matching `druntime` and
`phobos` for the target.

```sh
ldc2 -mtriple=aarch64-alpine-linux-musl --static -O2 app.d -of=app
```

⚠ **The target runtime libraries are the constraint.** `ldc-build-runtime`
builds them for a target, which is real work per architecture. In practice a
container per target architecture is simpler than cross-compiling D.

## 5. CPU features

```sh
ldc2 -mcpu=x86-64-v2 ...
```

⛔ Not `-mcpu=native`.

## 6. External libraries

D binds to C directly, so the C static-archive problem applies unchanged:
[`c-cpp.md`](c-cpp.md) §6.

## 7. TLS and certificates

⚠ **`std.net.curl` in phobos links libcurl**, which pulls in a TLS stack and
its certificate handling. Static linking libcurl and its dependencies is
possible and awkward. A D package doing HTTPS is better off with `vibe.d` or a
direct OpenSSL binding it can control.

## 8. DNS

Through libc. musl's resolver under LDC on Alpine; the glibc-static NSS problem
otherwise.

## 9. Locale

Phobos formatting is largely locale-independent. ⚠ Code calling C's `setlocale`
through a binding gets the libc's behaviour, so musl's `C`-only locale applies.

## 10. Plugins

⛔ D's `Runtime.loadLibrary` uses `dlopen`. Not available in a static binary.

## 11. Kernel

**documented**: inherits the libc floor. No D-specific requirement.

## 12. Reproducibility

⚠ **Least explored of the compiled languages here.**

| control | |
| --- | --- |
| build path | ⚠ LDC has no documented equivalent of `-ffile-prefix-map`; ⭐ rely on building at the fixed `/build` |
| timestamps | `__DATE__` equivalents exist in D and are rare |
| ⛔ `dub` | ⚠ resolves dependencies at build time; use `dub.selections.json` to pin |

⛔ **`dub.selections.json` must be committed and the build run with
`--skip-registry=all` where possible**, or the dependency set is not pinned.

## 13. Debugging and size

`-g` for symbols, `strip --strip-all` after. `-Os` through LDC's
`--Oz`. Phobos is large; a hello-world LDC static binary is typically over a
megabyte, ⚠ documented rather than measured here.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build]
image = "docker.io/library/alpine@sha256:..."
deps  = ["ldc", "musl-dev"]

[build.script]
run = """
ldc2 -O2 -release --static -of=out/app src/app.d
"""

[verify]
run = ["--version"]
```

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ `undefined reference to __tls_get_addr` | ⭐ **measured**: gdc against glibc, statically. Use LDC with musl. |
| `dlopen` and `gethostbyname` link warnings | glibc static; same fix |
| `dub` fetches a different dependency set | ⛔ `dub.selections.json` not committed |
| the binary is dynamic | `--static` omitted, or the target is not musl |

**⛔ When not to**: the project needs gdc specifically; it uses
`Runtime.loadLibrary`; it depends on libcurl through phobos and static linking
that proves impractical.
