# architecture

⭐ **The technical reference.** Components, the data that flows between them,
the invariants each holds, and the limits that are not going to move.

⛔ **When any other document in this tree conflicts with this one, this one is
right and the other is the defect.** Fix it in the same change.

This document owns: the component model, the trust boundaries, the identity
model's shape, the end-to-end state machines, and the system-wide invariants.
It does not own field-level schemas, CLI syntax, or per-ecosystem build
advice; each of those has its own document and is linked from here.

---

## 1. The one-paragraph model

A **recipe** is inert TOML in git. A **builder** reads it, fetches a
commit-pinned source into a digest-pinned container, runs the recipe's script,
and verifies the bytes that come out. A **publisher** pushes those bytes to an
OCI registry as a content-addressed artefact, then attaches a signature, an
SBOM, a provenance statement and the build log as separate artefacts that name
it. An **index generator** produces a signed catalogue mapping names and
versions to digests. A **client** resolves a name against that catalogue,
downloads by digest, verifies the hash and the signature independently, and
installs into a per-version directory reached through a symlink.

Every arrow in that paragraph carries a digest.

---

## 2. Components

Each row names the component, what it is authoritative for, and the document
that specifies it in full. ⛔ No component reaches past its column.

| # | component | authoritative for | specified in |
| --- | --- | --- | --- |
| C1 | **recipe** | what a package is, declaratively | [`format/build-manifest.md`](format/build-manifest.md) |
| C2 | **validator** | whether a recipe is well formed, without executing it | [`testing.md`](testing.md) |
| C3 | **resolver** | which upstream version is current | [`ci/update-automation.md`](ci/update-automation.md) |
| C4 | **builder** | turning a recipe into bytes, reproducibly | [`build/build-system.md`](build/build-system.md) |
| C5 | **verifier** | whether produced bytes are fit to publish | [`build/build-system.md`](build/build-system.md) |
| C6 | **publisher** | putting artefacts and their evidence in a registry | [`registry/oci-ghcr.md`](registry/oci-ghcr.md) |
| C7 | **signer** | asserting that a digest was approved | [`security/signing-and-attestations.md`](security/signing-and-attestations.md) |
| C8 | **index generator** | the searchable catalogue | [`registry/index-and-search.md`](registry/index-and-search.md) |
| C9 | **client** | resolving, verifying and installing on a user's machine | [`client/client-behaviour.md`](client/client-behaviour.md) |
| C10 | **mirror agent** | replicating artefacts elsewhere, unchanged | [`registry/mirroring.md`](registry/mirroring.md) |

### 2.1 The split that defines the system

⭐ **C1 through C3 never execute recipe content. C4 does, and is the only one
that does.**

This is the whole design in one line, and it is what neither historical system
managed. Era 1 executed recipe shell during metadata generation, so merely
learning a package's version ran a maintainer's script. Era 3 removed
execution by removing building. Here, execution exists but is confined to one
component, one machine, and one lifecycle stage.

⛔ **A validator, resolver, index generator or client that executes anything
from a recipe is not conformant.** The acceptance test for this is in
[`testing.md`](testing.md) and it plants a recipe whose script would write a
file, then asserts the file does not exist.

---

## 3. Trust boundaries

Five boundaries. Crossing one requires the check named.

```
  ┌─ B1 ─────────────────────────────────────────────────────────┐
  │ untrusted: a contributor's pull request                      │
  │   -> crossing requires: human review of an inert diff        │
  ├─ B2 ─────────────────────────────────────────────────────────┤
  │ semi-trusted: upstream source at a pinned commit             │
  │   -> crossing requires: commit equality checked after fetch  │
  ├─ B3 ─────────────────────────────────────────────────────────┤
  │ isolated: the build container                                │
  │   -> crossing requires: output verification (C5)             │
  ├─ B4 ─────────────────────────────────────────────────────────┤
  │ published: the registry                                      │
  │   -> crossing requires: signature over the manifest digest   │
  ├─ B5 ─────────────────────────────────────────────────────────┤
  │ the user's machine                                           │
  │   -> crossing requires: hash AND signature, checked          │
  │      independently, before any byte is made executable       │
  └──────────────────────────────────────────────────────────────┘
```

⭐ **B5's two checks are independent on purpose.** A validly signed index
carrying a wrong hash still fails at install, because the hash is checked
against the bytes rather than against the index. Losing the signing key does
not by itself let an attacker substitute an artefact, and corrupting the
registry does not by itself let one either. Both are required together.

The full threat model, per attacker position, is
[`security/security-model.md`](security/security-model.md).

---

## 4. Identity

`architecture.md` owns the *shape*; the rules and grammars are in
[`format/package-identity.md`](format/package-identity.md).

A published artefact is identified by five coordinates:

```
  repository   family   name      version   revision   host
  ─────────────────────────────────────────────────────────────
  opk          ripgrep  ripgrep   14.1.1    1          x86_64-linux
```

| coordinate | meaning | mutable |
| --- | --- | --- |
| **repository** | which package set this came from, for example `opk` or a third party's | no |
| **family** | the directory grouping related recipes, usually equal to name | no |
| **name** | the package name a user types | no |
| **version** | upstream's version string, normalised | no |
| **revision** | our build counter for that version | no |
| **host** | `<arch>-<os>`, for example `x86_64-linux` | no |

The **package coordinate** is `repository/family/name`. The **release
coordinate** adds `version-revision-host`. Neither is an integrity claim; both
resolve to a digest, and the digest is.

⛔ **Two artefacts with the same release coordinate MUST have the same
digest.** Publishing different bytes under one coordinate is the failure the
whole index model rests on not happening; the publisher refuses it and
[`registry/oci-ghcr.md`](registry/oci-ghcr.md) says how.

---

## 5. Data flow

### 5.1 Publish

```
opk.toml ──C2──> valid?
              │ no  -> reject, report on the pull request, stop
              │ yes
              ▼
        ┌─────────────────────────┐
        │ C4 builder              │  container pinned by digest
        │  fetch source @commit   │  commit verified after fetch
        │  install pinned tools   │  each verified by sha256
        │  run [build.script]     │  SOURCE_DATE_EPOCH from commit
        │  collect [artifact] map │  LC_ALL=C TZ=UTC, fixed /build
        └───────────┬─────────────┘
                    │ bytes + build.log
                    ▼
        ┌─────────────────────────┐
        │ C5 verifier             │  arch matches the declared host
        │                         │  no PT_INTERP unless declared
        │                         │  runs under emulation if asked
        └───────────┬─────────────┘
             │ fail │ pass
             ▼      ▼
      publish   ┌─────────────────────────┐
      FAILURE   │ C6 publisher            │  normalised archive
      record    │  push package manifest  │  artifactType set
      (log      │  attach SBOM            │  referrers, or fallback tag
      only,     │  attach provenance      │
      no        │  attach build log       │
      payload)  │  C7 sign the digest     │
                └───────────┬─────────────┘
                            ▼
                     C8 index generator ──> signed index
```

⭐ **A failed build publishes its log and never its payload.** The failure
record carries a distinct `artifactType`, so no client can install it by
accident. Proven by `experiments/30-oci-pipeline.sh`, which builds a program
that cannot compile and asserts the resulting manifest has no payload layer.

### 5.2 Install

```
opk install NAME
   │
   ├─ 1. load index, verify its signature ──────── fail -> refuse, exit 11
   ├─ 2. resolve NAME + constraints -> release coordinate
   │       no candidate for this host -> exit 12 with the hosts that exist
   ├─ 3. look up the digest for that coordinate
   ├─ 4. fetch the manifest BY DIGEST ──────────── digest mismatch -> exit 13
   ├─ 5. fetch layers by digest, streaming-hash while writing
   ├─ 6. verify payload hash against the index ─── mismatch -> exit 13
   ├─ 7. discover referrers, fetch the signature
   ├─ 8. verify the signature over the MANIFEST digest under the
   │     active trust policy ───────────────────── fail -> exit 14
   ├─ 9. unpack into a staging directory on the same filesystem
   ├─ 10. verify every declared provides path exists
   ├─ 11. atomically rename staging into the version directory
   └─ 12. update the symlink farm, atomically
```

⛔ **No byte becomes executable before step 11.** Steps 1 to 10 write only
into a staging directory that is removed on any failure. There is no partial
install; the rename in step 11 either happens or does not.

⚠ **Step 8's failure mode is a policy decision, not a fixed behaviour.** Under
the default policy a missing or bad signature refuses the install. Under
`--trust-policy=hash-only` it warns and proceeds, which exists for air-gapped
mirrors that legitimately carry no signing key.
[`security/trust-and-verification.md`](security/trust-and-verification.md)
defines every policy and its exact behaviour.

---

## 6. State machines

### 6.1 A recipe, in the repository

```
  DRAFT ──open PR──> PROPOSED ──validate──> VALIDATED ──build──> BUILT
                         │ fail                  │ fail            │
                         └──> REJECTED <─────────┘                 │ merge
                                                                   ▼
   RETIRED <──takedown── PUBLISHED <──index── INDEXED <────────────┘
      │                     │
      │                     └──rebuild fails to reproduce──> SUSPECT
      └──> tombstone kept; the coordinate is never reused
```

| state | means | who moves it |
| --- | --- | --- |
| `PROPOSED` | a pull request exists | contributor |
| `VALIDATED` | parses, schema-valid, all pins present | CI |
| `BUILT` | produced a verified artefact on every declared host | CI |
| `PUBLISHED` | in the registry, signed | CI on merge |
| `INDEXED` | resolvable by a client | index generator |
| `SUSPECT` | a scheduled rebuild did not reproduce | reproducibility job |
| `RETIRED` | withdrawn; see [`ops/operations.md`](ops/operations.md) | maintainer |

⛔ **A retired coordinate is never reused.** Reuse would let a name a user has
pinned resolve to different software.

⚠ **`SUSPECT` does not unpublish.** A package that stops reproducing is
flagged loudly and left installable, because the alternative is that a
transient CI difference removes working software from users. What `SUSPECT`
does change is that it blocks the next promotion and raises an alert;
[`build/reproducibility.md`](build/reproducibility.md) has the handling.

### 6.2 An installed package, on a client

```
  ABSENT ──install──> STAGED ──rename──> INSTALLED ──link──> ACTIVE
              │ any failure                                     │
              └──> ABSENT (staging removed)                     │
                                                                │
   ACTIVE ──upgrade──> (new version ACTIVE, old INSTALLED)      │
   ACTIVE ──rollback──> (previous ACTIVE, current INSTALLED)  ──┘
   INSTALLED ──gc──> ABSENT
```

⭐ **Rollback is a symlink change, not a download**, as long as the previous
version is still `INSTALLED`. That is the reason old versions are kept until
garbage collection rather than removed on upgrade, and the retention default
is in [`client/delta-and-gc.md`](client/delta-and-gc.md).

---

## 7. System-wide invariants

⛔ These hold everywhere. Each names the component that enforces it and the
test that proves it.

| # | invariant | enforced by | tested by |
| --- | --- | --- | --- |
| I1 | Reading, validating, resolving or indexing a recipe executes nothing from it | C2, C3, C8 | `testing.md` §inert |
| I2 | Every build input is pinned by digest or cryptographic hash | C2 rejects otherwise | `testing.md` §pins |
| I3 | A published artefact is addressable by digest, and the client uses that address | C6, C9 | `experiments/30-oci-pipeline.sh` |
| I4 | The payload hash recorded in metadata equals the hash of the payload shipped | C5, C6 | `experiments/30-oci-pipeline.sh` |
| I5 | A signature covers a manifest digest, never a tag | C7 | `experiments/30-oci-pipeline.sh` |
| I6 | Hash verification and signature verification are independent | C9 | `testing.md` §trust |
| I7 | A failed build publishes no payload | C5, C6 | `experiments/30-oci-pipeline.sh` |
| I8 | An artefact declaring a host runs on that host's architecture with no PT_INTERP, unless the recipe declares dynamic linkage with a reason | C5 | `experiments/20-static-matrix.sh` |
| I9 | Nothing is executable on the client until the atomic rename succeeds | C9 | `testing.md` §atomic |
| I10 | A release coordinate maps to exactly one digest, forever | C6 | `testing.md` §immutable |
| I11 | Build logs are published for successes and failures alike | C6 | `experiments/30-oci-pipeline.sh` |
| I12 | Secrets never reach a published log | C4, C6 | `security/secrets.md` |

⚠ **I8 has a deliberate exception and it is declared, not implicit.** Some
software genuinely cannot be statically linked, for example anything that must
`dlopen` a host GPU driver. Such a package sets `portable = false` with a
`portable-reason`, and the client warns at install.
[`build/static-linking.md`](build/static-linking.md) has the criteria.

---

## 8. What lives where

⭐ **The question this table answers is the one that gets decided wrongly
most often**: given a piece of information, which layer stores it.

| information | lives in | why not elsewhere |
| --- | --- | --- |
| package name, version, host | manifest **annotations** | a client filtering a listing must not have to download layers |
| `artifactType` | the **manifest** | it is how a client tells a package from a signature before fetching |
| the binary | a **layer** | it is the payload |
| licence text, icons | **layers** | they ship with the package and are small |
| full metadata JSON | a **layer** | too large for annotations, needed at install |
| checksums of each shipped file | a **layer** | verified after unpacking |
| signature | a **referrer** | it is created after the manifest exists, and adding it must not change the manifest's digest |
| SBOM | a **referrer** | same, and it is optional to fetch |
| provenance | a **referrer** | same |
| build log | a **referrer** | often larger than the payload, and almost never fetched |
| name to digest mapping for search | the **external index** | walking a registry to find a package is not a supported operation |
| download counts, popularity | the **external index** | not integrity-relevant, and mutable |

⛔ **Annotations are limited and must not be used as a database.** GHCR
enforces a manifest size ceiling; the measured value and the annotation budget
derived from it are in [`registry/oci-ghcr.md`](registry/oci-ghcr.md).

---

## 9. The registry layout, in one block

Full specification, including the GHCR constraints that shaped it, is
[`registry/oci-ghcr.md`](registry/oci-ghcr.md). The shape:

```
ghcr.io/<org>/opk/<family>/<name>
  :<version>-<revision>-<host>       one platform, the common case
  :<version>-<revision>              an index over the per-host manifests
  :stable                            channel pointer, mutable
  :sha256-<hex>                      referrers fallback index for that digest

ghcr.io/<org>/opk-index
  :v1                                the signed catalogue
  :v1-<YYYYMMDDTHHMMSSZ>             an immutable snapshot of it
```

⚠ **`ghcr.io/<org>/opk/...` deliberately nests below a fixed `opk` segment.**
GHCR maps a repository to a GitHub Packages entry per top-level path, and
without the segment a package named `index` would collide with the index
repository. The reasoning and the alternatives are in
[`decisions/0004-registry-namespace.md`](decisions/0004-registry-namespace.md).

---

## 10. Limits

⛔ Properties of the substrate, not of this design. Nothing here is fixable by
implementing better; each is a constraint the design routes around.

| # | limit | consequence | evidence |
| --- | --- | --- | --- |
| L1 | GHCR does not implement the referrers API | referrers are published as a fallback-tag index, and the client tries both | `experiments/40-registry-conformance.sh`, controls held |
| L2 | A registry tag is mutable | a tag is never an integrity claim; signatures cover digests | OCI distribution-spec |
| L3 | GitHub Actions offers Linux runners for x86-64 and aarch64 only | every other architecture is cross-compiled and verified under emulation | [`build/cross-compilation.md`](build/cross-compilation.md) |
| L4 | Distribution packages installed during a build are not version-pinned by most package managers | reproducibility holds within a window unless the base image carries the dependencies | [`build/reproducibility.md`](build/reproducibility.md) |
| L5 | A static binary cannot use glibc's NSS or `dlopen` plugins | some software cannot be statically linked and must declare it | [`build/static-linking.md`](build/static-linking.md) |
| L6 | A static binary carries no shared-library security updates | a vulnerable dependency requires a rebuild of every package containing it | [`security/supply-chain.md`](security/supply-chain.md) |
| L7 | A registry has no server-side search | discovery requires an external index | [`registry/index-and-search.md`](registry/index-and-search.md) |

⭐ **L6 is the most consequential and the least visible.** Dynamic linking
gives a distribution one place to patch a library for every program. Static
linking trades that for portability, and the price is a rebuild fan-out that
must be automated or it will not happen.
[`security/supply-chain.md`](security/supply-chain.md) specifies the mechanism
that pays it.

---

## 11. Where the design came from

Each choice below is stated in full, with alternatives and cost, in its own
decision record. This table is the index, not the argument.

| decision | record |
| --- | --- |
| inert recipes with one contained escape hatch | [`decisions/0001-inert-recipes.md`](decisions/0001-inert-recipes.md) |
| OCI registries as the substrate, GHCR as reference | [`decisions/0002-oci-substrate.md`](decisions/0002-oci-substrate.md) |
| static linking by default, musl as the default libc | [`decisions/0003-static-musl-default.md`](decisions/0003-static-musl-default.md) |
| the registry namespace shape | [`decisions/0004-registry-namespace.md`](decisions/0004-registry-namespace.md) |
| evidence as referrers, with the fallback tag | [`decisions/0005-referrers-fallback.md`](decisions/0005-referrers-fallback.md) |
| two hashes, BLAKE3 and SHA-256, with distinct jobs | [`decisions/0006-two-hashes.md`](decisions/0006-two-hashes.md) |
| reproducibility checked off the publish path | [`decisions/0007-reproducibility-off-path.md`](decisions/0007-reproducibility-off-path.md) |
| TOML for recipes | [`decisions/0008-toml.md`](decisions/0008-toml.md) |
| the implementation order | [`decisions/0009-implementation-order.md`](decisions/0009-implementation-order.md) |
| signing scheme, and why not only Sigstore | [`decisions/0010-signing-scheme.md`](decisions/0010-signing-scheme.md) |
| the index as a signed artefact rather than a service | [`decisions/0011-index-as-artifact.md`](decisions/0011-index-as-artifact.md) |
| no lifecycle hooks by default | [`decisions/0012-no-hooks.md`](decisions/0012-no-hooks.md) |
