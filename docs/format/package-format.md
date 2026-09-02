# package format

The on-disk shape of a package set, the two kinds of file in it, and the rule
that makes the whole tree safe to read.

Field-level schema is [`build-manifest.md`](build-manifest.md). Identity rules
are [`package-identity.md`](package-identity.md). This document owns the
**tree layout** and the **inertness rule**.

---

## 1. The tree

```
packages/
  <family>/
    opk.toml                       the recipe: identity, source, build, artifacts
    <name>-<version>-<revision>.toml   a pinned release, written by tooling
    patches/
      0001-fix-build.patch         optional, referenced by the recipe
    assets/
      icon.png                     optional
      <name>.desktop               optional
licenses/
  GPL-3.0.txt                      shared texts, for licences that require verbatim
keys/
  <keyid>.pub                      the public keys this repository publishes under
```

**MUST**: a family directory contains exactly one `opk.toml`.

**MUST**: a release file is named `<name>-<version>-<revision>.toml`, and the
name, version and revision inside it match the filename. A validator that finds
a mismatch rejects the file rather than preferring either source.

⚠ **The filename is a convenience for humans and for git, not an identity.**
Two files whose contents disagree with their names is a defect the validator
catches; a reader who trusts the name over the contents is reading it wrong.

---

## 2. Two files, two jobs

⭐ **This split is the single most important structural decision in the
format.** It is taken directly from the studied system's third era, where it
worked, and the reasoning transfers unchanged.

| | `opk.toml` | `<name>-<version>-<revision>.toml` |
| --- | --- | --- |
| **answers** | how this package is built, and how to find new versions | which exact bytes are version X |
| **written by** | a human | tooling (`opk resolve`, `opk pin`) |
| **changes when** | the build changes | a version is released |
| **read by** | the builder, the update bot | the index generator, the client |
| **contains** | a build script | no executable content of any kind |
| **review question** | is this build correct and safe | is this hash the artefact it claims |

**Why split at all.** A single file carrying both means every version bump
re-reviews the build script, and every build change re-reviews the hashes.
Splitting makes an automated version bump a diff a human can read in five
seconds: a version string, some hashes, some sizes.

⚠ **The release file is generated, and it is still reviewed.** A generated
file that nobody reads is a channel an attacker can use. The review question is
narrow but real, and [`../ci/update-automation.md`](../ci/update-automation.md)
says what a reviewer is looking for.

### EXAMPLE: a complete package

`packages/ripgrep/opk.toml`

```toml
[package]
name        = "ripgrep"
description = "Recursively search directories for a regex pattern"
homepage    = ["https://github.com/BurntSushi/ripgrep"]
license     = ["MIT", "Unlicense"]
maintainer  = ["Example Person <person@example.org>"]
provides    = ["rg"]
category    = ["ConsoleOnly", "Utility"]

[source]
git    = "https://github.com/BurntSushi/ripgrep"
commit = "4649aa9700d4dbaad0c85b0ac8b2c66e2b649b6c"

[update]
strategy     = "github-releases"
repo         = "BurntSushi/ripgrep"
strip-prefix = ""

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
"doc/rg.1"                    = "share/man/man1/rg.1"
```

`packages/ripgrep/ripgrep-14.1.1-1.toml`

```toml
version  = "14.1.1"
revision = 1

[artifact.x86_64-linux]
digest = "sha256:2fa1e0a0a0b8e5f0c9d3a6b2e4f7c1d8a5b3e9f2c6d0a4b8e1f5c9d3a7b2e6f0"
blake3 = "b3:0e5f0c9d3a6b2e4f7c1d8a5b3e9f2c6d0a4b8e1f5c9d3a7b2e6f04a1e0a0a0b8"
size   = 5242880

[artifact.aarch64-linux]
digest = "sha256:9c1d8a5b3e9f2c6d0a4b8e1f5c9d3a7b2e6f04a1e0a0a0b8e5f0c9d3a6b2e4f7"
blake3 = "b3:5c9d3a7b2e6f04a1e0a0a0b8e5f0c9d3a6b2e4f7c1d8a5b3e9f2c6d0a4b8e1f5"
size   = 5111808

[provenance]
source_commit = "4649aa9700d4dbaad0c85b0ac8b2c66e2b649b6c"
epoch         = 1714435200
built_at      = "2026-09-01T10:04:11Z"
```

⚠ **The digests above are illustrative and not real.** A worked example with
real, reproducible values is `experiments/30-oci-pipeline.sh`, which prints
them.

---

## 3. The inertness rule

⛔ **Parsing, validating, resolving or indexing a package tree MUST NOT execute
anything the tree contains.**

This is invariant I1 in [`../architecture.md`](../architecture.md). Concretely:

| operation | may run recipe content |
| --- | --- |
| `opk validate` | no |
| `opk resolve` | no |
| `opk pin` | no |
| index generation | no |
| a client resolving, downloading, verifying, installing | no |
| `opk build` | ⭐ yes, and only inside the container |

**What "execute" covers.** It is wider than running the `[build.script]`:

- No shelling out to a value from the file, even a version string.
- No template language with function calls. Substitution is limited to
  `${version}`, `${revision}`, `${arch}` and `${target}`, textually, with no
  expressions. [`build-manifest.md`](build-manifest.md) §substitution.
- No YAML tags, TOML extensions or anchors that trigger construction.
- No path in the file is used unsanitised as a filesystem or shell operand;
  every one is validated against the grammar first.

⚠ **The last point is the one implementations get wrong.** A recipe declaring
an artefact at `../../../../etc/cron.d/x` is not executing anything, and it is
still an attack. Path validation rules are in
[`build-manifest.md`](build-manifest.md) §paths, and the test that plants such
a recipe is in [`../testing.md`](../testing.md).

### HISTORICAL NOTE

Era 1 of the studied system placed a full shell script in `x_exec.run` and
another in `x_exec.pkgver`, and the second ran during *metadata* generation.
Learning what version a package was at meant executing a maintainer's shell
with a GitHub token in the environment. That is the specific shape this rule
exists to forbid, and
[`../history/references/README.md`](../history/references/README.md) has the
citations.

---

## 4. Multiple recipes for one program

Some programs are legitimately packaged more than one way: a stable and a
nightly channel, a build with and without a large optional dependency, or one
build from source alongside one repackaged from upstream.

**MUST**: each such build is its own family directory, with a distinct
`name`.

```
packages/
  ffmpeg/          name = "ffmpeg"
  ffmpeg-full/     name = "ffmpeg-full"
```

⚠ **Do not express variants as multiple recipes in one directory.** Era 1 did,
with filenames encoding type, provider and channel:
`static.nixpkgs.stable.yaml` beside `static.official.source.yaml`. It works
until a tool needs to know which is canonical, and then every consumer
reimplements the precedence rule from the filename. Variants that genuinely
belong to one package are declared inside the recipe;
[`variants-and-features.md`](variants-and-features.md) says how.

---

## 5. What is deliberately absent

| absent | why | where the need is met |
| --- | --- | --- |
| a dependency solver | statically linked artefacts have no runtime dependency graph to solve | [`dependencies.md`](dependencies.md) |
| pre- and post-install scripts | a package that runs code at install time can do anything a user can | [`../client/hooks.md`](../client/hooks.md) |
| a patch DSL | patches are files applied by the build script, which is already the escape hatch | [`build-manifest.md`](build-manifest.md) §patches |
| conditional expressions | they make a recipe a program, which defeats §3 | per-host tables in [`build-manifest.md`](build-manifest.md) |
| a global version constraint language | packages are self-contained, so cross-package constraints have almost nothing to constrain | [`dependencies.md`](dependencies.md) |

⚠ **The last row has a real exception and it is not hidden.** Packages that
provide the same binary name conflict, and that is resolved at install rather
than by a solver. [`../client/client-behaviour.md`](../client/client-behaviour.md)
§conflicts.
