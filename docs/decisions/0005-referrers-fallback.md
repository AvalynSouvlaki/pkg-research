# 0005: evidence as referrers, with the fallback tag mandatory

## Decision

⭐ **Signature, SBOM, provenance and build log are separate manifests naming the
package as their `subject`.** ⛔ **A publisher always writes the fallback tag,
and a client always tries the API first and the tag second.**

## Problem

A signature signs a manifest digest, so it cannot be inside that manifest. The
evidence must attach after publication without changing what it describes.

## Alternatives

| alternative | why rejected |
| --- | --- |
| ⛔ **evidence as layers of the package**, era 1's model | ⭐ circular for a signature: adding it changes the digest it signs. Also forces a pull of the log to get the metadata. |
| a parallel repository, `<name>-sig` | ⚠ works; ⛔ doubles the repository count and loses the subject relationship |
| ⛔ **referrers API only** | ⛔ **GHCR does not implement it**; measured |
| ⛔ fallback tag only | ⚠ works everywhere; ⭐ gives up the API on registries that do implement it |
| ⭐ **both, always** | ⭐ chosen |

## Tradeoff

⭐ **Gained**: evidence attaches without changing the package digest. It works
on GHCR today and gets the API's benefits on registries that have it.

⚠ **Cost**: ⛔ the fallback tag is read-modify-write and therefore racy, so
writes must be serialised per subject and reconciled. Two code paths in the
client.

## Evidence

⭐ **Measured**, `experiments/40-registry-conformance.sh`, 2026-09-02, with two
controls holding in the same run:

| step | result |
| --- | --- |
| control A: our digest equals the registry's `Docker-Content-Digest` | ✅ held |
| control B: that digest resolves as a manifest | ✅ HTTP 200 |
| the referrers endpoint on that digest | ❌ **HTTP 404 `MANIFEST_UNKNOWN`** |

⭐ **Measured**, `experiments/41-referrers-fallback.sh`: a client with the API
path disabled finds the same referrers by `artifactType` through the fallback
tag, and returns cleanly for a subject with none. 10 checks, all passing.

## Consequences

- ⛔ Publishers write both routes.
  [`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) §5.2.
- ⛔ Fallback-tag writes are serialised per subject, with reconciliation.
  [`../ci/ci-system.md`](../ci/ci-system.md) §3.1.
- ⛔ A mirror must copy the `sha256-*` tags, which a tag-based copy does not
  see. [`../registry/mirroring.md`](../registry/mirroring.md) §3.
- ⚠ A lost fallback entry presents as an unsigned package, which is a refused
  install. [`../ops/failure-modes.md`](../ops/failure-modes.md) F9.

## Reversal

⭐ **Cheap to drop the fallback** if GHCR implements the API, and ⚠ the
fallback tags should stay written anyway, because artefacts published before
the change would otherwise become undiscoverable through the API.
