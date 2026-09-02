# opk

**A specification for a package manager and binary distribution system built
on OCI registries, with GitHub Container Registry as the reference host.**

This repository contains no shipped product. It contains the specification an
engineering team implements to build one, the research that justifies every
decision in it, and runnable proofs that the load-bearing parts work.

⭐ **If you read one other file, read
[`docs/architecture.md`](docs/architecture.md).** It is the technical
reference, and where any other document disagrees with it, it is right and the
other document is the defect.

---

## Who this is for, and where to start

| you are | start at | then |
| --- | --- | --- |
| implementing this from nothing | this file, in order | [`docs/architecture.md`](docs/architecture.md), then [the minimum path](#the-minimum-implementation-path) |
| deciding whether to adopt it | [Why it exists](#why-it-exists), then [`docs/history/references/README.md`](docs/history/references/README.md) | [`docs/decisions/README.md`](docs/decisions/README.md) |
| packaging software with it | [`docs/workflows/package-author.md`](docs/workflows/package-author.md) | [`docs/format/build-manifest.md`](docs/format/build-manifest.md) |
| installing software with it | [`docs/workflows/end-user.md`](docs/workflows/end-user.md) | [`docs/client/cli.md`](docs/client/cli.md) |
| operating it | [`docs/workflows/maintainer.md`](docs/workflows/maintainer.md) | [`docs/ops/operations.md`](docs/ops/operations.md) |
| auditing it | [`docs/security/security-model.md`](docs/security/security-model.md) | [`docs/security/supply-chain.md`](docs/security/supply-chain.md) |
| checking our work | [`experiments/README.md`](experiments/README.md) | run them; they exit non-zero when they fail |

⚠ **No prior knowledge is assumed.** If a word here is unfamiliar,
[`docs/terminology.md`](docs/terminology.md) defines it, including *package
manager*, *OCI*, *GHCR*, *registry*, *manifest*, *digest*, *static linking* and
*provenance*.

---

## What is being designed

A system that takes a declaration like this:

```toml
[package]
name    = "ripgrep"
version = "14.1.1"
revision = 1

[source]
git    = "https://github.com/BurntSushi/ripgrep"
commit = "4649aa9700d4dbaad0c85b0ac8b2c66e2b649b6c"

[build]
image = "docker.io/library/rust@sha256:3f4a1e6ee9d0f2b8c5a7b1d9e0c3f5a7b9d1e3f5a7b9c1d3e5f7a9b1c3d5e7f9"
hosts = ["x86_64-linux", "aarch64-linux"]

[build.script]
run = "cargo build --release --locked --target $TARGET"

[artifact]
"target/${target}/release/rg" = "bin/rg"
```

and turns it into a **statically linked binary** that any user on any Linux
distribution installs with one command, with no root, no dependency
resolution, and no risk of breaking their system:

```sh
opk install ripgrep
```

The binary, its metadata, its SBOM, its signature, its build provenance and
its complete build log all live in an **OCI registry** as content-addressed
artifacts. The client verifies every one before anything touches disk.

**The properties that define it:**

| property | what it means | specified in |
| --- | --- | --- |
| **inert declarations** | a package definition is data. Reading or resolving one never executes anything from it. | [`docs/format/package-format.md`](docs/format/package-format.md) |
| **contained execution** | building does run a script, but only inside a digest-pinned container, from a commit-pinned source, on a machine that is thrown away | [`docs/build/build-system.md`](docs/build/build-system.md) |
| **content addressing** | every artefact is named by the hash of its bytes. A tag is a convenience; a digest is the truth. | [`docs/registry/oci-ghcr.md`](docs/registry/oci-ghcr.md) |
| **reproducibility** | an independent rebuild produces the same bytes, so the builder is not a party you have to trust | [`docs/build/reproducibility.md`](docs/build/reproducibility.md) |
| **static linking by default** | one binary runs on any Linux of the same architecture, regardless of its libc | [`docs/build/static-linking.md`](docs/build/static-linking.md) |
| **evidence attached** | SBOM, provenance, signature and build log are discoverable from the package itself | [`docs/security/sbom-and-provenance.md`](docs/security/sbom-and-provenance.md) |

---

## Why it exists

⚠ This section is history. It explains the shape of the design. Nothing here
is a rule; the rules are in the documents linked above.

Installing a command-line tool on Linux is worse than it should be. The
distribution's package manager has an old version and needs root. Building
from source needs a toolchain. Language package managers only cover their own
language. Downloading a release binary from a forge works right up until it is
linked against a newer glibc than the machine has, and then it fails with a
message about `GLIBC_2.38 not found` that tells the user nothing they can act
on.

The direct answer is a **static binary**: one file, no dependencies, runs
anywhere with the same CPU architecture and a roughly compatible kernel. The
hard part is not the idea. It is producing those binaries for thousands of
programs, keeping them current, and giving users a reason to trust them.

### Two real systems tried, and each solved half of it

This specification is built on a close reading of one project that attempted
exactly this, twice, in opposite directions. The full sweep, with commits and
line citations, is in
[`docs/history/references/README.md`](docs/history/references/README.md).

**The first attempt built everything.** Each package carried a shell script
that fetched source and compiled it, and CI ran those scripts and pushed the
results to GHCR with the build log attached. It worked, and users could click
from a package page straight to the log of the build that produced the binary
they were about to install.

It also carried 871 hand-written build scripts, no two of which were identical
in any respect. **385 of them, 44%, were disabled** at the commit examined.
Measured by build strategy, the split is stark:

| strategy | files | disabled | rate |
| --- | ---: | ---: | ---: |
| `nix` | 96 | 3 | 3.1% |
| `go build` | 194 | 8 | 4.1% |
| `cargo build` | 156 | 11 | 7.1% |
| hand-written C build systems | 25 | 23 | 92.0% |
| Python packaging | 12 | 11 | 91.7% |

⭐ **Strategies with one uniform way to link statically survived. Strategies
needing bespoke per-package work did not.** That single table is the strongest
empirical result in the sweep and it shapes this entire design.

Worse, the scripts ran with real credentials and arbitrary shell. And because
version strings came out of unvalidated shell pipelines, corrupted versions
reached the public index: the live entry for `bash` records version `445.3p3`
for what upstream calls `5.3p3`, because a `jq` expression emitted several
matches and `tr -d '[:space:]'` concatenated them.

**The second attempt built nothing.** It replaced every script with inert
TOML: a URL, a hash, and a size, per package per architecture. Nothing in the
tree executes. A version bump is a small diff a human can review, and a
changed hash on an unchanged version is a visible signal that upstream
replaced an artefact in place.

That fixed the safety problem and the maintenance problem at once. It also
gave up the ability to build anything. The system now depends on upstream
projects publishing static binaries themselves, and when they do not, the
package cannot exist. Build logs, provenance and the whole GHCR artefact model
went with it.

### What this design does about that

**Keep the second attempt's inert package tree. Add back the first attempt's
building, in a box.**

A package definition remains data. Building is a separate, explicit act that
happens in a pinned container and produces a signed, reproducible artefact
with its log and provenance attached. The tree that a client reads still
contains no code.

The rest of this specification is the detail of how.

---

## The major components

```
                    ┌──────────────────────────────────────┐
   package author → │  RECIPE  (opk.toml, inert TOML)      │
                    │  identity, source pin, build script, │
                    │  artifact map, host list             │
                    └──────────────┬───────────────────────┘
                                   │  reviewed in a pull request
                    ┌──────────────▼───────────────────────┐
                    │  BUILDER                             │
                    │  digest-pinned container,            │
                    │  SOURCE_DATE_EPOCH from the commit,  │
                    │  normalised env, verified output     │
                    └──────────────┬───────────────────────┘
                                   │  produces bytes + a log
                    ┌──────────────▼───────────────────────┐
                    │  OCI REGISTRY  (GHCR)                │
                    │  package manifest ── referrers:      │
                    │    payload layer     signature       │
                    │    metadata layer    SBOM            │
                    │                      provenance      │
                    │                      build log       │
                    └──────────────┬───────────────────────┘
                                   │  digest-addressed
                    ┌──────────────▼───────────────────────┐
                    │  INDEX  (generated, signed)          │
                    │  name → version → digest, searchable │
                    └──────────────┬───────────────────────┘
                                   │
                    ┌──────────────▼───────────────────────┐
   end user      →  │  CLIENT  (opk)                       │
                    │  resolve, verify, install, roll back │
                    └──────────────────────────────────────┘
```

Each box is specified in its own document:

| component | document | one line |
| --- | --- | --- |
| recipe | [`docs/format/build-manifest.md`](docs/format/build-manifest.md) | every field, its type, its default, its validation rule |
| identity | [`docs/format/package-identity.md`](docs/format/package-identity.md) | names, versions, revisions, hosts, and what makes two packages the same |
| builder | [`docs/build/build-system.md`](docs/build/build-system.md) | the execution contract and the sandbox around it |
| registry | [`docs/registry/oci-ghcr.md`](docs/registry/oci-ghcr.md) | repository layout, media types, manifests, referrers, GHCR's limits |
| index | [`docs/registry/index-and-search.md`](docs/registry/index-and-search.md) | how a client finds a package without walking the registry |
| client | [`docs/client/client-behaviour.md`](docs/client/client-behaviour.md) | resolution, verification, installation, rollback, garbage collection |
| CLI | [`docs/client/cli.md`](docs/client/cli.md) | every command, flag, exit code and output format |
| CI | [`docs/ci/ci-system.md`](docs/ci/ci-system.md) | the workflows, their triggers, and their permissions |

---

## The package lifecycle

One package, from idea to installed, with the document that specifies each step.

| # | step | who | specified in |
| --- | --- | --- | --- |
| 1 | write `opk.toml`, pin source by commit and toolchain by image digest | author | [`docs/format/build-manifest.md`](docs/format/build-manifest.md) |
| 2 | build locally, inspect the artefact, iterate | author | [`docs/workflows/developer.md`](docs/workflows/developer.md) |
| 3 | open a pull request | author | [`docs/ci/pull-requests.md`](docs/ci/pull-requests.md) |
| 4 | CI validates the recipe without executing it | machine | [`docs/testing.md`](docs/testing.md) |
| 5 | CI builds it in a throwaway container and reports | machine | [`docs/ci/ci-system.md`](docs/ci/ci-system.md) |
| 6 | a maintainer reviews the diff and the build result | maintainer | [`docs/workflows/maintainer.md`](docs/workflows/maintainer.md) |
| 7 | on merge, the artefact is published, signed, and attested | machine | [`docs/security/signing-and-attestations.md`](docs/security/signing-and-attestations.md) |
| 8 | the index is regenerated and signed | machine | [`docs/registry/index-and-search.md`](docs/registry/index-and-search.md) |
| 9 | a user installs it, verifying every hop | user | [`docs/client/client-behaviour.md`](docs/client/client-behaviour.md) |
| 10 | a bot notices a new upstream version and opens a pull request | machine | [`docs/ci/update-automation.md`](docs/ci/update-automation.md) |
| 11 | a scheduled job rebuilds and compares bytes | machine | [`docs/build/reproducibility.md`](docs/build/reproducibility.md) |
| 12 | old versions age out under a stated retention policy | machine | [`docs/registry/retention.md`](docs/registry/retention.md) |

## The user lifecycle

`opk install` → `opk list` → `opk upgrade` → `opk rollback` → `opk remove`,
with `opk why`, `opk verify` and `opk log` available at every point. All of it
is [`docs/client/cli.md`](docs/client/cli.md); the ergonomics arguments are in
[`docs/workflows/end-user.md`](docs/workflows/end-user.md).

## The maintainer lifecycle

Triage, review, merge, watch the rebuild, respond to a reproducibility
failure, and take a package down when it must go. That is
[`docs/workflows/maintainer.md`](docs/workflows/maintainer.md), and the
operational side, including what to do when the registry is unavailable, is
[`docs/ops/operations.md`](docs/ops/operations.md).

---

## How the documents relate

Nothing normative is stated twice. Where a document needs a fact another
document owns, it links rather than repeating, so the two cannot drift apart.

```
README.md ......................... you are here. Orientation only.
│
├── docs/architecture.md .......... ⭐ THE TECHNICAL REFERENCE. Wins conflicts.
├── docs/terminology.md .......... every term, defined once
├── docs/principles.md ........... the rules that decided the design
├── docs/requirements.md ......... numbered, testable requirements
│
├── docs/format/ ................. what a package IS
├── docs/registry/ ............... where it LIVES
├── docs/build/ .................. how it is MADE
│   └── languages/ ............... static linking, one file per ecosystem
├── docs/security/ ............... why you may believe it
├── docs/client/ ................. what the user's machine does
├── docs/ci/ ..................... what the robots do
├── docs/workflows/ .............. what each kind of human does
├── docs/ops/ .................... running it for years
├── docs/decisions/ .............. every decision, with alternatives and cost
└── docs/history/ ................ what was believed, and why that changed
```

[`docs/README.md`](docs/README.md) is the full map, one row per file.

---

## The minimum implementation path

⭐ **A team can have a working system with the first five items.** Everything
after is hardening and scale. Each links to the document that specifies it,
and each has an acceptance check you can run.

| # | build | you can then | specified in |
| --- | --- | --- | --- |
| 1 | the recipe parser and validator | reject a malformed package without executing it | [`docs/format/build-manifest.md`](docs/format/build-manifest.md) |
| 2 | the local builder | produce an artefact on your own machine | [`docs/build/build-system.md`](docs/build/build-system.md) |
| 3 | the publisher | push a package to a registry with correct media types | [`docs/registry/oci-ghcr.md`](docs/registry/oci-ghcr.md) |
| 4 | the index generator | let a client find a package by name | [`docs/registry/index-and-search.md`](docs/registry/index-and-search.md) |
| 5 | the client: resolve, verify, install | install software end to end | [`docs/client/client-behaviour.md`](docs/client/client-behaviour.md) |
| 6 | signing and verification | let a user refuse an unsigned package | [`docs/security/signing-and-attestations.md`](docs/security/signing-and-attestations.md) |
| 7 | CI build and publish | stop building on laptops | [`docs/ci/ci-system.md`](docs/ci/ci-system.md) |
| 8 | SBOM and provenance | answer "what is in this and who made it" | [`docs/security/sbom-and-provenance.md`](docs/security/sbom-and-provenance.md) |
| 9 | build-log publication and retrieval | let a user read the build of their binary | [`docs/ci/build-logs.md`](docs/ci/build-logs.md) |
| 10 | the update bot | stop bumping versions by hand | [`docs/ci/update-automation.md`](docs/ci/update-automation.md) |
| 11 | the reproducibility job | detect a builder that has been tampered with | [`docs/build/reproducibility.md`](docs/build/reproducibility.md) |
| 12 | mirrors and offline operation | survive a registry outage | [`docs/client/offline-and-airgap.md`](docs/client/offline-and-airgap.md) |

**The full production path** adds cross-compilation for architectures with no
runner ([`docs/build/cross-compilation.md`](docs/build/cross-compilation.md)),
non-Linux targets ([`docs/compatibility.md`](docs/compatibility.md)), delta
updates and client garbage collection
([`docs/client/delta-and-gc.md`](docs/client/delta-and-gc.md)), trust policies
([`docs/security/trust-and-verification.md`](docs/security/trust-and-verification.md)),
and the operational work in [`docs/ops/`](docs/ops/operations.md).

⚠ **Do not start at item 6.** Signing a system whose artefacts are not yet
content-addressed produces a signature over something that can still change
underneath it. The order above is the dependency order, and
[`docs/decisions/0009-implementation-order.md`](docs/decisions/0009-implementation-order.md)
says why.

---

## How to run the proof-of-concept examples

The examples are not illustrations. They are scripts in
[`experiments/`](experiments/), they run on an ordinary Linux machine with no
root and no registry account, and **they exit non-zero when they fail**.

```sh
bash experiments/10-probe-host.sh          # what this machine can prove
bash experiments/20-static-matrix.sh       # static linking, per toolchain
bash experiments/30-oci-pipeline.sh        # the whole lifecycle, locally
bash experiments/40-registry-conformance.sh  # what a real registry implements
bash experiments/41-referrers-fallback.sh  # discovery without a referrers API
```

`30-oci-pipeline.sh` is the one to run first if you only run one. It starts a
spec-conformant registry on loopback, builds a static binary, publishes it with
an SBOM, provenance, a build log and a signature, discovers them through the
registry, verifies them, installs the result, rebuilds it byte-for-byte, and
publishes a deliberately failed build in a form no client will install. It
made 30 assertions and passed all 30 on the host recorded in
`experiments/out/10-probe-host.txt`.

[`experiments/README.md`](experiments/README.md) explains what each answers,
what it needs, and what it does not establish.
[`docs/poc/README.md`](docs/poc/README.md) maps each example to the part of the
specification it demonstrates.

---

## What this specification does not establish

⛔ Read this before the recommendations, not after.

- **Nothing here has been run at production scale.** The measurements come
  from one machine on one day, named in `experiments/out/10-probe-host.txt`.
  Claims about thousands of packages are inferred from the historical
  system's numbers, and are labelled as inference where they appear.
- **No package has been published to a real GHCR namespace.** GHCR was probed
  read-only and anonymously. Everything involving a push is demonstrated
  against a local registry, and
  [`docs/registry/oci-ghcr.md`](docs/registry/oci-ghcr.md) lists precisely
  which GHCR behaviours remain unverified and the command that would verify
  each.
- **Windows, macOS and BSD are specified but not measured here.** The host was
  Linux. [`docs/compatibility.md`](docs/compatibility.md) marks every
  non-Linux claim as unverified.
- **Several language toolchains were unavailable on the probe host.** Rows in
  [`docs/build/static-linking.md`](docs/build/static-linking.md) are marked
  measured or documented, never silently mixed.
- **The tracker sweep could not read GitHub Discussions.** The credential-free
  route is REST and discussions are GraphQL only, so a design argument that
  happened there is missing from
  [`docs/history/references/README.md`](docs/history/references/README.md).
- **The review passes corrected real errors in earlier drafts of these
  documents.** They are listed in
  [`docs/history/README.md`](docs/history/README.md). ⚠ Assume more remain.

---

## Repository layout

| path | what is in it |
| --- | --- |
| [`docs/`](docs/README.md) | the specification |
| [`experiments/`](experiments/README.md) | runnable proofs, numbered in the order they were written |
| [`tools/`](tools/) | the instruments the experiments use, chiefly `elfprobe.py` |
| [`references/`](references/) | the mined trackers of the systems studied, kept so a claim can be re-checked |
| [`CHANGELOG.md`](CHANGELOG.md) | what changed here, newest first |
| [`SECURITY.md`](SECURITY.md) | the threat model of this repository itself |
| [`AGENTS.md`](AGENTS.md) | the router, for an agent picking up this work |

---

## Conventions these documents follow

Normative strength is marked, and the marking is the contract:

| word | means |
| --- | --- |
| **MUST** / **MUST NOT** | an implementation that does otherwise is not conformant |
| **SHOULD** / **SHOULD NOT** | do this unless you have a stated reason not to |
| **MAY** | genuinely optional |
| *(unmarked prose)* | explanation. Never normative. |

Blocks are labelled `EXAMPLE`, `HISTORICAL NOTE` or `OPEN QUESTION` where they
are not specification. The three markers ⛔ ⭐ ⚠ mean, in order: a rule whose
violation is unrecoverable, the highest-value item on the page, and a trap that
works until it does not. [`docs/conventions.md`](docs/conventions.md) states
the rest, including why no number in this tree is unsourced.
