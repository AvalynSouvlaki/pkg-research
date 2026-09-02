# toolchains

Selecting a compiler and linker, pinning them, and the flag sets this system
uses by default.

Which images carry which toolchain is
[`build-environments.md`](build-environments.md). Per-ecosystem detail is
[`languages/README.md`](languages/README.md). This document is **selection and
defaults**.

---

## 1. Selection

⛔ **A recipe does not name a compiler version. It names an image digest.** The
image is the toolchain pin; there is no second mechanism, because two
mechanisms means two things to keep in agreement.

```toml
[build]
image = "docker.io/library/rust@sha256:b4b54b17..."
```

⚠ **A recipe that installs a toolchain in its script has moved the pin into an
unpinned place.** `rustup toolchain install stable` inside `[build.script].run`
resolves to a different compiler each month.

⭐ **The one legitimate case** is a toolchain the image cannot carry, for
example a target's standard library added on demand:

```sh
rustup target add "$TARGET"      # adds a std for an already-pinned toolchain
```

That is adding a target to a pinned compiler, not choosing a compiler.

---

## 2. Linkers

| linker | when |
| --- | --- |
| GNU `ld.bfd` | the default; ⚠ slowest, most compatible |
| `ld.gold` | ⚠ deprecated and being removed; do not adopt |
| ⭐ `lld` | fast, ships with clang and with Zig |
| ⭐ `mold` | fastest for large link jobs |

```sh
gcc -fuse-ld=mold ...
clang -fuse-ld=lld ...
```

⚠ **Changing the linker changes the output bytes.** Section ordering and
padding differ, so a package that switches linkers is a rebuild with a new
revision, and its previously published artefact will not reproduce under the
new setting. The linker is part of the toolchain pin in practice, so it belongs
in the image rather than being switched per build.

⚠ **`mold`'s output has been reported as reproducible**, and this repository did
not verify that. Treat as documented, not measured. Where a package must be
reproducible, the safe path is to keep whichever linker produced the published
artefact.

---

## 3. Default flag sets

⭐ Applied by profile. A recipe overrides through `[build.env]` when it must,
and the override is visible in the metadata.

### 3.1 C and C++, `release`

```
-O2
-fstack-protector-strong
-D_FORTIFY_SOURCE=2
-ffile-prefix-map=/build=/opk
-static
-Wl,--build-id=none
-Wl,-z,relro
-Wl,-z,now
-Wl,--as-needed
```

| flag | for |
| --- | --- |
| `-ffile-prefix-map` | ⭐ reproducibility: the build path does not reach the artefact |
| `--build-id=none` | ⚠ or `=sha1` if a build-id is wanted; the point is that it is stated |
| `-z relro -z now` | read-only relocations, eager binding |
| `--as-needed` | drop unused `DT_NEEDED` entries; harmless when static |

⚠ **`-D_FORTIFY_SOURCE=2` requires optimisation to do anything**, and emits a
warning at `-O0`. `=3` is stronger and needs gcc 12 or clang 17 and up.

### 3.2 C and C++, `hardened`

Adds:

```
-D_FORTIFY_SOURCE=3
-fstack-clash-protection
-fcf-protection=full
-static-pie -fPIE
```

⚠ **`-fcf-protection` is x86-specific.** The aarch64 equivalent is
`-mbranch-protection=standard`. A flag set applied to the wrong architecture
produces a warning that is easy to lose in build output, so the profile applies
architecture-appropriate flags rather than one list.

### 3.3 Rust, `release`

```
RUSTFLAGS="-C target-feature=+crt-static \
           -C link-self-contained=yes \
           --remap-path-prefix=/build=/opk"
cargo build --release --locked --target "$TARGET"
```

| in `Cargo.toml` | value |
| --- | --- |
| `[profile.release] strip` | `true` |
| `lto` | `"thin"` |
| `codegen-units` | ⚠ `1` for smallest output, and it removes a parallelism-related source of variation |
| `panic` | ⚠ `"abort"` only when nothing calls `catch_unwind` |

⛔ **`--locked` is mandatory.** Without it, `cargo` may update `Cargo.lock` and
build something other than what was reviewed.

⚠ **Do not blindly rewrite a project's `[profile.release]`.** Era 1 of the
studied system did, with:

```sh
sed "/^\[profile\.release\]/,/^$/d" -i ./Cargo.toml
echo -e "\n[profile.release]\nstrip = true\nopt-level = 3\nlto = true" >> ./Cargo.toml
```

That deletes from the profile header to the next blank line, so a profile
written without a trailing blank line loses whatever followed it, and a
project's deliberate settings are discarded silently. Set flags through
environment variables, or patch with a real TOML editor.

### 3.4 Go, `release`

```sh
CGO_ENABLED=0 go build \
  -trimpath \
  -ldflags="-s -w -buildid=" \
  -o out/prog .
```

| flag | for |
| --- | --- |
| ⭐ `CGO_ENABLED=0` | static, and no glibc resolver. [`static-linking.md`](static-linking.md) §2.1. |
| ⭐ `-trimpath` | reproducibility |
| `-s -w` | drop the symbol table and DWARF |
| `-buildid=` | ⚠ empties Go's own build ID, which otherwise varies with the build path |

⚠ **`-s -w` and `-buildid=` interact with debugging.** A Go binary built this
way cannot be symbolised. Where debuggability matters, build twice: once
stripped for publication and once unstripped for the debuginfo referrer, per
[`static-linking.md`](static-linking.md) §8.

### 3.5 Zig

```sh
zig build-exe main.zig -O ReleaseSafe -target "$ZIG_TARGET"
```

⚠ **`ReleaseSafe` keeps bounds checks; `ReleaseFast` does not; `ReleaseSmall`
optimises for size and keeps checks off.** ⭐ `ReleaseSafe` is the default here:
a packaging system shipping to unknown users should not silently remove memory
safety checks to save a few percent.

---

## 4. Microarchitecture

⛔ **The default is the architecture baseline.** No `-march=native`, ever: it
produces a binary tuned for the *runner*, which is not the user's machine, and
the failure mode is `SIGILL` on hardware that is merely older.

A package publishing a raised level does so explicitly:

| level | gcc, clang | Rust |
| --- | --- | --- |
| base | `-march=x86-64` | default |
| v2 | `-march=x86-64-v2` | `-C target-cpu=x86-64-v2` |
| v3 | `-march=x86-64-v3` | `-C target-cpu=x86-64-v3` |
| v4 | `-march=x86-64-v4` | `-C target-cpu=x86-64-v4` |

⛔ **Publishing a raised level requires also publishing the base level**, per
[`../format/package-identity.md`](../format/package-identity.md) §5.1.

⭐ **Run-time dispatch is better than a build-time level where the software
supports it**: one binary that detects CPU features and selects an
implementation. It costs a little size and removes the whole problem.

---

## 5. What a recipe may override, and what it may not

| may | may not |
| --- | --- |
| add flags through `[build.env]` | ⛔ set `SOURCE_DATE_EPOCH`, `TZ`, `LC_ALL`, `PREFIX`, `TARGET`, `HOST` |
| choose a different image | ⛔ pass `--privileged` or change the container invocation |
| add `[[tool]]` | ⛔ install a toolchain from an unpinned source |
| disable a profile flag with a reason | ⛔ disable `-ffile-prefix-map` or `-trimpath` |

⛔ **The last row is the reproducibility floor.** A recipe that removes path
remapping produces an artefact that cannot reproduce on another machine, and the
validator rejects it rather than letting it publish something the weekly job
will flag a week later.
