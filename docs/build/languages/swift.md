# Swift

**documented**, not measured: the probe host had no Swift toolchain.

⚠ **The static-Linux story changed recently and much advice online predates
it.** Swift 6.0 introduced a fully static musl SDK; before that, static linking
on Linux meant static Swift runtime plus dynamic glibc.

---

## 1. Fully static: yes, since Swift 6.0

```sh
swift sdk install \
  https://download.swift.org/swift-6.0.2-release/static-sdk/swift-6.0.2-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz \
  --checksum <sha256>

swift build -c release --swift-sdk x86_64-swift-linux-musl
```

⭐ **That SDK produces a fully static musl binary with no `PT_INTERP`.**

**Older approach**, still seen and weaker:

```sh
swift build -c release -Xswiftc -static-stdlib
```

⚠ **`-static-stdlib` links the Swift runtime statically and leaves glibc
dynamic.** The binary still needs a compatible glibc and still names a loader.
It is not what this system means by static.

## 2. libc

| target | libc | note |
| --- | --- | --- |
| ⭐ `*-swift-linux-musl` | musl | ⭐ **the default here**, Swift 6.0 and up |
| `*-unknown-linux-gnu` | glibc | ⚠ dynamic, or static-stdlib only |

## 3. Compiler and linker

| | |
| --- | --- |
| compiler | `swiftc` through Swift Package Manager |
| linker | `lld` in the static SDK |
| ⛔ pin | the toolchain by image digest, and the SDK by its published checksum |

⭐ **The SDK install takes a `--checksum`**, so it is a pinnable input and
belongs in the recipe as such.

## 4. Cross-compilation

⭐ **The static SDK cross-compiles**: install it once, then

```sh
swift build -c release --swift-sdk aarch64-swift-linux-musl
```

**Triples**: `x86_64-swift-linux-musl`, `aarch64-swift-linux-musl`. ⚠ riscv64
is not in the published static SDK as of Swift 6.0.

## 5. CPU features

`-Xcc -march=x86-64-v2` passes through to the C backend. ⛔ Not `native`.

## 6. External libraries

⚠ **Foundation is large and pulls in ICU, libcurl and libxml2 historically.**
Swift 6's rewritten `swift-foundation` removes much of that, which is a
significant part of why static linking became practical.

⛔ **A package importing `FoundationNetworking` pulls in libcurl.** Prefer
`AsyncHTTPClient` or `URLSession` from swift-foundation where possible.

## 7. TLS and certificates

⚠ **`swift-nio-ssl` uses BoringSSL, vendored and statically linked.** Root
certificates come from the host store through NIOSSL's default trust roots,
which read the standard paths. ⚠ Behaviour differs from the libcurl path, so a
package switching HTTP clients may change its certificate behaviour.

## 8. DNS

Through libc `getaddrinfo`, so musl's resolver under the static SDK. ⚠ NIO's
resolver can be configured to use its own, which changes the behaviour.

## 9. Locale

⚠ **Foundation historically depended on ICU for locale, collation and date
formatting**, which is a large data dependency. swift-foundation reduces this.
A package doing locale-aware formatting must check what its Foundation version
does under musl.

## 10. Plugins

⛔ `dlopen` unavailable statically. Swift's own plugin mechanism is
compile-time, so this is rarely a constraint.

## 11. Kernel

**documented**: inherits musl's floor.

## 12. Reproducibility

| control | |
| --- | --- |
| build path | ⚠ `-Xswiftc -debug-prefix-map=/build=/opk` |
| ⭐ `Package.resolved` | commit it; ⛔ build with `--disable-automatic-resolution` so it cannot change |
| ⚠ macros | Swift macros run at build time and are arbitrary code |

⚠ **Swift macros are compiled and executed during the build**, which is the
same class of reproducibility risk as Rust's `build.rs`.

## 13. Debugging and size

`-Xswiftc -g` for symbols; `strip --strip-all` after. ⚠ **Swift binaries are
large**: the runtime, reflection metadata and Foundation add several megabytes
even for small programs. `-Xswiftc -Osize` helps.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[build]
image = "docker.io/swift@sha256:..."

[build.script]
run = """
swift sdk install "$SWIFT_STATIC_SDK_URL" --checksum "$SWIFT_STATIC_SDK_SHA"
swift build -c release --swift-sdk "$TARGET" \
  --disable-automatic-resolution \
  -Xswiftc -debug-prefix-map -Xswiftc /build=/opk
"""

[verify]
run = ["--version"]
```

**Failure modes**

| symptom | cause |
| --- | --- |
| the binary still names a loader | ⛔ `-static-stdlib` used instead of the static SDK |
| a libcurl or ICU symbol is missing | `FoundationNetworking` or locale-aware Foundation pulled in |
| ⚠ the toolchain is Swift 5 | the static SDK needs 6.0 and up |
| `Package.resolved` changes during a build | automatic resolution not disabled |

**⛔ When not to**: the toolchain available is older than 6.0; the package needs
riscv64, which the static SDK does not publish; it depends on
`FoundationNetworking` and libcurl cannot be linked statically.
