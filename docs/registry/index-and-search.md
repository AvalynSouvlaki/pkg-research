# index and search

How a client finds a package without walking the registry.

---

## 1. Why an index exists at all

⛔ **A registry has no search, and it has no reliable listing.** The
distribution spec's catalogue endpoint is optional, is commonly disabled, and
returns repository names with no metadata. Resolving `opk install ripgrep`
against the registry alone would mean guessing repository paths.

So the catalogue is a separate, generated, signed artefact.

⚠ **The alternative is a search service, and it was rejected.** A service is
another thing to run, another thing to be down, and another party to trust.
[`../decisions/0011-index-as-artifact.md`](../decisions/0011-index-as-artifact.md)
has the comparison, including what is given up: real-time updates and
server-side ranking.

---

## 2. What the index is

An artefact in its own repository:

```
ghcr.io/<org>/opk-index
  :v1                              the current catalogue, moves
  :v1-20260901T100411Z             an immutable snapshot, never moves
```

⛔ **`:v1` is mutable and it is the only mutable thing a client depends on.**
That is not a contradiction of "tags are never integrity claims": the index is
signed, and the client verifies the signature before reading a byte of it. The
tag says *which* index; the signature says whether to believe it.

| layer | media type | contents |
| --- | --- | --- |
| `catalog.json.zst` | `application/vnd.opk.catalog.v1+json` compressed | the full catalogue |
| `catalog.sqlite.zst` | `application/vnd.opk.catalog-db.v1` | ⭐ the same data as SQLite, for clients that prefer a query engine |
| `catalog.minisig` | `application/vnd.opk.signature.minisign.v1` | the signature over `catalog.json.zst`'s digest |

⭐ **Two encodings of one dataset, generated together from one source.** The
JSON is the normative form and the SQLite is derived; a check asserts row
counts and a sample of digests agree. Shipping only JSON makes a large
catalogue slow to query; shipping only SQLite makes it opaque to anything
without SQLite.

⚠ **The SQLite file is a build output and must be reproducible.** SQLite writes
a change counter and can leave free pages in a non-deterministic layout;
generation runs `VACUUM` and zeroes the header's change counter, or two
identical catalogues produce different bytes.

---

## 3. The catalogue

```json
{
  "schemaVersion": 1,
  "repository": "opk",
  "generated": "2026-09-01T10:04:11Z",
  "registry": "ghcr.io/example/opk",
  "signing_keys": ["RWS...base64..."],
  "packages": [
    {
      "name": "ripgrep",
      "family": "ripgrep",
      "description": "Recursively search directories for a regex pattern",
      "license": ["MIT", "Unlicense"],
      "homepage": ["https://github.com/BurntSushi/ripgrep"],
      "category": ["ConsoleOnly", "Utility"],
      "tag": ["grep", "search"],
      "provides": ["rg"],
      "aliases": ["ripgrep-cli"],
      "variant_of": null,
      "releases": [
        {
          "version": "14.1.1", "revision": 1, "epoch": 0, "channel": "stable",
          "created": "2026-05-01T00:00:00Z",
          "hosts": {
            "x86_64-linux": {
              "digest": "sha256:d4311144c0b4d63b4e2f6e22e3286602a9f8508fe14a02822c9c0ba1e5f60b07",
              "payload_blake3": "b3:0e5f0c9d...",
              "size": 5242880,
              "portable": true,
              "min_kernel": null,
              "signed": true
            }
          }
        }
      ]
    }
  ]
}
```

⛔ **The client resolves to `digest`, and fetches by digest.** Everything else
in the entry is for choosing which digest.

⭐ **`payload_blake3` is in the index on purpose.** It lets the client verify
the payload against a value that came through the *signed index*, not through
the registry. If the registry served a different manifest, the manifest digest
check catches it; if the registry served a manifest whose metadata layer was
also swapped, this catches it. Two independent paths to the same fact.

### 3.1 Fields the index carries that metadata does not

| field | why here |
| --- | --- |
| `signed` | so a client under a signature-requiring policy can filter before fetching |
| `aliases` | flattened from every release, for search |
| `variant_of` | so a search for `ffmpeg` can mention `ffmpeg-full` |
| `downloads` | ⚠ optional, mutable, and never affects resolution |

⛔ **`downloads` is presentation only.** Popularity that influenced which
version resolves would make an attacker's inflated count a resolution input.

---

## 4. Signing and freshness

```
catalog.json.zst ── sha256 ──> digest ── minisign ──> catalog.minisig
```

⛔ **The signature covers the digest of the compressed catalogue**, and the
trusted comment carries the generation timestamp and the repository name.

**Freshness.** ⚠ A signed index is still a *replayable* index: an attacker who
can serve stale content can pin a client to an old catalogue and hide a
security update.

| control | effect |
| --- | --- |
| ⭐ the signed trusted comment carries `generated` | a client compares it against the last index it saw |
| a client **MUST** refuse an index whose `generated` is older than the one it already has | ⛔ rollback protection |
| a client **SHOULD** warn when `generated` is more than `max-index-age` old, default 14 days | staleness is visible |
| the generator publishes a snapshot tag per run | a specific index can be pinned and audited |

⚠ **This is weaker than a TUF-style timestamp role and the design says so.**
A determined attacker who controls the client's network can serve a valid,
signed, merely old index up to the staleness warning. Closing that fully needs
an online signing key with a short expiry, which is a different operational
model. Recorded in [`../open-questions.md`](../open-questions.md).

---

## 5. Generation

Inputs: the package tree, and the registry.

```
for each recipe in packages/:
    for each release file:
        for each host:
            resolve the tag to a manifest digest      ← registry
            fetch the manifest                        ← registry
            read dev.opk.* annotations
            fetch the metadata layer                  ← registry
            check: annotations agree with metadata    ⛔ a mismatch fails
            check: the recipe's identity agrees       ⛔ a mismatch fails
            discover referrers, record `signed`
            emit a host entry
```

⛔ **The generator fails on disagreement rather than preferring a source.**
Annotations, the metadata layer and the recipe are three copies of the same
identity. Where they differ, one of them is wrong and picking one silently is
how a corrupted entry enters a catalogue clients trust.

⚠ **The generator needs no credentials for a public repository**, which means
anyone can regenerate the index and compare it to the published one. That is a
cheap and effective audit, and
[`../workflows/maintainer.md`](../workflows/maintainer.md) recommends it.

⭐ **Generation is incremental and idempotent.** The generator caches by
manifest digest, so a run that changes one package re-reads one package. A full
rebuild is always available and **MUST** produce byte-identical output to an
incremental run over the same state; a scheduled job asserts it.

---

## 6. Search, on the client

Search is local. The client has the catalogue.

| query | matches |
| --- | --- |
| `opk search rg` | name, provides, aliases, exact first |
| `opk search --description json` | descriptions |
| `opk search --provides rg` | ⭐ only what installs a program called `rg` |
| `opk search --category Development` | categories |

**Ranking**, in order: exact name, exact provides, exact alias, name prefix,
provides prefix, substring in name, substring in description. Ties break by
name, ascending. ⛔ Deterministic and independent of download counts.

⚠ **`opk search` with no index is an error, not an empty result.** An empty
result reads as "that package does not exist" and would be wrong.

---

## 7. Size and growth

⚠ **No measured figure is available for a real catalogue at scale**, because
this repository has not built one. The historical system's equivalent is a
62 MB JSON file (`GHCR_PKGS.json` in `pkgforge/metadata`, observed
2026-09-02), compressing to 318 KB with zstd, a ratio near 200 to 1. That is
one data point about *their* schema, not a prediction about this one, and it is
recorded because the order of magnitude is the useful part.

Design responses, none of which depend on that figure:

- the client fetches the compressed catalogue and decompresses locally;
- ⭐ the client caches by digest and skips the download when the index tag
  resolves to a digest it already has;
- a `catalog-lite.json` layer carries names, versions and digests only, for
  clients that never search;
- the SQLite form allows a client to query without loading everything.

⛔ **Splitting the catalogue per architecture is deliberately not done.** The
historical system publishes one file per host triple, and the consequence is
that `opk search` cannot tell a user "this exists, but not for your machine",
which is the single most useful thing a search can say when a package is
missing.
