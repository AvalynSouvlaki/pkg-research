# Rust

⭐ **measured** on the probe host, rustc 1.94.1.

---

## 1. Fully static: yes

| recipe | bytes | PT_INTERP |
| --- | ---: | --- |
| ⭐ `--target x86_64-unknown-linux-musl`, `crt-static` | 541,832 | none |
| `--target x86_64-unknown-linux-gnu`, `crt-static` | 1,393,680 | none |

⭐ **The musl target is 2.6x smaller than static glibc for the same program.**

⚠ **`*-linux-musl` links `crt-static` by default; `*-linux-gnu` does not.** The
flag is redundant for the first and required for the second, and setting it in
both places is what makes a recipe portable between them.

## 2. libc

| target | libc | note |
| --- | --- | --- |
| ⭐ `x86_64-unknown-linux-musl` | musl | ⭐ **the default here** |
| `x86_64-unknown-linux-gnu` | glibc | dynamic by default; static with `crt-static` |
| `*-linux-musl` for other arches | musl | ⭐ same story |

⚠ **`+crt-static` on a gnu target is supported and is not the same as a musl
build.** It produces a large binary that still has glibc's static limitations:
no NSS, `dlopen` broken. The measured 1,393,680 bytes against 541,832 is the
visible half of that trade.

## 3. Compiler and linker

| | |
| --- | --- |
| compiler | `rustc` through `cargo`, pinned by image digest |
| linker | ⭐ `rust-lld` for musl targets by default in recent versions; `-C linker=clang -C link-arg=-fuse-ld=mold` for speed |
| ⛔ | `rust-toolchain.toml` in a project overrides the pinned toolchain |

⚠ **A project's `rust-toolchain.toml` will pull a different compiler over the
network.** Either honour it deliberately, or set `RUSTUP_TOOLCHAIN` to the
pinned one. ⛔ **Deleting it, as era 1 of the studied system did with `rm
rust-toolchain*`, is the wrong fix**: some projects genuinely need a specific
toolchain and the build then fails in a confusing way.

## 4. Cross-compilation

```sh
rustup target add riscv64gc-unknown-linux-musl
cargo build --release --locked --target riscv64gc-unknown-linux-musl
```

⚠ **That is enough only for pure-Rust dependency trees.** Any crate with C in
it, and that is most non-trivial trees, needs a C cross toolchain that `rustup`
does not provide.

⭐ **`cargo-zigbuild` supplies it:**

```sh
cargo zigbuild --release --locked --target riscv64gc-unknown-linux-musl
```

**Target triples**: `x86_64-unknown-linux-musl`,
`aarch64-unknown-linux-musl`, `riscv64gc-unknown-linux-musl`,
`armv7-unknown-linux-musleabihf`, `loongarch64-unknown-linux-musl`.

⚠ **`riscv64gc`, not `riscv64`.** The `gc` names the required extension set,
and the short form is not a valid Rust target.

## 5. CPU features

```sh
RUSTFLAGS="-C target-cpu=x86-64-v2"
```

⛔ **Never `-C target-cpu=native`.**

⭐ Run-time dispatch through `std::arch::is_x86_feature_detected!` is available
and preferable.

## 6. External libraries

⚠ **`*-sys` crates are where static builds fail.**

| crate | how to make it static |
| --- | --- |
| `openssl-sys` | ⭐ prefer `rustls` instead; or `OPENSSL_STATIC=1` with `OPENSSL_DIR` |
| `libz-sys` | feature `static` |
| `libsqlite3-sys` | ⭐ feature `bundled`, which compiles SQLite in |
| `ring` | vendors its own C and assembly; ⭐ works, needs a C cross compiler |
| `pq-sys`, `mysqlclient-sys` | ⚠ genuinely hard; prefer a pure-Rust driver |

⭐ **The general answer in Rust is a `vendored` or `bundled` feature**, which
compiles the C dependency from source into the crate. It is more common in this
ecosystem than in any other and it is why Rust static builds are usually easy.

## 7. TLS and certificates

| stack | store |
| --- | --- |
| `rustls` + `rustls-native-certs` | ⭐ **recommended**: pure Rust, reads the host store |
| `rustls` + `webpki-roots` | ⛔ a bundle compiled in, frozen at build time |
| `native-tls` | OpenSSL on Linux; the C build problem returns |

⛔ **`webpki-roots` is the trap.** It is the default in several tutorials, it
works, and the root set ages with the binary. A root removed for cause is still
trusted; a newly required root is missing. Use it only where the endpoint set is
fixed and known.

## 8. DNS

⭐ **A musl-target Rust binary uses musl's resolver.** `std::net::ToSocketAddrs`
calls `getaddrinfo`, which musl implements internally.

⚠ **Async runtimes often use their own resolver.** `hickory-dns` and
`trust-dns` are pure Rust and read `/etc/resolv.conf` themselves, which is
fine, and means the behaviour is theirs rather than libc's.

## 9. Locale

Rust's standard library does not use locale for formatting; numbers and dates
format the same everywhere. ⭐ **This removes a whole class of difference**, and
it means a crate that *does* use locale is doing it through a C dependency.

## 10. Plugins

⛔ **`libloading` and `dlopen` do not work in a static binary.** A plugin
architecture in Rust usually means dynamic linking, and such a package is not
static.

⚠ **Proc macros are a build-time thing and do not affect the artefact.**

## 11. Kernel

**documented**: Rust's Linux targets require kernel 3.2 and up; `*-musl`
inherits musl's floor. `std` uses `statx` where available with a fallback, so
no raised floor from the standard library alone.

## 12. Reproducibility

```sh
RUSTFLAGS="--remap-path-prefix=/build=/opk -C target-feature=+crt-static"
cargo build --release --locked
```

| | |
| --- | --- |
| ⛔ `--locked` | mandatory; without it `Cargo.lock` may be rewritten |
| `codegen-units = 1` | ⚠ removes a parallelism-related source of variation, at build-time cost |
| ⭐ `Cargo.lock` | per-crate checksums, so the dependency set is pinned |
| ⚠ `build.rs` | ⛔ arbitrary code at build time; may embed a timestamp or a path |

⚠ **`build.rs` is the reproducibility risk in this ecosystem.** A build script
calling `SystemTime::now()` or reading an environment variable produces a
different artefact each run. There is no way to detect this except by
rebuilding and comparing.

## 13. Debugging and size

| lever | effect |
| --- | --- |
| ⭐ `strip = true` in `[profile.release]` | large |
| `opt-level = "z"` | 10% to 20% |
| `lto = "fat"` | 5% to 20% |
| `codegen-units = 1` | 5% |
| ⚠ `panic = "abort"` | 10% to 15%; ⛔ removes `catch_unwind` |
| `build-std` with `panic_immediate_abort` | large; ⚠ nightly only |

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build]
image = "docker.io/library/rust@sha256:..."

[build.target]
x86_64-linux  = "x86_64-unknown-linux-musl"
aarch64-linux = "aarch64-unknown-linux-musl"

[build.env]
RUSTFLAGS = "-C target-feature=+crt-static --remap-path-prefix=/build=/opk"

[build.script]
run = """
rustup target add "$TARGET"
cargo build --release --locked --target "$TARGET"
"""
```

**Failure modes**

| symptom | cause |
| --- | --- |
| `openssl-sys` fails to build | ⭐ switch to `rustls`, or set `OPENSSL_STATIC` and `OPENSSL_DIR` |
| a `*-sys` crate fails when cross-compiling | ⭐ use `cargo-zigbuild` |
| ⛔ TLS fails months after release | `webpki-roots` frozen at build time |
| the wrong compiler is used | a `rust-toolchain.toml` in the project |
| `cargo` rewrites `Cargo.lock` | ⛔ `--locked` was omitted |
| the binary is dynamic on a gnu target | `+crt-static` not set |

**⛔ When not to**: it loads plugins with `libloading`; it depends on a C
library with no static or vendored path; it is a `cdylib` for another language.
