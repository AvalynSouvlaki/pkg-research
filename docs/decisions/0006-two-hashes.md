# 0006: two hashes, BLAKE3 and SHA-256, with distinct jobs

## Decision

⭐ **BLAKE3 is what the client verifies. SHA-256 is what a registry or forge
independently reports, so the two can be cross-checked.**

## Problem

One hash is enough for integrity. What one hash cannot do is let you compare
your value against a third party's when that third party only publishes a
different algorithm.

## Alternatives

| alternative | why rejected |
| --- | --- |
| SHA-256 only | ⭐ simplest; ⚠ slower on large artefacts, no parallel verification |
| ⚠ BLAKE3 only | ⭐ fastest; ⛔ nothing to cross-check against, since registries and forges report SHA-256 |
| SHA-512 | ⚠ no advantage here |
| ⭐ **both, with different jobs** | ⭐ chosen |

## Evidence

⭐ **Measured** in `experiments/30-oci-pipeline.sh`: the payload's BLAKE3 is
computed at publish, written to `metadata.json` as `b3:<hex>`, and checked
against the artefact **pulled back out of the registry**. A byte appended to
the payload changes the value, which is asserted rather than assumed.

⚠ **This proof did not exist until review pass 5.** Every experiment checked
SHA-256 only, so the hash this decision calls load-bearing was never once
exercised. ⛔ A decision with no proof behind it reads exactly like one with
a proof behind it, which is why the gap survived four passes.

## Tradeoff

⭐ **Gained**: fast verification, and an independent value to compare against
what the registry or forge says. ⭐ A disagreement between the two is a finding
that neither alone can produce.

⚠ **Cost**: two values per file in the metadata, and two hashes computed at
publish. ⚠ Both are cheap relative to the download.

## Evidence

⭐ **Observed**, era 3's own format document: `[blake3]` is annotated "what soar
verifies against" and `[sha256]` "what a forge API reports, so it can be
cross-checked". ⭐ The distinction is theirs and it is correct.

⭐ **Observed**, era 1: `bsum` (BLAKE3) and `shasum` (SHA-256) both appear in
the published metadata, with the SHA-256 equal to the OCI layer digest.

⚠ **Not measured here**: no hashing benchmark was run in this repository, so
the speed claim is documented rather than measured.

## Consequences

- Both hashes appear per file in
  [`../format/metadata-schema.md`](../format/metadata-schema.md).
- ⭐ The publisher compares its SHA-256 against a forge-reported digest where
  one exists and fails on a mismatch.
- ⛔ `CHECKSUMS` inside an artefact uses BLAKE3; OCI layer digests are SHA-256
  because the spec requires it.

## Reversal

⭐ **Cheap.** Dropping one is a schema change with a version bump. ⚠ Adding a
third later is also cheap; the metadata is a map keyed by algorithm.
