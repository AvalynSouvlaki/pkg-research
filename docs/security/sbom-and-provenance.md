# SBOM and provenance

Two different documents answering two different questions, both attached as
referrers, both routinely over-read.

| document | answers |
| --- | --- |
| **SBOM** | ⭐ what is inside this artefact |
| **provenance** | ⭐ how this artefact came to exist |

---

## 1. SBOM

### 1.1 Generation

```sh
syft scan file:stage/rg -o spdx-json > sbom.spdx.json
syft scan dir:stage     -o cyclonedx-json > sbom.cdx.json
```

⭐ **Generate from the source tree, not only from the binary.** A stripped
static binary tells a scanner very little; the dependency lockfile tells it
everything.

```sh
syft scan dir:/build -o spdx-json > sbom.spdx.json     # reads Cargo.lock, go.sum, ...
```

⛔ **Both are worth producing and they are not equivalent**: the source-tree
SBOM lists what was intended; the binary SBOM lists what a scanner can find in
what shipped. Where they disagree, that is a finding.

### 1.2 ⚠ What an SBOM of a static binary is worth

⛔ **Less than people assume, and saying so is part of using it honestly.**

| property | reality |
| --- | --- |
| a stripped static binary | ⚠ a scanner finds almost nothing: no `DT_NEEDED`, no package database, no version strings unless they happen to be in `.rodata` |
| a Go binary | ⭐ the exception: build info is embedded and `syft` reads the module list |
| a Rust binary | ⚠ nothing embedded by default; the SBOM must come from `Cargo.lock` |
| a C binary with a vendored library | ⛔ the vendored code is indistinguishable from the project's own |

⭐ **This is why the source-tree SBOM is the primary one.** The binary SBOM is a
cross-check, and an SBOM claiming completeness for a stripped C binary is
asserting something it cannot know.

⚠ **Measured here**: `experiments/30-oci-pipeline.sh` runs `syft` against a
stripped static musl C binary and gets a valid SPDX-2.3 document. It is 739
bytes as published and it names essentially nothing, which is the honest
result for that input.

### 1.3 Format

| | |
| --- | --- |
| ⭐ primary | SPDX 2.3 JSON, `application/spdx+json` |
| also | CycloneDX 1.5 JSON, `application/vnd.cyclonedx+json` |
| ⛔ deterministic | ⚠ see below |

⛔ **An SBOM must be deterministic or it breaks reproducibility.** Scanners
emit a generation timestamp and a random document namespace by default, so two
identical builds produce different SBOMs and therefore different digests.

```sh
SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
SYFT_SOURCE_NAME="$OPK_NAME" \
syft scan dir:/build -o spdx-json \
  | jq -S 'del(.creationInfo.created) | .documentNamespace = "urn:opk:'"$OPK_NAME"':'"$OPK_VERSION"'"' \
  > sbom.spdx.json
```

⚠ **Deleting the timestamp makes the document non-conformant to SPDX's
requirement that `created` be present.** The alternative, setting it to
`SOURCE_DATE_EPOCH`, keeps conformance and determinism together, and is what a
production implementation should do. The `del` above is shown because it is what
people reach for first and it has that cost.

---

## 2. Provenance

An in-toto statement with a SLSA provenance predicate, attached as a referrer.

```json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [
    { "name": "ripgrep",
      "digest": { "sha256": "afb42bf28b19048dac5b970cb2474ead0f7ea02d1307a86104d18644f13a824f" } }
  ],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://opk.dev/buildtypes/container/v1",
      "externalParameters": {
        "recipe": "https://github.com/example/opk-packages/blob/4d5e6f/packages/ripgrep/opk.toml",
        "recipeDigest": "sha256:7c8d9e...",
        "package": "ripgrep", "version": "14.1.1", "revision": 1,
        "host": "x86_64-linux"
      },
      "internalParameters": {
        "SOURCE_DATE_EPOCH": "1714435200",
        "LC_ALL": "C", "TZ": "UTC", "PREFIX": "/opk",
        "network": "restricted"
      },
      "resolvedDependencies": [
        { "uri": "git+https://github.com/BurntSushi/ripgrep",
          "digest": { "gitCommit": "4649aa9700d4dbaad0c85b0ac8b2c66e2b649b6c" } },
        { "uri": "pkg:oci/rust",
          "digest": { "sha256": "b4b54b176a74db7e5c68fdfe6029be39a02ccbcfe72b6e5a3e18e2c61b57ae26" } }
      ]
    },
    "runDetails": {
      "builder": {
        "id": "https://github.com/example/opk-packages/.github/workflows/build.yaml@refs/heads/main"
      },
      "metadata": {
        "invocationId": "https://github.com/example/opk-packages/actions/runs/1234567890",
        "startedOn": "2026-09-01T10:00:00Z",
        "finishedOn": "2026-09-01T10:04:11Z"
      }
    }
  }
}
```

### 2.1 ⛔ Fields that must be present

| field | why |
| --- | --- |
| `subject[].digest` | ⛔ ties the statement to specific bytes. Without it the statement describes nothing. |
| `externalParameters.recipe` + `recipeDigest` | ⭐ the exact recipe, pinned, so it cannot drift |
| `internalParameters.SOURCE_DATE_EPOCH` | ⭐ a rebuild needs it |
| `resolvedDependencies` | the source commit and the image digest: everything needed to rebuild |
| `builder.id` | who to trust, checked under `strict` |
| `metadata.invocationId` | ⭐ the CI run, so a human reaches the log the ordinary way |

⭐ **`recipe` plus `recipeDigest` is the linkage the historical system almost
had.** Era 1 published a `build_script` URL pointing at `refs/heads/main`, so
following it later showed the *current* recipe rather than the one that built
the artefact. Pinning the commit and recording the hash prevents the drift and
makes it detectable.

⚠ **`startedOn` and `finishedOn` are wall-clock and therefore vary between
runs.** They do not break the artefact's reproducibility because provenance is
a *referrer*, not a layer of the package, so it does not enter the manifest
digest. ⛔ Anything that must be reproducible does not go in the provenance.

### 2.2 SLSA level

⭐ **This design targets SLSA Build Level 3**, and states what is and is not
met.

| requirement | met |
| --- | --- |
| provenance exists | ⭐ yes |
| provenance is authentic, signed | ⭐ yes, through Sigstore or minisign |
| the build runs on a hosted, isolated platform | ⭐ yes |
| the build service generates the provenance | ⭐ yes, not the build script |
| ⛔ the build is isolated from other builds | ⭐ yes, a fresh container per build |
| secrets are unavailable to the build | ⭐ yes, [`../build/build-system.md`](../build/build-system.md) §3.1 |
| ⚠ dependencies are complete | ⛔ **not fully**: `[build].deps` are unpinned, per [`../build/reproducibility.md`](../build/reproducibility.md) §4.1 |

⛔ **That last row is why the claim is "targets" rather than "meets".** A
package built with `deps = []` and `network = "none"` meets it; one using `apk
add` does not, and the metadata's `hermetic` field records which.

⚠ **Do not publish a SLSA level as a badge.** It is a property of each build,
not of the project, and a badge averages over builds that differ.

---

## 3. Vulnerability scanning

```sh
grype sbom:sbom.spdx.json --fail-on high
```

⛔ **Scanning runs on a schedule against published SBOMs, not on the publish
path.** A build blocked by a scanner is a build blocked by a third party's
database, which changes without notice and has false positives.

| when | what |
| --- | --- |
| at build | ⚠ record findings in the log; do not fail |
| ⭐ daily, over the whole index | produce advisories |
| ⭐ on a new advisory | mark affected releases, per [`../registry/retention.md`](../registry/retention.md) §4 |
| ⛔ never | delete an affected artefact |

⚠ **The known-unknown**: an SBOM that cannot see a vendored C library means the
scanner cannot see its vulnerability either. §1.2. This is the strongest
argument for generating the SBOM from the source tree, where the vendored
directory is visible.

---

## 4. What each document is not evidence of

⛔ The single most useful table in this file.

| document | is evidence of | ⛔ is NOT evidence of |
| --- | --- | --- |
| signature | ⭐ a key holder approved these bytes | that the software is safe |
| provenance | ⭐ what the builder says it did | that the builder was honest, without reproducibility |
| SBOM | ⭐ what a scanner found | ⛔ that nothing else is in there |
| reproducibility | ⭐ two builders agree | that either was correct |
| a clean vulnerability scan | ⭐ no known match in one database | ⛔ that there is no vulnerability |

⭐ **Together they are much stronger than individually**, and the design
attaches all of them for that reason. Each alone is routinely over-read, and a
system that publishes one and implies the others is worse than one that
publishes none.
