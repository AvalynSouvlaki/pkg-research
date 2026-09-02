# retention and garbage collection

What is kept, for how long, and what removes it. Registry side. The client's
disk is [`../client/delta-and-gc.md`](../client/delta-and-gc.md).

---

## 1. ⛔ The rule that constrains everything else

**A digest a user may have pinned is never deleted while any supported client
could still resolve it.**

Deleting a published artefact breaks:

- a user who pinned `ripgrep@14.1.1-1` in a script or a lockfile;
- a rollback to a previous version;
- an offline bundle that references it;
- reproducing a build whose provenance names it as an input;
- any audit of what was shipped.

⚠ **This is in tension with cost and with security, and the tension is real
rather than rhetorical.** Keeping everything forever costs storage and keeps
known-vulnerable artefacts installable. §4 is how both are handled without
deleting.

---

## 2. The policy

| item | retention | rationale |
| --- | --- | --- |
| a released package version, any host | ⭐ **indefinite** | §1 |
| its metadata, checksums, signature | indefinite | useless without them |
| its provenance and SBOM | indefinite | an audit years later is the point |
| its build log | ⭐ **indefinite, compressed** | a log outliving its build is the whole value |
| a **failure record** | 90 days | it answers "why is this missing"; that question expires |
| a **prerelease** on `nightly` | 30 days, or the last 10, whichever is more | |
| an index snapshot tag | 2 years | audit trail |
| the moving `:v1` index tag | current only | |
| an untagged, unreferenced manifest | ⛔ immediately eligible | §3 |

⚠ **"Indefinite" is a policy, not a physical law.** An operator with a storage
budget will eventually need §5.

---

## 3. What is safe to collect

⭐ **Untagged and unreferenced manifests are the only category that is
unambiguously garbage**, and they arise routinely: a build that pushed and then
failed before tagging, a fallback index replaced by a newer one, an interrupted
mirror.

A manifest is collectable when **all** hold:

1. no tag points at it;
2. no index lists it;
3. it is not the `subject` of any referrer;
4. it is not itself a referrer of a live subject;
5. it has been in that state for at least 7 days.

⛔ **Condition 5 is not tidiness.** A push is not atomic: layers, then the
manifest, then the tag. A collector running against a push in progress deletes
blobs the tag is about to reference. Seven days is far beyond any legitimate
push.

⚠ **Condition 4 is the one that gets missed.** A referrer whose subject is
alive has no tag of its own and is reachable only through the referrers API or
the fallback index. ⛔ **On GHCR, where there is no referrers API, a collector
that checks only tags and indexes will consider every signature garbage.** The
collector **MUST** read the fallback tags.

---

## 4. Vulnerable versions: mark, do not delete

⛔ **A package with a known vulnerability is not deleted.** Deleting it breaks
reproducibility and audit, and it does not protect anyone who already installed
it.

```json
{
  "advisories": [
    {
      "id": "OPK-2026-0001",
      "packages": [ { "name": "somelib-tool", "versions": "<2.4.1" } ],
      "severity": "high",
      "references": ["https://nvd.nist.gov/vuln/detail/CVE-2026-XXXXX"],
      "fixed_in": "2.4.1-1"
    }
  ]
}
```

| effect | on |
| --- | --- |
| ⭐ the client warns loudly at install and requires `--allow-vulnerable` | install |
| `opk audit` lists installed packages matched by an advisory | an installed system |
| the index marks the release | search and resolution |
| ⛔ the bytes stay fetchable | reproducibility, forensics, rollback |

⚠ **Advisory data must be signed and fresh, exactly like the index**, or
suppressing an advisory becomes an attack. Same freshness rules as
[`index-and-search.md`](index-and-search.md) §4.

---

## 5. Takedown

Some deletions are not optional: a licence violation, a leaked secret baked
into an artefact, unlawful content.

⛔ **A takedown leaves a tombstone.** The bytes go; the record that they existed
and were removed does not.

```json
{
  "coordinate": "opk/example/example:1.2.3-1-x86_64-linux",
  "digest": "sha256:...",
  "removed": "2026-09-01T00:00:00Z",
  "reason": "upstream licence violation",
  "contact": "security@example.org"
}
```

⛔ **The coordinate is never reused**, so a client that had it pinned gets a
clear "removed, here is why" instead of silently different software.

⚠ **A leaked secret inside a published artefact is not fixed by deletion.**
Deletion removes one copy; mirrors, caches and users' disks keep theirs. The
first action is revoking the secret. Deletion is second.
[`../ops/operations.md`](../ops/operations.md) §incident.

---

## 6. GHCR specifics

⛔ **Deletion is a GitHub Packages API operation, not a registry one.** The
distribution spec's `DELETE /v2/<repo>/manifests/<digest>` is not the mechanism
GHCR exposes for this; package versions are deleted through the Packages REST
API, and the whole package through its own endpoint.

Consequences for an implementation:

| | |
| --- | --- |
| a collector needs a GitHub token with `delete:packages` | a scope no publishing workflow should hold |
| deletion is by *package version*, identified by GitHub's own ID | ⚠ not by digest, so the collector maps digest to version ID first |
| ⛔ deletion is not transactional | a partial run leaves a half-deleted version; the collector is idempotent and re-runnable |
| GHCR does its own blob collection on its own schedule | ⚠ freeing storage is not immediate and is not observable |

⛔ **The collector runs as a separate workflow with its own credential**, never
as part of a publish. A publish workflow that can also delete is one bug away
from deleting what it just published.

⚠ **Not measured here.** This repository has no GHCR namespace, so the deletion
path is specified from GitHub's documentation and has not been exercised. The
verification command is in [`../open-questions.md`](../open-questions.md).

---

## 7. Cost control without deleting

⭐ Ordered by how much they save for how little risk.

| technique | effect | risk |
| --- | --- | --- |
| deduplicate blobs across versions | ⭐ large, and registries do it automatically for identical digests | none |
| compress logs above 1 MiB | large, logs dominate count | none |
| a single payload layer per artefact rather than per file | fewer blobs, less per-blob overhead | ⚠ loses per-file fetch; see below |
| prune `nightly` per §2 | proportional to nightly volume | low |
| move artefacts older than N years to cold storage, keeping the manifest | ⚠ large | a fetch becomes slow, and the client must handle it |
| ⛔ delete old versions | large | ⛔ breaks §1 |

⚠ **The per-file layer choice is a real trade and the historical system chose
the other side.** It published fifteen separate layers per package, one per
file, which let its HTTP gateway serve `?download=b3sum.log` without fetching
the binary. This design puts the tree in one payload layer and the log in a
*referrer*, which achieves the same selective fetch with fewer blobs, because a
referrer is fetched independently anyway.
