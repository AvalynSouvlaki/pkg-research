# Fortran

⭐ **measured** on the probe host, GNU Fortran 13.3.0 against glibc.

---

## 1. Fully static: yes

**Measured**, `experiments/20-static-matrix.sh`:

| recipe | bytes | PT_INTERP |
| --- | ---: | --- |
| ⭐ `gfortran -O2 -static hello.f90` | 1,220,024 | none |

⭐ **Static linking worked with no adjustment**, one of only two languages here
for which that was true against glibc.

## 2. libc

| libc | status |
| --- | --- |
| ⭐ glibc | ⭐ **measured working** |
| musl | ⚠ possible; ⛔ `gfortran` is not commonly packaged against musl. Alpine ships `gfortran` linked against musl in its `gcc-gfortran` package, and this was not verified here. |

⚠ **`libgfortran` is the constraint, not the compiler.** A static build needs
`libgfortran.a`, which most distributions ship; a musl build needs one built
against musl.

## 3. Compiler and linker

| | |
| --- | --- |
| ⭐ gfortran | GCC's Fortran front end; the default |
| LLVM Flang | ⚠ newer, less exercised for static linking |
| Intel `ifx` | ⚠ proprietary; `-static-intel` statically links its own runtime |
| ⛔ pin | by image digest |

## 4. Cross-compilation

⚠ **Needs a cross gfortran**, same situation as Ada. ⭐ Build inside a container
for the target architecture instead.

## 5. CPU features

⛔ **This is the ecosystem where `-march=native` is most tempting and most
harmful.** Numerical code benefits substantially from AVX, and a package built
with `native` on a CI runner fails with `SIGILL` on older hardware.

⭐ **The right answer here is run-time dispatch or explicit levels**, and for
numerical libraries specifically, publishing per-microarchitecture variants:

```
prog-1.0.0-1-x86_64-linux        baseline
prog-1.0.0-1-x86_64-v3-linux     AVX2
```

per [`../../format/package-identity.md`](../../format/package-identity.md) §5.1.

⚠ **Publishing only the raised level makes the package silently unavailable on
older hardware.** The base level is mandatory.

## 6. External libraries

⚠ **BLAS and LAPACK are the dominant dependency and the dominant problem.**

| implementation | static | note |
| --- | --- | --- |
| Reference BLAS, LAPACK | ⭐ yes | slow, portable, small |
| OpenBLAS | ⭐ yes, `libopenblas.a` | ⚠ builds a per-CPU dispatch table; see below |
| Intel MKL | yes | ⚠ proprietary, licensing |
| ATLAS | ⚠ tuned at build time to the build machine | ⛔ do not distribute |

⛔ **ATLAS auto-tunes to the machine it is built on.** A distributed binary
containing it is tuned for a CI runner and may be slower or may crash
elsewhere.

⭐ **OpenBLAS with `DYNAMIC_ARCH=1` builds every kernel and selects at run
time**, which is the correct choice for a distributed package. It is larger.

## 7. TLS and certificates

⚠ Rare in Fortran. Where present, through a C binding, so
[`c-cpp.md`](c-cpp.md) §7.

## 8. DNS

⛔ Through glibc, statically, so NSS is unavailable. Rarely relevant.

## 9. Locale

⚠ **Fortran list-directed output formats numbers in the C locale**, and
`gfortran` does not follow `LC_NUMERIC` by default. Consistent, which is what a
package wants.

## 10. Plugins

Not applicable.

## 11. Kernel

**documented**: inherits glibc's floor.

## 12. Reproducibility

| control | |
| --- | --- |
| build path | ⭐ `-ffile-prefix-map=/build=/opk` |
| ⚠ module files | `.mod` files are compiler-version-specific intermediates; they must not be shipped |
| ⚠ parallel compilation | module dependencies can make `make -j` order-dependent; use a correct dependency graph or `-j1` |
| ⛔ OpenMP thread count | ⚠ affects results, not bytes; irrelevant to reproducibility of the artefact |

⚠ **`.mod` files embed the gfortran version.** A build that ships them
produces an artefact usable only with that exact compiler, which is not what a
binary package should contain. Keep them out of the `[artifact]` map.

## 13. Debugging and size

`-g` then `strip --strip-all`. Measured 1,220,024 bytes unstripped for
hello-world; ⚠ most of it is glibc's static runtime plus `libgfortran`.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build]
image = "docker.io/library/debian@sha256:..."
deps  = ["gfortran", "libopenblas-dev"]
deps_via = "apt"

[build.script]
run = """
gfortran -O2 -static -ffile-prefix-map=/build=/opk \
  -march=x86-64 \
  -o out/prog src/*.f90 -lopenblas
"""

[verify]
run = ["--version"]
```

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ `SIGILL` on older hardware | `-march=native` reached the flags, or ATLAS was linked |
| undefined BLAS symbols | the static BLAS archive is missing |
| numerical results differ between builds | ⚠ `-ffast-math` or a different BLAS; ⛔ not a packaging problem, and it is a real one |
| a `.mod` file shipped | it was matched by the artifact map |

**⛔ When not to**: the package depends on MKL under a licence that forbids
redistribution; it needs ATLAS.
