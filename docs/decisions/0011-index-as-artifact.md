# 0011: the index as a signed artefact, not a service

## Decision

⭐ **The searchable catalogue is a signed artefact in the registry. There is no
search service.**

## Problem

A registry has no search. A client resolving `opk install ripgrep` needs a
mapping from a name to a digest, and that mapping has to come from somewhere.

## Alternatives

| alternative | why rejected |
| --- | --- |
| ⚠ **a search service** | ⭐ real-time, server-side ranking; ⛔ something to run, something to be down, and another party to trust |
| ⛔ **walk the registry** | ⛔ the catalogue endpoint is optional, commonly disabled, and returns names with no metadata |
| ⚠ **an index in git** | ⭐ works; ⚠ a large index in git is what made `pkgforge/metadata` hard-reset its history every 5000 commits |
| ⭐ **a signed artefact in the registry** | ⭐ chosen |

## Tradeoff

⭐ **Gained**: nothing to operate. The index is content-addressed, signed, and
cached by digest like everything else. ⭐ Anyone can regenerate it and compare,
which is a cheap and effective audit.

⚠ **Cost**: no real-time updates; the index is as fresh as its last generation.
No server-side ranking. ⛔ A replay window, bounded by freshness rules but not
eliminated. Clients download a whole catalogue rather than querying.

## Evidence

⚠ **Recommended**, with observed support.

⭐ **Observed**: `pkgforge/metadata`'s `GHCR_PKGS.json` is 62,755,217 bytes and
its zstd form is 317,606, a ratio near 200 to 1, observed 2026-09-02. ⭐ That is
one data point about *their* schema and it establishes the order of magnitude:
a whole-catalogue download is a few hundred kilobytes, not a few hundred
megabytes.

⚠ **Observed**: the same repository's README states it hard-resets its history
every 5000 commits, which is the git-as-index approach reaching its limit.

## Consequences

- ⛔ Freshness rules and rollback protection are required, because a signed
  index is still a replayable index.
  [`../registry/index-and-search.md`](../registry/index-and-search.md) §4.
- Search is local and its ranking is deterministic.
- ⭐ A `catalog-lite` layer exists for clients that never search.
- ⚠ Generation must be incremental, or it becomes the largest rate-limit
  consumer. [`../ops/rate-limits.md`](../ops/rate-limits.md) §4.

## Reversal

⭐ **Cheap to add a service later** as an optional accelerator, with the signed
artefact remaining authoritative. ⛔ Making a service authoritative is the
expensive direction, because it puts a party back in the trust path that this
decision removed.
