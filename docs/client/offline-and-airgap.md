# offline and air-gapped operation

Installing with no network, and moving packages across a boundary no network
crosses.

---

## 1. Three degrees

| degree | means | mechanism |
| --- | --- | --- |
| **cached** | the network is down, this machine already has the bytes | ⭐ the local cache |
| **mirrored** | a network exists, but only reaches an internal mirror | [`../registry/mirroring.md`](../registry/mirroring.md) |
| ⭐ **air-gapped** | no network reaches the outside at all | ⭐ bundles, §3 |

⛔ **Verification is identical in all three.** Offline changes where bytes come
from, never whether they are checked. A bundle carries its own signatures and
they are verified on install.

---

## 2. Cached operation

```sh
opk install ripgrep --offline
```

| condition | behaviour |
| --- | --- |
| index cached, fresh | ⭐ resolve normally |
| index cached, stale | ⚠ warn with its age; proceed |
| index cached, older than `max-index-age` | ⛔ refuse unless `--allow-stale-index` |
| index absent | ⛔ exit 10 |
| package blobs cached | ⭐ install, verifying as usual |
| blobs absent | ⛔ exit 17, naming what is missing |

⭐ **Pre-populating a cache is a supported workflow**, not an accident:

```sh
opk install ripgrep fd bat --download-only
```

⚠ **Cache eviction can silently undo it.** A `--download-only` run followed by a
`gc` that evicts what was fetched leaves a machine that thought it was ready.
`--pin-cache` marks blobs as not evictable.

---

## 3. Bundles

⭐ **A single file carrying packages, their evidence, and enough index to
resolve them.**

```sh
opk bundle create ripgrep fd bat@8.7.0 -o tools.opkb
opk bundle verify tools.opkb
opk bundle install tools.opkb
```

### 3.1 Format

⛔ **An OCI image layout directory in a normalised tar**, not a bespoke format.

```
tools.opkb  (tar, normalised per artifact-layout.md §6)
  oci-layout                       {"imageLayoutVersion": "1.0.0"}
  index.json                       the OCI index: every package manifest
  blobs/sha256/<digest>            every layer, manifest and referrer
  opk-bundle.json                  ⭐ what this bundle is
  opk-bundle.json.minisig          its signature
```

⭐ **Using the OCI layout means `oras`, `skopeo` and `crane` can all read a
bundle**, and a bundle can be pushed into a registry with one command:

```sh
oras cp --from-oci-layout ./tools:ripgrep-14.1.1-1 registry.internal/opk/ripgrep/ripgrep:14.1.1-1
```

### 3.2 `opk-bundle.json`

```json
{
  "schemaVersion": 1,
  "created": "2026-09-01T10:04:11Z",
  "source_index": {
    "repository": "official",
    "generated": "2026-09-01T09:00:00Z",
    "digest": "sha256:aabbcc..."
  },
  "hosts": ["x86_64-linux", "aarch64-linux"],
  "packages": [
    { "name": "ripgrep", "version": "14.1.1", "revision": 1,
      "host": "x86_64-linux", "digest": "sha256:d4311144...",
      "payload_blake3": "b3:0e5f...", "signed": true }
  ],
  "includes": { "signatures": true, "provenance": true, "sbom": true, "buildlogs": false }
}
```

⛔ **`includes` is explicit.** A bundle without signatures is usable only under
`hash-only`, and the receiving side must be able to tell before it imports.

⭐ **`source_index` records which index this was cut from**, so a receiving side
knows how stale it is without trusting the bundle's own `created`.

### 3.3 ⛔ Verification on import

```
1. verify opk-bundle.json's signature against the trusted key set
2. ⛔ verify every blob hashes to its filename
3. verify each manifest's digest
4. verify each package signature, if present
5. ⛔ verify each package's payload hash against the bundle manifest
6. install
```

⛔ **Step 2 is not optional.** An OCI layout is a directory of files named by
digest, and nothing enforces that a file's contents match its name except the
importer.

⚠ **A bundle is a trust boundary crossing.** It arrives on removable media from
outside. Verifying it fully on import is the entire point, and skipping steps
because "it came from our own build" is how the air gap becomes decorative.

---

## 4. Air-gapped workflow

```
  OUTSIDE                              │        INSIDE
                                       │
  opk bundle create ... -o t.opkb      │
  sha256sum t.opkb  ────── recorded ───┼──► compared by hand
                                       │
      [ removable media ] ─────────────┼──►  opk bundle verify t.opkb
                                       │     opk bundle install t.opkb
                                       │
                                       │  or: push into an internal registry
                                       │     oras cp --from-oci-layout ...
```

⭐ **Two options inside**, and the second is better for more than a handful of
machines:

| | direct install | push to an internal registry |
| --- | --- | --- |
| machines | ⚠ one | ⭐ many |
| ongoing | ⚠ a bundle per update | ⭐ ordinary `opk install` |
| setup | ⭐ none | a registry to run |

⛔ **The internal registry needs the fallback tags written**, or referrer
discovery finds nothing and every package appears unsigned.
[`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) §5.2.

### 4.1 Trust inside

| approach | trade |
| --- | --- |
| ⭐ ship the public key with the client | ⭐ packages verify with their original signatures |
| ⛔ re-sign with an internal key | ⚠ loses the original attestation chain; the internal key now vouches for everything |
| `hash-only` | ⚠ hashes still checked; ⛔ no authenticity |

⭐ **Keeping the original signature is strongly preferred.** Re-signing means
the internal signer is asserting something it did not verify, unless it verified
first, in which case keeping the original signature was free.

---

## 5. Updating an air-gapped environment

```sh
# outside, incremental: only what changed
opk bundle create --since 2026-08-01 --from-index-digest sha256:aabbcc... -o delta.opkb
```

⭐ **A bundle can be incremental against a known index digest.** Layers already
present inside are omitted, which for a security rebuild fan-out is the
difference between a 40 MB transfer and a 4 GB one.

⚠ **Incremental bundles depend on the inside state being what the outside
believes.** ⛔ `opk bundle verify` refuses an incremental bundle whose base
index digest does not match what is installed, rather than installing a partial
set.

---

## 6. What does not work offline

⛔ Stated, so nobody plans around a capability that is not there.

| | why |
| --- | --- |
| ⛔ discovering a package not in the index you have | there is no other source |
| ⛔ fetching a build log not in the bundle | logs are large and excluded by default |
| ⛔ Sigstore verification that needs the transparency log | ⚠ minisign has no such dependency, which is a reason it is the baseline |
| ⛔ advisory freshness | ⚠ an air-gapped environment gets advisories on the same media, or not at all |

⭐ **The last row is the operationally serious one.** An air-gapped environment
with no advisory feed does not know its packages are vulnerable. The advisory
index is small and should be bundled on every transfer, even when no package
changed.
