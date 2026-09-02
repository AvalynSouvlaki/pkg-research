# Crystal

**documented**, not measured: the probe host had no Crystal.

---

## 1. Fully static: yes, with friction

```sh
crystal build --release --static --no-debug -o out/app src/app.cr
```

⭐ **`--static` is a first-class flag** and Crystal's own documentation
recommends Alpine for it.

⚠ **The friction is the dependency set.** Crystal's runtime links libpcre2,
libgc (Boehm), libevent, libyaml, libxml2 and OpenSSL depending on what the
program uses, and each needs a static archive present. On Alpine:

```sh
apk add crystal shards musl-dev \
        pcre2-dev pcre2-static \
        gc-dev libevent-static \
        openssl-dev openssl-libs-static \
        zlib-static yaml-dev yaml-static \
        libxml2-dev libxml2-static
```

⛔ **Missing one produces a link error naming a symbol**, not a message about a
package. That is the dominant Crystal static-build failure.

## 2. libc

| libc | note |
| --- | --- |
| ⭐ musl, on Alpine | ⭐ **the supported static path** |
| glibc | ⚠ `--static` against glibc works and inherits every glibc-static limit |

## 3. Compiler and linker

| | |
| --- | --- |
| compiler | `crystal`, LLVM-based |
| linker | the system linker through `cc` |
| ⛔ pin | by image digest |

⚠ **Crystal before 1.0 changed often; it is stable now, and shard
compatibility still moves.** Pin both the compiler and the shard lock.

## 4. Cross-compilation

⚠ **Supported and awkward.** `--cross-compile` emits an object file and prints
the link command to run on the target:

```sh
crystal build --release --cross-compile --target aarch64-alpine-linux-musl src/app.cr
```

⭐ **In practice, building inside a container for the target architecture,
under emulation if necessary, is simpler than Crystal's cross-compile flow.**
Slower, and it works without a second manual step.

## 5. CPU features

`--mcpu` passes through to LLVM. ⛔ Not `native`.

## 6. External libraries

§1. ⭐ **`--link-flags` and `@[Link]` annotations control it**; the
`--static` flag makes Crystal prefer `.a` where it finds one.

## 7. TLS and certificates

OpenSSL, statically linkable with `openssl-libs-static`. ⚠ **The compiled-in
`OPENSSLDIR` problem applies**: a binary built on Alpine looks in `/etc/ssl`.
Honour `SSL_CERT_FILE`.

## 8. DNS

Through libc, so musl's resolver on Alpine. ⚠ **Crystal's event loop resolves
names on a thread pool**, which does not change the resolver's behaviour.

## 9. Locale

Not locale-dependent for its own formatting.

## 10. Plugins

⛔ No plugin mechanism that would need `dlopen`. Not a constraint here.

## 11. Kernel

**documented**: inherits musl's floor. ⚠ Crystal's event loop uses `epoll` on
Linux, present since 2.6.

## 12. Reproducibility

⚠ **Least documented area of this ecosystem.**

| control | |
| --- | --- |
| build path | ⭐ rely on the fixed `/build`; Crystal has no path-remapping flag |
| ⛔ `shard.lock` | must be committed; `shards install --frozen` refuses to update it |
| ⚠ macros | Crystal macros run at compile time and can read the environment or the clock |

⛔ **`shards install --frozen`, not `shards install`.** Without it the lock can
be updated and the build is not the one that was reviewed.

## 13. Debugging and size

`--no-debug` omits debug info; `strip --strip-all` after. ⚠ Crystal binaries
carry the Boehm collector and the runtime, so they are larger than Rust or Zig
for equivalent programs.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build]
image = "docker.io/crystallang/crystal@sha256:..."
deps  = ["pcre2-static", "openssl-libs-static", "zlib-static",
         "yaml-static", "libxml2-static", "libevent-static", "gc-dev"]

[build.script]
run = """
shards install --frozen --production
crystal build --release --static --no-debug -o out/app src/app.cr
"""

[verify]
run = ["--version"]
```

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ link error naming an OpenSSL, pcre or yaml symbol | the `-static` package for it is missing |
| `--static` on Debian produces a binary that fails elsewhere | glibc static; use Alpine |
| a rebuild does not reproduce | `shard.lock` not frozen, or a macro read the clock |
| the binary is very large | expected; the runtime and collector ship in it |

**⛔ When not to**: a dependency has no static archive on Alpine and cannot be
vendored.
