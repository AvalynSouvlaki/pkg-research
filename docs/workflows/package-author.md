# package author workflow

Adding a package, from nothing to merged. ⭐ **Written to be followed, not
read.**

---

## 1. Before you start

⛔ **Three questions. A "no" to any changes the answer.**

| question | if no |
| --- | --- |
| does it already exist? | ⭐ `opk search NAME` first. A variant may be what you want. |
| ⭐ can it be a static binary? | [`../build/static-linking.md`](../build/static-linking.md) §7. If not, it may still be packageable with `portable = false`. |
| does upstream publish a static build already? | ⭐ ⚠ **prefer pinning theirs.** Building is work you take on forever. |

⭐ **The third question is the one people skip.** A package whose upstream
already ships a static musl binary should pin that URL and hash, not rebuild it.
The studied system's build repository states the same rule and requires a
`reason` field explaining why each package is built rather than pinned.

---

## 2. Scaffold

```sh
opk new ripgrep --from https://github.com/BurntSushi/ripgrep
```

Writes `packages/ripgrep/opk.toml` with identity and `[update]` filled in from
the forge, and the build section stubbed.

---

## 3. Fill in the recipe

Field reference:
[`../format/build-manifest.md`](../format/build-manifest.md).

```toml
[package]
name        = "ripgrep"
description = "Recursively search directories for a regex pattern"
homepage    = ["https://github.com/BurntSushi/ripgrep"]
license     = ["MIT", "Unlicense"]
maintainer  = ["Your Name <you@example.org>"]
provides    = ["rg"]
category    = ["ConsoleOnly", "Utility"]

[source]
git    = "https://github.com/BurntSushi/ripgrep"
commit = "4649aa9700d4dbaad0c85b0ac8b2c66e2b649b6c"

[update]
strategy = "github-releases"
repo     = "BurntSushi/ripgrep"

[build]
image = "docker.io/library/rust@sha256:b4b54b176a74db7e5c68fdfe6029be39a02ccbcfe72b6e5a3e18e2c61b57ae26"
hosts = ["x86_64-linux", "aarch64-linux"]
deps  = ["musl-dev"]

[build.target]
x86_64-linux  = "x86_64-unknown-linux-musl"
aarch64-linux = "aarch64-unknown-linux-musl"

[build.env]
RUSTFLAGS = "-C target-feature=+crt-static"

[build.script]
run = """
rustup target add "$TARGET"
cargo build --release --locked --target "$TARGET"
"""

[verify]
run = ["--version"]

[artifact]
"target/${target}/release/rg" = "bin/rg"
"LICENSE-MIT"                 = "share/licenses/ripgrep/LICENSE-MIT"
"COPYING"                     = "share/licenses/ripgrep/COPYING"
```

### 3.1 ⛔ Getting the pins

```sh
# the commit for a release tag
git ls-remote --tags https://github.com/BurntSushi/ripgrep | grep '14\.1\.1'

# the image digest
crane digest docker.io/library/rust:1.83-alpine
```

⛔ **A tag is not a pin.** `[source].commit` takes a full hash, and the
validator rejects anything else.

### 3.2 Where to look for the recipe

⭐ **Start from your ecosystem's file**:
[`../build/languages/README.md`](../build/languages/README.md). Each carries a
production default block that is close to a working recipe.

---

## 4. Build it locally

```sh
opk build ripgrep --host x86_64-linux
```

```
building ripgrep 14.1.1 for x86_64-linux (x86_64-unknown-linux-musl)
  fetch      commit verified 4649aa97
  run        251s
  collect    3 artefacts
  verify     bin/rg  x86_64  static  no PT_INTERP  5238784 bytes
             bin/rg --version -> ripgrep 14.1.1
  assemble   dist/ripgrep-14.1.1-1-x86_64-linux.tar.zst

  sha256  afb42bf28b19048dac5b970cb2474ead0f7ea02d1307a86104d18644f13a824f
  bytes   5242880
```

⚠ **No container runtime?** ⭐ Install rootless podman. `--no-container` works
and is degraded: no toolchain pinning, no isolation, and artefacts marked
unsandboxed which cannot be published.
[`../build/build-system.md`](../build/build-system.md) §6.

### 4.1 Inspect it

```sh
opk inspect dist/ripgrep-14.1.1-1-x86_64-linux.tar.zst
python3 tools/elfprobe.py --expect-static stage/bin/rg
```

⭐ **Look at the artefact, not only at the build output.** A build that
succeeded and produced the wrong thing is the failure this catches.

---

## 5. Iterate on failures

⭐ **The five most common, and what each means.**

| symptom | cause | fix |
| --- | --- | --- |
| ⛔ `cannot find -lz` | the static archive is missing | add `zlib-static` to `[build].deps` |
| ⛔ `dynamically linked against /lib64/ld-...` | the build linked dynamically | ⭐ check the target is `*-musl` and the static flag is set |
| ⛔ `built for e_machine 0x3e, expected aarch64` | ⭐ the cross-compile fell back to the native compiler | check `[build.target]` and the toolchain |
| ⛔ `artifact not produced: target/.../rg` | the path is wrong | run with `--keep` and look at the tree |
| `Killed`, exit 137 | out of memory | raise `[build].memory` |

```sh
opk build ripgrep --host x86_64-linux --keep --verbose
ls experiments/.work/...          # ⭐ the workspace survives with --keep
```

⭐ **`--keep` leaves the workspace**, which is how you find out what the build
actually produced when the artifact map does not match.

---

## 6. Build every declared host

```sh
for h in x86_64-linux aarch64-linux; do opk build ripgrep --host "$h" || break; done
```

⚠ **A cross-built artefact needs `[verify].run` to be worth much.** Compiling
for aarch64 on an x86-64 machine proves it compiled; running it under
`qemu-user` proves it starts.

---

## 7. Pin the release

```sh
opk resolve packages/ripgrep
opk pin packages/ripgrep
opk validate
```

Writes `packages/ripgrep/ripgrep-14.1.1-1.toml` with the resolved URL and
hashes per host.

⛔ **Never write a release file by hand.** It is generated, and a hand-written
one is a hash nobody computed.

---

## 8. Open the pull request

```sh
git switch -c add-ripgrep
git add packages/ripgrep
git commit -m "ripgrep: add 14.1.1"
git push -u origin add-ripgrep
```

⭐ **The pull request body should say why the package is built rather than
pinned from an upstream release**, if it is built. That is the question a
reviewer asks first.

---

## 9. The checklist

⛔ **Run through this before opening.** It is what a reviewer will check.

- [ ] `opk validate` passes
- [ ] `opk lint` passes
- [ ] it builds on every host in `[build].hosts`
- [ ] ⭐ the artefact has no `PT_INTERP`, or `portable = false` with a reason
- [ ] `[verify].run` is set, or there is a reason it cannot be
- [ ] ⛔ the image is pinned by digest, not by tag
- [ ] ⛔ `[source].commit` is a full hash, not a tag
- [ ] the licence ships under `share/licenses/<name>/`
- [ ] `provides` lists every program that reaches `bin/`
- [ ] ⛔ nothing in `[build.script]` fetches an unpinned URL
- [ ] ⭐ the description says what the tool does, not that it is good
- [ ] the name does not collide, and is not one typo from an existing package

---

## 10. After merge

| happens | you can |
| --- | --- |
| CI builds and publishes | watch the run |
| the artefact is signed | |
| the index regenerates | ⭐ `opk update && opk install ripgrep` |
| ⭐ the update bot takes over versions | ⭐ stop bumping by hand |
| a weekly job rebuilds and compares | ⚠ you may get a reproducibility issue |

⭐ **A reproducibility failure on your package is not an accusation.** It
usually means an unpinned `[build].deps` entry moved.
[`../build/reproducibility.md`](../build/reproducibility.md) §4.1 is the fix.

---

## 11. Maintaining it

| when | do |
| --- | --- |
| ⭐ a bot bump | ⭐ nothing, unless the build breaks |
| a build break after a bump | fix the recipe; that is the job |
| ⚠ upstream changes its build system | update `[build.script]` |
| ⚠ the base image digest ages | ⭐ a quarterly bot pull request bumps it |
| upstream is abandoned | ⛔ mark `disabled` **with a reason**, do not delete |

⛔ **A disabled package keeps its reason.** Era 1 carried 385 disabled recipes
with almost none recorded, so the next person to propose the package cannot find
out why it is not there.
