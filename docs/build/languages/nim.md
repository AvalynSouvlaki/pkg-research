# Nim

**documented**, not measured: the probe host had no Nim. ⭐ Nim compiles to C,
so its static story is C's story, which makes it one of the easier ecosystems.

---

## 1. Fully static: yes

```sh
nim c -d:release --opt:size --passL:-static -o:out/app src/app.nim
```

⭐ **Nim emits C and hands it to a C compiler**, so with `musl-gcc` as that
compiler the result is an ordinary static musl binary.

```sh
nim c -d:release --cc:gcc --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc \
      --passL:-static -o:out/app src/app.nim
```

## 2. libc

| libc | note |
| --- | --- |
| ⭐ musl | ⭐ **the default here**, through `musl-gcc` |
| glibc | ⚠ works, inherits every glibc-static limit |

⚠ **Nim's default garbage collector and the newer ORC memory management both
work statically.** `--mm:orc` is the modern default and has no bearing on
linkage.

## 3. Compiler and linker

| | |
| --- | --- |
| Nim compiler | ⛔ pin by image digest or a hashed `[[tool]]` |
| backend C compiler | `musl-gcc`, `gcc`, `clang`, or ⭐ `zig cc` |
| linker | whatever the C compiler uses |

⭐ **`zig cc` as the backend is the cleanest cross-compilation route:**

```sh
nim c -d:release --cpu:arm64 --os:linux \
      --cc:clang --clang.exe:"zig cc" --clang.linkerexe:"zig cc" \
      --passC:"-target aarch64-linux-musl" \
      --passL:"-target aarch64-linux-musl -static" \
      -o:out/app src/app.nim
```

## 4. Cross-compilation

`--cpu:` and `--os:` select the target; the backend C compiler must be a cross
compiler. ⭐ Zig supplies it for every target in one tool.

**Nim CPU names**: `amd64`, `arm64`, `riscv64`, `arm`, `i386`.

⚠ **Nim's own `--cpu` names differ from every other convention here.** The
recipe's `[build.target]` maps host triples to whatever the toolchain wants, and
Nim is a good example of why that table exists.

## 5. CPU features

Passed through to the C compiler: `--passC:"-march=x86-64-v2"`. ⛔ Not
`native`.

## 6. External libraries

Nim binds to C libraries with `{.dynlib.}` or static linking pragmas.

⛔ **`{.dynlib: "libfoo.so".}` is a run-time `dlopen`.** A Nim package using it
is not static. Replace with `{.header.}` plus `--passL:-lfoo` and a static
archive.

⚠ **This is the most common Nim static-build failure** and it is invisible
until run time, because the binary links fine and fails to find the library when
the pragma is first reached.

## 7. TLS and certificates

`std/httpclient` uses OpenSSL. ⚠ **By default it `dlopen`s `libssl.so` at run
time**, which is the same trap as §6. Build with `-d:ssl` and link OpenSSL
statically, or use a pure-Nim TLS binding.

## 8. DNS

Through libc `getaddrinfo`. musl's resolver applies.

## 9. Locale

Nim's standard library does not depend on the C locale for its own formatting.

## 10. Plugins

⛔ `dynlib` does not work in a static binary.

## 11. Kernel

**documented**: inherits the libc floor.

## 12. Reproducibility

| control | |
| --- | --- |
| build path | ⭐ passed through to the C compiler: `--passC:-ffile-prefix-map=/build=/opk` |
| ⚠ `nimcache` | Nim writes generated C into a cache directory; set `--nimcache:/build/.nimcache` so it stays inside the fixed path |
| ⛔ dependencies | `nimble` resolves at build time; commit a lockfile and use `nimble install --depsOnly` against it |

⚠ **Nim's generated C can embed the source path in `#line` directives**, which
reach debug info. `-ffile-prefix-map` on the backend handles it.

## 13. Debugging and size

`-d:release` plus `--opt:size` plus `strip --strip-all`. ⭐ Nim binaries are
small by the standards of garbage-collected languages because the runtime is
minimal and dead code is eliminated at the C level.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build]
image = "docker.io/library/alpine@sha256:..."
deps  = ["nim", "musl-dev", "gcc"]

[build.script]
run = """
nim c -d:release --opt:size --mm:orc \
      --cc:gcc --gcc.exe:musl-gcc --gcc.linkerexe:musl-gcc \
      --passC:-ffile-prefix-map=/build=/opk \
      --passL:-static \
      --nimcache:/build/.nimcache \
      -o:out/app src/app.nim
"""
```

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ "could not load: libssl.so" at run time | a `{.dynlib.}` pragma; link statically instead |
| the binary is dynamic | `--passL:-static` omitted, or a `dynlib` pragma forced it |
| a rebuild does not reproduce | `nimcache` outside the fixed path |
| a different dependency version each build | ⛔ `nimble` unpinned |

**⛔ When not to**: the project depends on `{.dynlib.}` bindings it cannot
replace.
