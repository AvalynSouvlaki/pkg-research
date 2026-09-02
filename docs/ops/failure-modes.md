# failure modes

⭐ **The table to read during an incident.** What breaks, how it presents, what
to do.

Sorted by how often it will happen, not by severity.

---

## 1. The table

| # | failure | presents as | ⭐ first action | prevention |
| --- | --- | --- | --- | --- |
| F1 | ⭐ user's PATH not set | ⭐ "command not found" after a successful install | ⭐ `eval "$(opk env)"` | the client warns at install |
| F2 | index stale | old versions resolve | `opk update` | freshness warning at `max-index-age` |
| F3 | upstream release URL 404s | the update bot fails on one package | ⭐ check whether upstream retagged; re-pin | ⛔ hashes catch a *changed* artefact, not a removed one |
| F4 | a build breaks after an upstream change | one host red on a bot pull request | ⭐ read `opk log --failed`; fix the recipe | none; this is the job |
| F5 | ⛔ a build linked dynamically | ⭐ verifier check V3 fails | ⭐ check the target is `*-musl` and the static flag | ⭐ V3 is mandatory, so it never ships |
| F6 | ⛔ a cross-build produced the native architecture | verifier check V2 fails | check `[build.target]` and the toolchain | ⭐ V2 is mandatory |
| F7 | a cache serves a variant under an unqualified key | ⚠ "Exec format error" on a binary that was fine | ⛔ clear the cache; ⭐ key by platform | ⭐ name the variant on every fetch |
| F8 | registry rate limit | 429, builds and installs fail | ⛔ honour `Retry-After`; ⚠ reduce `max-parallel` | budget, [`rate-limits.md`](rate-limits.md) |
| F9 | ⛔ **a lost fallback-tag entry** | ⭐ a package reads as unsigned | ⭐ re-run reconciliation | ⛔ serialise per subject; [`../ci/ci-system.md`](../ci/ci-system.md) §3.1 |
| F10 | signing workflow fails | artefact published unsigned; ⛔ clients refuse | ⭐ re-run signing; alert is urgent | ⛔ never `continue-on-error` |
| F11 | index generation fails | ⚠ the previous index stands; new packages invisible | re-run; check the disagreement it refused on | it fails loudly by design |
| F12 | ⛔ a reproducibility mismatch | the weekly job reports SUSPECT | ⭐ [`../workflows/maintainer.md`](../workflows/maintainer.md) §7 | pin `deps`; use a project image |
| F13 | GHCR outage | pushes and pulls fail | ⭐ clients fall back to mirrors; CI waits | mirrors, [`../registry/mirroring.md`](../registry/mirroring.md) |
| F14 | a base image digest no longer resolves | ⛔ every build of that family fails | ⭐ bump the digest; ⚠ old builds are unreproducible from here | ⭐ mirror pinned base images |
| F15 | disk full on a runner | ⚠ a build fails with an unrelated-looking error | ⛔ classify as infrastructure, not as the package | detect and label; [`../ci/error-reporting.md`](../ci/error-reporting.md) §4 |
| F16 | disk full on a client | install fails mid-unpack | ⭐ staging is removed; suggest `opk gc` | ⛔ check free space before staging |
| F17 | client state corrupted | commands disagree with the filesystem | `opk fsck --repair` | ⭐ the filesystem is authoritative |
| F18 | a stale lock after a crash | the client hangs waiting | ⭐ automatic: liveness check, then break with a warning | |
| F19 | a hash mismatch on download | ⛔ install refused, exit 13 | ⛔ **investigate**; do not retry blindly | this is the system working |
| F20 | a conflicting `provides` | install refused, exit 16 | ⭐ pick a resolution; the message lists them | detected before staging |
| F21 | ⚠ a package needs a newer kernel | refused, naming the version | ⭐ install an older revision | `min_kernel` declared |
| F22 | ⛔ `SIGILL` on older hardware | a crash with no message | ⛔ the package raised its microarchitecture without a baseline | ⛔ baseline is mandatory |
| F23 | a mirror is behind the index | ⛔ a blob 404s at fetch | ⭐ fall back to the primary | ⛔ mirrors sync packages before the index |
| F24 | ⛔ a secret in a published log | discovered later | ⛔ **revoke first**, then scrub | ⛔ no secret in the container |

---

## 2. The three that are most costly

### F9: a lost fallback-tag entry

⭐ **Costly because it is silent and it looks like something else.**

A package whose signature entry was lost in a concurrent write reads as
unsigned. Under the default trust policy every client refuses it. Users report
"the package is broken", maintainers look at the build, and the build is fine.

| | |
| --- | --- |
| detect | ⭐ a scheduled job re-reads every fallback index and compares against the referrers it expects |
| repair | rewrite the index with the full set |
| prevent | ⛔ serialise writes per subject digest |

### F12: a reproducibility mismatch

⭐ **Costly because it is ambiguous.** It usually means an unpinned dependency
moved, and it can mean a builder was tampered with. Distinguishing them takes
work, and the temptation is to assume the boring answer.

⛔ **Re-run on a third runner before concluding anything.** A control run once
is a coincidence you have not noticed yet.

### F14: a base image digest that no longer resolves

⭐ **Costly because it is unrecoverable after the fact.** Once the image is
gone, every artefact built with it can never be reproduced, and the
reproducibility claim for those artefacts is dead.

⛔ **Mirror every pinned base image**, and treat this as urgent when it happens.

---

## 3. Diagnosis

⭐ **Start here, in this order.**

```
1. is it one package, one host, one user, or everything?
     one user            -> F1, F16, F17, F18
     one package+host    -> F4, F5, F6, F21, F22
     one package, all    -> F3, F9, F10, F12
     everything          -> F2, F8, F11, F13, F14
2. does `opk doctor` on an affected client say anything?
3. does `opk verify --explain` name a specific step?
4. does the failure record or build log exist? ⭐ if not, that is itself the finding.
```

⭐ **The blast-radius question first is what keeps an incident from becoming an
afternoon.** "One user" and "everything" have almost disjoint causes.

---

## 4. Failures a monitor should catch

| signal | threshold | means |
| --- | --- | --- |
| ⭐ index age | ⭐ over 24 h | F11, or the schedule stopped |
| unsigned published artefacts | ⭐ any | F10 |
| fallback indexes missing an expected referrer | ⭐ any | F9 |
| build failure rate | ⚠ over its own baseline | F13, F14, or infrastructure |
| ⭐ reproducibility mismatches | any | F12 |
| registry 429 rate | ⚠ over a few percent | F8 |
| ⛔ a base image digest that stops resolving | any | F14 |
| ⛔ log scrubber redaction count | ⭐ any non-zero | F24 |

⛔ **A non-zero redaction count is an incident, not a success.** Something put a
credential where it could be printed, and the scrubber is a backstop rather than
a control.

---

## 5. Recovery

| lost | recoverable | how |
| --- | --- | --- |
| the index | ⭐ yes | regenerate from the tree and the registry |
| ⭐ client state | ⭐ yes | `opk fsck --repair` from the filesystem |
| a published artefact, still in the tree | ⭐ yes | rebuild and republish |
| ⭐ a signature | ⭐ yes | re-sign the digest |
| ⛔ a signing key | ⚠ no | rotate, re-sign the archive |
| ⛔ a base image that vanished | ⛔ no | ⚠ old artefacts become unreproducible |
| ⛔ an upstream source that vanished | ⛔ no | ⚠ mirror sources for anything critical |

⭐ **Almost everything is recoverable because almost everything is derived.**
The package tree in git and the signing key are the only two things whose loss
is not repairable by recomputation, which is what
[`long-term-maintenance.md`](long-term-maintenance.md) plans around.

---

## 6. What has actually failed here

⚠ **This repository has no deployment**, so every row above is analysis rather
than incident history. What did fail, during development, is recorded because
it is real:

| | |
| --- | --- |
| ⛔ a referrers listing captured before an attach | the signature lookup searched a stale list and reported a verification failure |
| ⛔ a guard that passed while testing nothing | a `minisign` verify against a *missing* file also exits non-zero |
| ⛔ a media type storing a path instead of a basename | a build log could not be retrieved after being attached |
| ⚠ a number taken from a token count instead of a file count | 133 published where 29 was correct |

⭐ **Three of the four were found by running the thing, not by reading it**, and
the fourth by re-deriving a number before publishing it. That ratio is the
argument for the experiments directory.
