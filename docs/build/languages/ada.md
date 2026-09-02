# Ada

⭐ **measured** on the probe host, GNATMAKE 13.3.0 against glibc.

---

## 1. Fully static: yes

**Measured**, `experiments/20-static-matrix.sh`:

| recipe | bytes | PT_INTERP |
| --- | ---: | --- |
| ⭐ `gnatmake -O2 hello.adb -bargs -static -largs -static` | 1,347,848 | none |

⭐ **Ada was one of the two languages that linked statically against glibc with
no adjustment**, the other being Fortran. Its runtime does not use the
`dlopen`-based machinery that broke D.

⚠ **`-bargs -static -largs -static` is two different flags to two different
tools.** `-bargs` goes to the binder and `-largs` to the linker. Passing only
one produces a partially static binary, and the mistake is easy to make.

## 2. libc

| libc | status |
| --- | --- |
| ⭐ glibc | ⭐ **measured working**, statically |
| musl | ⚠ possible with a musl-targeted GNAT; ⛔ not in most distributions' packages |

⚠ **This is the one ecosystem here where glibc is the pragmatic default**,
because a musl GNAT is not commonly packaged. The consequence is the usual
glibc-static set: no NSS, `dlopen` warnings, and a 1.3 MB floor.

⭐ **Alire, Ada's package manager, can install a GNAT toolchain**, and
`gnat-musl` builds exist. Where one is available, prefer it.

## 3. Compiler and linker

| | |
| --- | --- |
| compiler | GNAT, the GCC Ada front end |
| build driver | ⭐ `gprbuild` for real projects; `gnatmake` for single files |
| linker | the system linker |
| ⛔ pin | by image digest |

## 4. Cross-compilation

⚠ **Needs a cross GNAT built for the target**, which is significant work. There
is no equivalent of Zig's universal toolchain.

⭐ **In practice, build inside a container for the target architecture.** For
architectures with no runner, that means emulation, which for Ada's typically
small codebases is usually tolerable.

## 5. CPU features

`-march=x86-64-v2` through `-cargs`. ⛔ Not `native`.

## 6. External libraries

Ada binds to C with `pragma Import`. The C static-archive problem applies:
[`c-cpp.md`](c-cpp.md) §6.

⚠ **GNAT's runtime itself may need `-lgnat -lgnarl` explicitly** when linking
through a non-GNAT driver. Using `gnatmake` or `gprbuild` for the link avoids
it.

## 7. TLS and certificates

Through a C binding, usually OpenSSL via `GNATCOLL` or `AWS`. ⚠ **AWS
(Ada Web Server) links OpenSSL or GnuTLS**, and static linking it carries the
usual certificate-path caveat.

## 8. DNS

⛔ **Through glibc, statically, so NSS is unavailable.** An Ada program
resolving names gets DNS and `/etc/hosts` and nothing else. For most Ada
software this is irrelevant.

## 9. Locale

Ada's `Ada.Text_IO` formatting is locale-independent. ⚠ Bindings that call C
locale functions get the libc's behaviour.

## 10. Plugins

⛔ Not idiomatic in Ada. Not a constraint.

## 11. Kernel

**documented**: inherits glibc's floor, 3.2 and up.

## 12. Reproducibility

| control | |
| --- | --- |
| build path | ⭐ `-cargs -ffile-prefix-map=/build=/opk`, GCC's flag applies |
| timestamps | ⚠ `GNAT.Calendar` used at compile time is rare |
| ⭐ `gprbuild` | deterministic given the same sources and switches |
| ⚠ Alire | ⛔ resolves dependencies at build time; commit `alire.lock` |

⚠ **GNAT writes `.ali` files recording the build environment.** They are build
artefacts, not shipped, so they do not reach the published bytes. Confirm they
are not swept up by the `[artifact]` map.

## 13. Debugging and size

`-g` then `strip --strip-all`. Measured 1,347,848 bytes unstripped for a
hello-world. ⚠ Much of that is the glibc static runtime rather than Ada's.

⚠ **`-gnatp` suppresses run-time checks and shrinks the binary.** ⛔ Do not:
Ada's run-time checks are a large part of why the language is chosen, and
removing them to save space in a distributed package is the wrong trade.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build]
image = "docker.io/library/debian@sha256:..."
deps  = ["gnat", "gprbuild"]
deps_via = "apt"

[build.script]
run = """
gprbuild -P app.gpr -XBUILD=release \
  -cargs -O2 -ffile-prefix-map=/build=/opk \
  -bargs -static \
  -largs -static
"""

[verify]
run = ["--version"]
```

**Failure modes**

| symptom | cause |
| --- | --- |
| the binary is partially dynamic | ⛔ only one of `-bargs -static` and `-largs -static` was passed |
| `dlopen`, `gethostbyname` link warnings | ⚠ expected for glibc static; ignore or move to a musl GNAT |
| undefined `__gnat_*` symbols | linking without `gnatmake` or `gprbuild` |
| a rebuild does not reproduce | Alire dependencies not locked |

**⛔ When not to**: the package must be musl-linked and no musl GNAT is
available; it needs glibc NSS.
