# Go

⭐ **measured** on the probe host, go 1.24.7. Go carries one trap, and this
file demonstrates it rather than describing it.

---

## 1. Fully static: yes, with one condition

| recipe | bytes | PT_INTERP |
| --- | ---: | --- |
| ⭐ `CGO_ENABLED=0 -trimpath -ldflags="-s -w -buildid="` | 1,433,748 | none |
| ⛔ `CGO_ENABLED=1` + `import "net"` | 3,161,314 | **`/lib64/ld-linux-x86-64.so.2`** |
| `CGO_ENABLED=0` + `import "net"` (the fix) | 2,019,476 | none |

⛔ **That middle row is the trap and it is measured, not warned about.**
Nothing in the source asks for dynamic linking. Importing `net` with cgo
enabled makes the toolchain use glibc's resolver, and the binary acquires a
`PT_INTERP`.

⭐ **It ran on the build host.** That is what makes it dangerous: the failure
happens on a user's machine with a different glibc, not in CI.

**The packages that trigger it**: `net`, `os/user`, `plugin`, and anything
importing them transitively. `net/http` imports `net`.

## 2. libc

⭐ **With `CGO_ENABLED=0`, none.** Go's runtime makes syscalls directly. There
is no libc in the binary and no libc on the host is consulted.

⚠ **With cgo, the build host's libc.** Building on Debian links glibc and the
binary needs a glibc at least that new on the user's machine. Building on
Alpine links musl.

## 3. Compiler and linker

| | |
| --- | --- |
| compiler | the `go` toolchain, pinned by image digest |
| linker | Go's internal linker with `CGO_ENABLED=0`; the external system linker with cgo |
| `-ldflags "-linkmode=external"` | ⚠ forces the system linker even without cgo; rarely wanted |

⚠ **`go.mod`'s `toolchain` directive can download a different Go version at
build time.** Set `GOTOOLCHAIN=local` to pin to the image's toolchain, or the
image digest is not the pin you think it is.

## 4. Cross-compilation

⭐ **The best in any ecosystem. Nothing to install.**

```sh
CGO_ENABLED=0 GOOS=linux GOARCH=riscv64 \
  go build -trimpath -ldflags="-s -w -buildid=" -o out/prog .
```

| host triple | `GOOS` | `GOARCH` | `GOARM` |
| --- | --- | --- | --- |
| `x86_64-linux` | linux | amd64 | |
| `aarch64-linux` | linux | arm64 | |
| `riscv64-linux` | linux | riscv64 | |
| `loongarch64-linux` | linux | loong64 | |
| `armv7-linux` | linux | arm | 7 |
| `x86_64-darwin` | darwin | amd64 | |
| `x86_64-windows` | windows | amd64 | |

⛔ **`CGO_ENABLED=0` is what makes it free.** With cgo, cross-compiling needs a
C cross toolchain and the result is dynamic.

## 5. CPU features

```sh
GOAMD64=v3 go build ...      # v1 default, v2, v3, v4
GOARM64=v8.2
```

⛔ **The default `GOAMD64=v1` is correct for distribution.** Raising it makes
the binary fail on older hardware.

⭐ Go's standard library does run-time feature detection internally, so
`crypto` and `hash` already use AVX where present without a build-time flag.

## 6. External libraries

⭐ **Usually none.** The Go ecosystem strongly prefers pure-Go implementations,
which is why static linking is the default experience here.

⚠ **Where cgo is unavoidable**, for example `mattn/go-sqlite3`, the choice is:

| option | trade |
| --- | --- |
| ⭐ a pure-Go replacement, for example `modernc.org/sqlite` | slower, sometimes; static |
| build with cgo on Alpine | musl-linked, needs `CGO_ENABLED=1` and a musl toolchain |
| ⛔ build with cgo on Debian | glibc-linked, dynamic, not portable |

## 7. TLS and certificates

⭐ **`crypto/x509` reads the host store**, trying the standard paths, and
honours `SSL_CERT_FILE` and `SSL_CERT_DIR`.

⚠ **A `scratch` container has no store**, and this surfaces as an
`x509: certificate signed by unknown authority` error that reads like a
certificate problem. For a package installed on a normal host it is not an
issue.

## 8. DNS

⭐ **`CGO_ENABLED=0` gives the pure-Go resolver**, which reads
`/etc/resolv.conf` and `/etc/hosts` directly.

⚠ **The pure-Go resolver ignores `nsswitch.conf` ordering** in the same way
musl does, so LDAP and mDNS resolution are unavailable. `GODEBUG=netdns=go` or
`netdns=cgo` selects at run time when cgo was compiled in; with
`CGO_ENABLED=0` only `go` exists.

## 9. Locale

Go's standard library does not use the C locale. `golang.org/x/text` carries its
own data. ⭐ **No locale dependency in a static Go binary.**

## 10. Plugins

⛔ **`plugin.Open` requires `CGO_ENABLED=1` and dynamic linking.** A Go program
using `plugin` is not a static package. It is rare.

## 11. Kernel

**documented**: Go 1.24 requires Linux 3.2 and up. ⚠ **The runtime uses
`epoll_pwait2` where available with a fallback**, so no raised floor from the
runtime. A program using `io_uring` through a library raises it to 5.1.

## 12. Reproducibility

⭐ **Go is the strongest ecosystem here.**

```sh
CGO_ENABLED=0 GOFLAGS=-mod=readonly GOTOOLCHAIN=local \
  go build -trimpath -ldflags="-s -w -buildid=" -o out/prog .
```

| control | effect |
| --- | --- |
| ⭐ `-trimpath` | removes the build path |
| ⭐ `-buildid=` | empties Go's own build ID, which otherwise varies with the path |
| ⭐ `go.sum` | checksums for every module |
| ⭐ the checksum database | detects a module that changed after publication |
| `-mod=readonly` | refuses to update `go.mod` silently |
| `GOTOOLCHAIN=local` | ⛔ stops `go.mod` pulling a different compiler |

⚠ **`-ldflags "-X main.version=..."` with a timestamp or a commit is common and
breaks reproducibility** unless the value is derived from
`SOURCE_DATE_EPOCH` and the source commit, both of which are pinned.

⭐ **Go embeds build info readable with `go version -m <binary>`**, which is a
useful provenance cross-check independent of our own metadata.

## 13. Debugging and size

Go binaries are large because the runtime and reflection metadata ship in every
one. `-s -w` removes the symbol table and DWARF, typically 25% to 30%.

⚠ **`-s -w` makes the binary unsymbolisable**, and Go panics print a stack
trace using its own tables, which survive `-w`. So panics stay readable while
`gdb` becomes useless. That is usually the right trade for a distributed tool.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build.env]
CGO_ENABLED  = "0"
GOFLAGS      = "-mod=readonly"
GOTOOLCHAIN  = "local"

[build.script]
run = """
go build -trimpath -ldflags="-s -w -buildid=" -o out/prog .
"""
```

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ the binary is dynamic although nothing asked for it | `CGO_ENABLED=1` with `net` or `os/user`. ⭐ The measured trap. |
| ⛔ fails on an older glibc | built with cgo on a newer distribution |
| `go: downloading go1.x` during a build | `go.mod` `toolchain`; set `GOTOOLCHAIN=local` |
| a rebuild does not reproduce | `-trimpath` or `-buildid=` missing, or a version stamp with a timestamp |
| ⚠ mDNS or LDAP names do not resolve | the pure-Go resolver; expected |

**⛔ When not to**: it uses `plugin`; it must link a C library with no pure-Go
equivalent and glibc-specific behaviour.
