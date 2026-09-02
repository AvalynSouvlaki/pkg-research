# mirroring

Replicating artefacts to another location, and the rule that makes a mirror
trustworthy.

Client-side use of mirrors is
[`../client/offline-and-airgap.md`](../client/offline-and-airgap.md). This
document is the mirror's own side.

---

## 1. Why mirror

| reason | who cares |
| --- | --- |
| the primary registry is unavailable | ⭐ everyone, at some point |
| a network cannot reach the primary at all | air-gapped and restricted environments |
| pull rate limits on a shared primary | large organisations, CI fleets |
| latency, or egress cost | anyone geographically distant |
| ⚠ long-term preservation | historians, and anyone whose vendor disappears |

---

## 2. ⛔ The rule

**A mirror copies bytes. It never creates them.**

| a mirror MAY | a mirror MUST NOT |
| --- | --- |
| copy manifests, blobs and tags | ⛔ re-sign anything |
| serve a subset | ⛔ recompress a layer |
| add its own signature **alongside** the original | ⛔ replace the original signature |
| refuse to carry something | ⛔ rewrite a manifest, including annotations |
| be slower, or behind | ⛔ serve a digest that does not hash to its content |

⭐ **Every artefact keeps its original digests**, so a client verifies a
mirrored artefact against the same signed index it would use for the primary.
The mirror is not a party the client trusts; it is a transport.

⚠ **This is the rule the studied system's mirror breaks, and it is instructive
rather than a criticism made in passing.** `sync_hf_mirror.sh` in
`pkgforge/metadata` rewrites URLs inside the mirrored JSON with `sed`, changing
`https://api.ghcr.pkgforge.dev/...?tag=X&download=Y` into
`https://hf.bincache.pkgforge.dev/.../X/Y`. The intent is reasonable, so that
mirrored metadata points at the mirror. The consequence is that the mirrored
metadata is not the metadata that was published, so it cannot be verified
against anything, and any signature over it would no longer match.

⭐ **The fix is to keep the artefact byte-identical and put the rewrite in the
client.** The client knows which mirror it is talking to; the artefact does
not need to.

---

## 3. What is copied

| item | copied | notes |
| --- | --- | --- |
| package manifests and layers | ⭐ yes | |
| referrer manifests: signature, SBOM, provenance | ⭐ yes | a mirror without signatures is unusable under the default trust policy |
| ⛔ the `sha256-*` fallback tags | **yes, and this is the one that gets missed** | without them, referrer discovery on the mirror returns nothing |
| build logs | optional | often the largest item; a mirror may exclude them and say so |
| the index | yes | |
| failure records | optional | |

⛔ **Copying manifests without the fallback tags produces a mirror where every
package appears unsigned.** A tool copying by tag alone does not see them,
because a fallback tag is not the tag of anything a package listing shows.

---

## 4. How

### 4.1 Registry to registry

```sh
# Copies manifests, layers and referrers, preserving digests.
oras cp --recursive \
  ghcr.io/example/opk/ripgrep/ripgrep:14.1.1-1-x86_64-linux \
  mirror.example.net/opk/ripgrep/ripgrep:14.1.1-1-x86_64-linux
```

```sh
# skopeo copies every manifest in an index in one call.
skopeo copy --all \
  docker://ghcr.io/example/opk/ripgrep/ripgrep:14.1.1-1 \
  docker://mirror.example.net/opk/ripgrep/ripgrep:14.1.1-1
```

⚠ **`--recursive` copies referrers where the source registry has the referrers
API.** On GHCR it does not, so referrers must be enumerated through the
fallback tag and copied explicitly.

⚠ **`oras cp` takes `--from-plain-http` and `--to-plain-http`, one per side,
not `--plain-http`.** Passing the wrong one fails every copy with an error that
reads like a network problem.

⭐ **Proven by `experiments/50-mirror.sh`**, which mirrors a signed package
between two local registries and asserts, against what came back out of the
mirror, that the manifest digest is unchanged, that the same referrers are
listed, that the payload is byte-identical, and ⭐ **that the original
signature still verifies against the mirrored artefact**. 15 checks, all
passing.

### 4.2 Registry to filesystem

```sh
oras copy --to-oci-layout \
  ghcr.io/example/opk/ripgrep/ripgrep:14.1.1-1-x86_64-linux \
  ./mirror-layout:14.1.1-1-x86_64-linux
```

⭐ **An OCI image layout directory is the portable form.** It is a defined
on-disk structure, it needs no registry, and it can be moved on removable
media. That is the basis of the offline bundle in
[`../client/offline-and-airgap.md`](../client/offline-and-airgap.md).

---

## 5. Verification after copy

⛔ **A mirror agent verifies what it wrote, by reading it back.** A copy tool's
exit code says the transfer returned, not that the destination holds the right
bytes.

| check | on |
| --- | --- |
| the destination manifest digest equals the source's | every manifest |
| every layer digest present at the destination | every layer |
| the fallback tag index has the same entry count | every subject |
| a sampled layer's bytes hash to its digest | ⚠ at least one per run; a full re-hash is expensive but a sample of zero is not a check |
| the signature still verifies against the destination copy | ⭐ every signed package. Measured in `experiments/50-mirror.sh`. |

⚠ **The last check is the one that catches a mirror that transformed
something.** If a mirror recompressed a layer, the digest changes, the manifest
no longer matches, and the signature fails. That is the desired outcome: a loud
failure at mirror time rather than a quiet one at install time.

---

## 6. Freshness and drift

| property | value |
| --- | --- |
| a mirror **MUST** publish its last successful sync time | in a `mirror.json` at a well-known path |
| a client **SHOULD** warn when a mirror is more than `max-mirror-age` behind | default 7 days |
| a mirror **MUST NOT** serve a channel tag it has not synced | ⛔ serving a stale `stable` silently pins users to an old version |
| a mirror **MAY** lag on packages and be current on the index | ⚠ and this is the dangerous combination: see below |

⛔ **A current index over a lagging mirror is worse than a lagging index.** The
client resolves a digest the mirror does not have and fails at fetch, with an
error about a missing blob rather than about a stale mirror. A mirror
**MUST** sync packages before the index, and the client falls back to the
primary on a missing blob rather than failing.

---

## 7. Preservation, and what the historical system got right and wrong

⭐ **Mirroring to something that is not a container registry is worth doing.**
The studied system mirrored every artefact to a Hugging Face dataset, which is
git with large-file storage. That is a genuinely different failure domain from
a container registry, and a good instinct.

Two things it teaches:

| observed | lesson |
| --- | --- |
| ⭐ the sync refuses to run when the metadata it fetched has fewer than 20 entries | a destructive sync driven by a truncated index is a real failure mode, and a floor check is a cheap guard against it |
| ⛔ it pulls by mutable tag, not by digest | a tag moved between index generation and sync is mirrored without notice |
| ⛔ it never verifies the `.sig` files it copies | a mirror that does not verify propagates a compromised artefact faithfully |
| ⚠ git-LFS accumulates every version forever with no collection | the mirror repository grows without bound |
| ⚠ pushes are serialised through one branch with retries and merge commits | throughput is capped by one writer |

**This design's answers:** mirror by digest; verify signatures during the
sync and refuse on failure; keep the floor check; use an OCI layout or a
registry rather than git for blob storage; and state a retention policy for the
mirror rather than growing forever ([`retention.md`](retention.md)).
