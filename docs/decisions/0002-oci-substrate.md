# 0002: OCI registries as the substrate, GHCR as reference

## Decision

⭐ **Artefacts are stored as OCI artefacts in an OCI distribution-spec
registry.** GHCR is the reference host; no GHCR-specific feature is used.

## Problem

The system needs content-addressed storage with authentication, resumable
downloads, CDN delivery and a client on every platform, without operating any
of it.

## Alternatives

| alternative | why rejected |
| --- | --- |
| ⭐ **forge releases**, era 3's choice | ⚠ works; ⛔ no content addressing, no referrers, per-repository asset limits, and no way to attach evidence to a specific artefact |
| ⛔ **object storage** | ⭐ cheapest, and it is storage only: no auth model, no manifest concept, and everything else must be built |
| ⛔ **a git repository as a blob store**, as `pkgforge/metadata` does | ⚠ it works and it does not scale: that repository hard-resets its history every 5000 commits |
| ⚠ a purpose-built server | ⛔ something to run, secure and keep up |
| ⭐ **an OCI registry** | ⭐ chosen |

## Tradeoff

⭐ **Gained**: content addressing, deduplication, referrers, free public
hosting, and off-the-shelf tooling (`oras`, `skopeo`, `crane`).

⚠ **Cost**: ⛔ no search of any kind, so an external index is required. ⛔ GHCR
does not implement the referrers API, so the fallback tag is mandatory. Rate
limits that are not clearly documented.

## Evidence

⭐ **Observed**: `ghcr.io/pkgforge/bincache` stores per-package artefacts with
fifteen titled layers each, so the approach is proven at scale by a real
system.

⭐ **Measured**, `experiments/40-registry-conformance.sh`, 2026-09-02: GHCR
answers the token flow anonymously and serves manifests by digest, and its
referrers endpoint returns 404 with both controls held.

⚠ **Observed**: `pkgforge/metadata` README states it hard-resets its history
every 5000 commits, which is the git-as-blob-store approach reaching its limit.

## Consequences

- An external signed index is required.
  [`../registry/index-and-search.md`](../registry/index-and-search.md).
- ⛔ The fallback tag scheme is mandatory, not optional.
  [`0005-referrers-fallback.md`](0005-referrers-fallback.md).
- Migration to another registry is a copy that preserves digests.
  [`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) §8.

## Reversal

⭐ **Cheap.** The layout uses no GHCR-specific feature, so moving is `oras cp`
plus re-signing the index. ⭐ Package signatures survive because they cover
digests.
