# maintainer workflow

Reviewing, merging, and the judgement calls that are not mechanical.

⭐ **The mechanical checks are CI's job.** This document is what a human adds.

---

## 1. What CI has already established

⛔ **Do not re-check these by hand.** If you find yourself doing so, the gap
belongs in CI.

- the recipe parses and every field is valid
- every build input is pinned
- ⛔ every pinned URL has a hash
- the version matches the grammar and is greater than the last
- it builds on every declared host
- ⛔ the artefact has no `PT_INTERP` unless declared
- ⛔ every declared `provides` path exists
- no setuid file, no path escaping the artefact root
- the licence identifier is valid SPDX

---

## 2. ⭐ What only a human can decide

### 2.1 The build script

⛔ **This is the highest-value minute of the review**, because it is the only
place in the tree that runs.

| ask | ⛔ a bad answer |
| --- | --- |
| does it fetch anything not in `[source]`, `[[tool]]` or `[[extra]]`? | ⛔ a `curl` or `wget` in the script |
| does it write outside the build tree? | ⛔ an absolute path |
| does it do anything unrelated to building? | ⛔ anything touching the network for a reason that is not a dependency |
| is it as short as it can be? | ⚠ length that should have been declarative fields |
| ⭐ would I run this on my own machine? | ⭐ the question that generalises the others |

⚠ **A script fetching an unpinned URL is the single most common real
problem**, and it is usually not malice: it is a project whose build downloads a
dependency, and the fix is `[[tool]]` or vendoring.

### 2.2 Is this package appropriate

| ask | |
| --- | --- |
| ⭐ does upstream already publish a static build? | ⭐ if so, pin theirs; do not take on a build |
| is it a program, or a library? | ⚠ this system distributes programs |
| is the name right? | not a typo of another package, not misleading |
| does the description say what it does? | ⛔ not that it is good |
| is the licence plausible for the artefact? | ⚠ a GPL dependency statically linked in changes the answer |

### 2.3 The hashes

⭐ **For a bot bump, this is the whole review.**

⛔ **A changed hash on an unchanged version means upstream replaced a published
artefact in place.** The bot highlights it; the human decides. Legitimate causes
exist, for example a re-upload after a bad build, and each one is worth
confirming with upstream before merging.

---

## 3. Reviewing a bot pull request

⭐ **Under a minute, if the tooling is doing its job.**

1. ⭐ any highlighted hash-changed-version-unchanged row: stop and investigate
2. versions look like versions, and like this project's versions
3. CI is green on every host
4. ⚠ a package that jumped several major versions: check it is the same project
5. merge

⚠ **Do not skim past a build failure on one host in a batch.** The batch is
convenient and it makes one red host easy to miss.

---

## 4. Reviewing a new package

⭐ **Two approvals recommended.** A new package adds a name, a maintainer and a
build script, and all three are permanent.

- everything in §2
- ⭐ the checklist in
  [`package-author.md`](package-author.md) §9, spot-checked
- the author has a plausible contact
- ⚠ ask why it is built rather than pinned, if it is built

---

## 5. Judgement calls

⚠ **Each of these comes up and has no mechanical answer.**

| call | ⭐ how to decide |
| --- | --- |
| a package that only builds on one architecture | ⭐ accept, with the others absent and a failure record explaining why |
| upstream has no licence file | ⭐ `NOASSERTION` plus a `note`; ⚠ do not invent one |
| a variant, or a feature? | ⭐ [`../format/variants-and-features.md`](../format/variants-and-features.md) §2 |
| a package that cannot be static | ⭐ accept with `portable = false` and a reason, or refuse if it needs the host's whole desktop stack |
| ⚠ a name close to an existing one | ⭐ ask the author; often it is legitimate |
| a huge artefact | ⚠ accept, and check it is not a shipped debug tree |
| an unmaintained upstream | ⭐ accept, and expect to disable it later with a reason |

⛔ **When refusing, say why in a sentence and point at the document.** A refusal
with no reason gets re-proposed in three months.

---

## 6. Routine work

| cadence | task |
| --- | --- |
| ⭐ daily | ⭐ review the bot's update pull request |
| daily | triage new failures, separating regressions from never-built |
| weekly | ⭐ read the reproducibility job's output |
| weekly | check the advisory job produced something sensible |
| monthly | review packages that have failed for over 30 days |
| quarterly | ⭐ base image digest bumps |
| ⚠ as needed | key rotation, per its schedule |

⭐ **The weekly reproducibility read is the one that is easy to drop and worth
keeping.** It is the only signal that a builder has been tampered with, and a
job nobody reads is a job that is not running.

---

## 7. Handling a reproducibility failure

⛔ **`SUSPECT` does not unpublish.**
[`../architecture.md`](../architecture.md) §6.1.

```
1. ⭐ re-run the rebuild on a third runner. Two of three is the signal.
2. diff the artefacts: diffoscope, else the fallbacks in
   ../build/reproducibility.md §3.2
3. attribute:
     a timestamp or path      -> a recipe bug; fix and bump the revision
     ⚠ a toolchain difference -> the image digest moved, or deps drifted
     ⛔ neither               -> ⛔ treat as a possible compromise; §8
4. record the finding on the package's issue either way
```

⚠ **Most reproducibility failures are boring**, and the boring ones still need
recording, because the pattern across packages is what identifies an unpinned
dependency nobody noticed.

---

## 8. Incident response

⛔ **When an artefact may have been tampered with.**

| # | step |
| --- | --- |
| 1 | ⭐ do not delete anything: the bytes are evidence |
| 2 | mark the release in the advisory index so clients warn |
| 3 | rebuild from the recipe on a clean runner and compare |
| 4 | if it differs, ⛔ revoke the signature and publish the revocation |
| 5 | ⛔ rotate any credential that could have been involved |
| 6 | rebuild, republish with a bumped revision, re-sign |
| 7 | write it up in the changelog and in `docs/history/` |

⛔ **Revocation before deletion.** Deleting removes one copy of something users
already have; revocation is what stops clients accepting it.
[`../security/secrets.md`](../security/secrets.md) §5.

---

## 9. Independent rebuild

⭐ **Anyone can check a published artefact, and a maintainer should
occasionally.**

```sh
# From the published metadata alone.
opk info ripgrep --json | jq -r '.build.recipe_url'
git clone https://github.com/example/opk-packages && cd opk-packages
git checkout 4d5e6f
opk build ripgrep --host x86_64-linux
sha256sum dist/ripgrep-14.1.1-1-x86_64-linux.tar.zst
opk info ripgrep --json | jq -r '.artifact.files[] | select(.path=="bin/rg") | .sha256'
```

⭐ **That the metadata carries the recipe URL, the recipe hash, the image
digest, the source commit and the epoch is what makes this five commands rather
than an investigation.**

---

## 10. Taking the project over

⭐ **What a new maintainer needs, in order.**

1. [`../../README.md`](../../README.md), then
   [`../architecture.md`](../architecture.md)
2. [`../ops/operations.md`](../ops/operations.md): the runbooks
3. [`../security/secrets.md`](../security/secrets.md): what credentials exist
   and who holds them
4. ⛔ ⭐ the signing keys: custody, rotation schedule, and ⛔ **who else has
   them**
5. [`../ops/failure-modes.md`](../ops/failure-modes.md): what breaks
6. [`../history/README.md`](../history/README.md): ⭐ what was tried and why it
   changed

⛔ **A project whose signing key has one holder is one accident from being
unmaintainable.** Custody is the first thing to fix on taking over, and
[`../ops/long-term-maintenance.md`](../ops/long-term-maintenance.md) says how.
