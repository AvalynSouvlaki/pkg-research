# proofs of concept

⭐ **Which experiment demonstrates which part of the specification**, and what
each proof does not cover.

The scripts and how to run them are
[`../../experiments/README.md`](../../experiments/README.md). This page is the
**mapping**.

---

## 1. The required demonstrations

⭐ **Every one of these runs on an ordinary Linux machine with no root, no
registry account and no credentials.**

| # | demonstration | where | status |
| --- | --- | --- | --- |
| 1 | ⭐ building a static binary | `20-static-matrix.sh`, `30-oci-pipeline.sh` | ⭐ **measured**, 15 toolchain rows |
| 2 | cross-compiling a static binary | `20-static-matrix.sh` via `zig cc` | ⭐ measured for one target |
| 3 | ⭐ producing an OCI artefact | `30-oci-pipeline.sh` | ⭐ measured |
| 4 | ⭐ publishing to a registry, locally | `30-oci-pipeline.sh` against zot | ⭐ measured |
| 5 | generating metadata | `30-oci-pipeline.sh` | ⭐ measured |
| 6 | generating checksums | `30-oci-pipeline.sh` | ⭐ measured |
| 7 | ⭐ generating signatures and attestations | `30-oci-pipeline.sh` | ⭐ measured: minisign plus in-toto |
| 8 | ⭐ verifying artefacts | `30-oci-pipeline.sh` | ⭐ measured, with a tamper check |
| 9 | installing an artefact | `30-oci-pipeline.sh` | ⭐ measured |
| 10 | ⭐ reproducing a build | `30-oci-pipeline.sh` | ⚠ **same host only**; §3 |
| 11 | inspecting build provenance | `30-oci-pipeline.sh` | ⭐ measured |
| 12 | ⭐ retrieving build logs | `30-oci-pipeline.sh` | ⭐ measured |
| 13 | ⭐ handling a failed build | `30-oci-pipeline.sh` | ⭐ measured: a real compile failure |
| 14 | updating a package declaration | ⚠ specified only | ⛔ **§4** |
| 15 | running the workflow in CI | ⚠ specified only | ⛔ **§4** |
| 16 | ⭐ mirroring, and catching a mirror that alters something | `50-mirror.sh` | ⭐ measured, 15 assertions |

---

## 2. `30-oci-pipeline.sh`, step by step

⭐ **The whole lifecycle in one script. 33 assertions, all passing on the probe
host.**

| step | asserts | specification |
| --- | --- | --- |
| start a registry | it answers `/v2/` with 200 | [`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) |
| build | ⭐ the binary has no `PT_INTERP` | [`../build/static-linking.md`](../build/static-linking.md) §1 |
| metadata | it is valid JSON and agrees with the payload | [`../format/metadata-schema.md`](../format/metadata-schema.md) |
| SBOM | ⭐ recognisable SPDX-2.3 | [`../security/sbom-and-provenance.md`](../security/sbom-and-provenance.md) §1 |
| push | ⭐ `artifactType` survives the round trip | [`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) §3.1 |
| attach | ⭐ three referrers, each discoverable by `artifactType` | same §5 |
| sign | ⭐ the signature covers the **manifest digest** | [`../security/signing-and-attestations.md`](../security/signing-and-attestations.md) §1 |
| pull | ⭐ by digest; the payload hash matches the metadata | [`../security/trust-and-verification.md`](../security/trust-and-verification.md) §2 |
| ⭐ BLAKE3 | ⭐ the hash the **client** verifies, and it changes on a modified byte | [`../decisions/0006-two-hashes.md`](../decisions/0006-two-hashes.md) |
| verify | ⭐ the signature verifies, ⛔ **and a tampered digest is refused** | same |
| install | it runs from the symlink farm | [`../client/installation-layout.md`](../client/installation-layout.md) |
| reproduce | ⭐ byte-identical rebuild | [`../build/reproducibility.md`](../build/reproducibility.md) |
| provenance | ⭐ the subject digest matches the artefact | [`../security/sbom-and-provenance.md`](../security/sbom-and-provenance.md) §2 |
| build log | retrieved from the registry by referrer | [`../ci/build-logs.md`](../ci/build-logs.md) |
| a failed build | ⭐ publishes a log, ⛔ **and no payload layer** | [`../architecture.md`](../architecture.md) I7 |

⭐ **The tamper check is the one worth reading the code for.** It passed
vacuously on its first run, and the fix is described in
[`../history/README.md`](../history/README.md) §4.

---

## 3. ⛔ What the proofs do not cover

| gap | why | closed by |
| --- | --- | --- |
| ⛔ **cross-host reproducibility** | ⭐ one machine, one day | [`../open-questions.md`](../open-questions.md) Q5 |
| ⛔ anything writing to real GHCR | no namespace or credentials | Q1 to Q4 |
| ⛔ the client | ⚠ not implemented | the implementation |
| ⛔ the update bot | ⚠ not implemented | §4 |
| ⛔ the index generator | ⚠ not implemented | the implementation |
| ⚠ ten of seventeen ecosystems | absent toolchains | ⭐ marked in each file |
| ⛔ non-Linux | Linux host | [`../compatibility.md`](../compatibility.md) |

---

## 4. ⛔ The two demonstrations that are specified and not built

⭐ **Named here rather than left as a silent absence.**

### 4.1 Updating a package declaration

⛔ **Not implemented**, because it requires the update bot, which requires the
recipe parser, which is step 1 of the implementation path.

⭐ **What it would look like**, fully specified in
[`../ci/update-automation.md`](../ci/update-automation.md):

```sh
opk resolve packages/ripgrep     # query the strategy, validate the version
opk pin packages/ripgrep         # fetch, hash, write the release file
opk validate                     # ⛔ refuses a pinned URL with no hash
git diff                         # ⭐ a version line and some hash lines
```

⭐ **The seven version checks in §4 of that document are the substance**, and
they are testable without the bot: they are a pure function from a discovered
string and a current version to accept or reject. ⭐ That is the first unit test
an implementer should write.

### 4.2 Running the workflow in CI

⛔ **Not run**, because this repository has no CI and no namespace to publish
to.

⭐ **The workflows are specified completely** in
[`../ci/ci-system.md`](../ci/ci-system.md), including permissions, concurrency
groups and the fork boundary. ⭐ `30-oci-pipeline.sh` performs the same sequence
locally, so what is untested is the GitHub Actions wiring rather than the
logic.

⚠ **The wiring is where the historical system's defects were**, not the logic:
`continue-on-error` on an attestation, a comment body interpolated into a
shell, signing that fails open. ⛔ Those are exactly what a local script cannot
catch, and it is honest to say the untested part is the risky part.

---

## 5. Reproducing the proofs

```sh
git clone <this repository> && cd pkg-research
bash experiments/00-fetch-tools.sh
bash experiments/10-probe-host.sh        # ⭐ compare against out/10-probe-host.txt
bash experiments/30-oci-pipeline.sh      # ⭐ expect: 33 passed, 0 failed
```

⚠ **Your numbers will differ from ours** wherever a toolchain version differs,
and that is the point of printing the conditions. ⛔ What must not differ is the
pass or fail column.

⭐ **If an assertion fails on your machine, that is a finding**, and the
experiment's output names which one.
