# C and C++

⭐ **measured** on the probe host. See [`README.md`](README.md) for the label
meanings.

---

## 1. Fully static: yes

Measured, `experiments/20-static-matrix.sh`:

| recipe | bytes | PT_INTERP |
| --- | ---: | --- |
| `gcc -static` glibc | 785,360 | none |
| `gcc -static-pie` glibc | 822,552 | none |
| ⭐ `musl-gcc -static` | 24,744 | none |
| ⭐ `musl-gcc -static`, stripped | **17,816** | none |
| `clang -static` glibc | 793,712 | none |
| `g++ -static -static-libstdc++` | 2,330,568 | none |

## 2. libc

| libc | static | recommendation |
| --- | --- | --- |
| ⭐ **musl** | designed for it | ⭐ **the default** |
| glibc | ⚠ works, 44x larger, ⛔ no NSS, ⛔ `dlopen` broken | only when something genuinely needs it |
| uClibc-ng | works | embedded targets only |

**C++ standard library:**

| | flag | note |
| --- | --- | --- |
| libstdc++ | `-static-libstdc++ -static-libgcc` | ⭐ the common case with g++ |
| libc++ | `-stdlib=libc++ -static` | clang; needs `libc++.a` and `libc++abi.a` present |

⚠ **`-static-libstdc++` alone does not make a static binary.** It statically
links the C++ runtime and leaves libc dynamic. `-static` is what removes
`PT_INTERP`; the other two flags matter when you want a mostly-dynamic binary
that does not depend on the host's libstdc++.

## 3. Compiler and linker

| | |
| --- | --- |
| compilers | gcc, clang, `zig cc` |
| linkers | `ld.bfd` default, ⭐ `lld` or `mold` for speed |
| ⛔ pin | by image digest, [`../build-environments.md`](../build-environments.md) |

## 4. Cross-compilation

⭐ **`zig cc` is the highest-leverage option**: one tool, every target.

```sh
zig cc  -target aarch64-linux-musl -O2 -static hello.c   -o hello
zig c++ -target riscv64-linux-musl -O2 -static hello.cpp -o hello
```

Conventional route:

```sh
apt-get install -y gcc-aarch64-linux-gnu
./configure --host=aarch64-linux-gnu --build=x86_64-linux-gnu
```

⚠ **`--host` is the target and `--build` is the machine.** Reversing them
produces a native binary and a confusing failure much later.

**Target triples**: `<arch>-<vendor>-<os>-<abi>`, for example
`aarch64-unknown-linux-musl`. Zig uses the shorter `aarch64-linux-musl`.

## 5. CPU features

⛔ **Never `-march=native`.** It targets the runner, not the user. Use an
explicit level: `-march=x86-64`, `-march=x86-64-v2`, `-march=x86-64-v3`.

⭐ **Run-time dispatch is better where the code supports it**:
`__builtin_cpu_supports()` with GCC function multi-versioning, or
`ifunc` resolvers. ⚠ `ifunc` in a fully static binary is supported by glibc's
static startup but has historically been fragile; test it rather than assuming.

## 6. External libraries

⛔ **Every library must have a `.a`.** A distribution ships `libfoo-dev` with a
shared object and often no static archive.

| library | static archive package on Alpine |
| --- | --- |
| zlib | `zlib-static` |
| OpenSSL | `openssl-libs-static` |
| ncurses | `ncurses-static` |
| SQLite | `sqlite-static` |
| libxml2 | `libxml2-static` |

⚠ **Alpine splits `-static` into its own package, and its absence is the single
most common static build failure.** The error is a link error naming a symbol,
not a message about a missing package.

⛔ **`pkg-config --static --libs` is the right way to get the link line.**
Without `--static` it omits the transitive dependencies a static link needs.

## 7. TLS and certificates

A static binary has no certificate store. [`../../format/dependencies.md`](../../format/dependencies.md) §5.1.

| library | static | note |
| --- | --- | --- |
| OpenSSL | ⭐ yes | reads the host store; honours `SSL_CERT_FILE`, `SSL_CERT_DIR` |
| GnuTLS | yes | more transitive dependencies |
| mbedTLS, BearSSL | ⭐ yes, small | ⚠ no host store integration; you supply the roots |

⚠ **OpenSSL compiles in a default `OPENSSLDIR`.** A binary built on Alpine
looks in `/etc/ssl` and finds nothing on a Fedora host. Build with the search
paths you intend, and honour the environment overrides.

## 8. DNS and name service

⛔ **glibc static: NSS unavailable**, `dlopen`-based. The link warns; the
warning is one of hundreds.

⭐ **musl static: works.** Its resolver is built in and reads `/etc/resolv.conf`
and `/etc/hosts` directly.

⚠ **musl's resolver differs from glibc's**: queries all nameservers in
parallel, a 512-byte UDP buffer that can truncate large responses where glibc
retries over TCP, and no `nsswitch.conf` support at all. For command-line tools
this is invisible; for service discovery it is not.

## 9. Locale

| | |
| --- | --- |
| glibc | full locale support, and ⛔ static builds still need locale *data* on the host |
| ⭐ musl | `C` and `C.UTF-8` only |

⚠ **Software calling `setlocale(LC_ALL, "")` and formatting numbers behaves as
`C` under musl.** Usually desirable for a tool; a real difference for anything
user-facing.

## 10. Plugins

⛔ **`dlopen` does not work in a static musl binary and works badly in a static
glibc one**, requiring the exact shared glibc it was linked against at the same
path. A program with a plugin architecture is not a static package;
[`../static-linking.md`](../static-linking.md) §7.

## 11. Kernel

**documented**: glibc requires Linux 3.2 or newer, musl 2.6.39 or newer. A
package using `statx` (4.11), `openat2` (5.6) or `io_uring` (5.1) declares
`min-kernel`.

## 12. Reproducibility

| control | flag |
| --- | --- |
| ⭐ build path | `-ffile-prefix-map=/build=/opk` |
| timestamps | `SOURCE_DATE_EPOCH`, honoured for `__DATE__` and `__TIME__` |
| build-id | `-Wl,--build-id=none` or `=sha1` |
| ⚠ link order | ⛔ `make -j1` for the link step where the build system links in completion order |

⚠ **Autotools embeds the build triple in `config.status`**, which is fine, and
some projects also record a hostname. Grep the artefact for the hostname during
verification; check V4 in
[`../build-system.md`](../build-system.md) §2.8 does.

## 13. Debugging and size

⭐ `-g` then `objcopy --only-keep-debug`, `--add-gnu-debuglink`, `strip
--strip-all`. [`../static-linking.md`](../static-linking.md) §8.

Size: musl over glibc is the 44x lever. Then `strip`, then `-Os`, then LTO,
then `--gc-sections` with `-ffunction-sections -fdata-sections`.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```sh
CC=musl-gcc
CFLAGS="-O2 -static -fstack-protector-strong -D_FORTIFY_SOURCE=2 \
        -ffile-prefix-map=/build=/opk"
LDFLAGS="-static -Wl,--build-id=none -Wl,-z,relro -Wl,-z,now -Wl,--as-needed"
```

Verify with `tools/elfprobe.py --expect-static`.

**Failure modes**

| symptom | cause |
| --- | --- |
| link error naming a symbol from a system library | ⛔ the `-static` package for it is not installed |
| ⛔ `dlopen`, `gethostbyname` warnings at link time | glibc static; switch to musl |
| binary works on the builder, fails on the user's machine | ⚠ it is not actually static. Check `PT_INTERP`. |
| `SIGILL` on older hardware | ⛔ `-march=native` reached the flags |
| TLS failures on some distributions | a compiled-in `OPENSSLDIR` that does not exist there |
| ⛔ hostname resolution works for DNS, fails for LDAP or mDNS | glibc static NSS |

**⛔ When not to**: it needs `dlopen`; it is a shared library; it needs full
locale or `iconv`; it needs glibc NSS integration; it is a GUI application
depending on host toolkits.
