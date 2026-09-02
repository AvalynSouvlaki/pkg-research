# abuse prevention

What a hostile or careless contributor can attempt, and what stops it.

The security model is
[`../security/security-model.md`](../security/security-model.md). This is the
**operational** side: what a project running this system does about people.

---

## 1. ⭐ The structural defence

⛔ **There is no self-service publish.** Every package enters through a merged
pull request. That single property removes most of what abuse-prevention pages
in other ecosystems exist to handle.

| attack this removes | why |
| --- | --- |
| ⭐ mass typosquatting | ⭐ each name costs a human review |
| ⭐ a malicious package uploaded and pulled before anyone notices | it is never live before review |
| namespace squatting at scale | same |
| ⚠ an abandoned package taken over by a new owner | ⭐ there is no per-package owner to transfer |

⚠ **The cost is that the project's review capacity is its publishing rate.**
That is the trade this design accepts, and
[`../ci/update-automation.md`](../ci/update-automation.md) is what keeps the
routine 74.6% of pull requests from consuming it.

---

## 2. What is still possible

| # | attempt | control |
| --- | --- | --- |
| A1 | ⭐ a malicious build script in a plausible package | ⛔ human review; §3 |
| A2 | a name close to a popular one | ⭐ the validator flags edit distance 1 |
| A3 | ⚠ CI resource exhaustion | timeouts, memory caps, `max-parallel` |
| A4 | ⚠ a pull-request flood | ⭐ rate limits on first-time contributors |
| A5 | a huge artefact filling storage | `[verify].max-size`, and a review |
| A6 | ⛔ using the build network to attack a third party | ⭐ `network` allowlist |
| A7 | a package whose licence is not what it claims | ⚠ review; ⛔ not mechanically checkable |
| A8 | ⛔ a long-lived contributor turning hostile | ⚠ §5 |
| A9 | ⚠ exhausting a maintainer's attention with plausible noise | ⭐ §4 |

---

## 3. A1: the malicious build script

⭐ **The one that matters, and the one with no mechanical answer.**

What makes it tractable:

| | |
| --- | --- |
| ⭐ the script is the only executable part of the tree | one place to look |
| ⭐ it is short | fetching, patching and collection are declarative fields |
| ⛔ it holds no credential | nothing to steal |
| ⛔ the artefact map bounds its output | it cannot publish extra files |
| ⚠ CI on a fork has no secrets | a hostile build gains nothing from running |

⚠ **What it can still do**: corrupt the artefact it compiles. A malicious patch
applied to a legitimate source produces a legitimate-looking binary.

⭐ **The residual controls are attribution rather than prevention**: the recipe
is pinned in the provenance, the build log records every command, and the
artefact reproduces, so the malicious change is in the tree with a name against
it.

⛔ **A project that cannot review build scripts should not accept
source-built packages.** Accepting only URL-pinned packages, where the artefact
comes from upstream and the tree carries only a hash, is a coherent and much
smaller-surface posture. It is what the studied system's third era chose.

---

## 4. A9: attention exhaustion

⚠ **The most likely real problem, and it does not look like an attack.**

A stream of low-quality pull requests, each individually plausible, each needing
a maintainer to read a build script. Nobody is being malicious; the capacity is
gone all the same.

| control | |
| --- | --- |
| ⭐ a template that front-loads the review questions | why built rather than pinned, what the script does |
| ⭐ CI does everything mechanical first | ⛔ a maintainer never reviews something that has not built |
| a queue with a stated response time | expectations rather than silence |
| ⭐ triage labels applied by a bot | `needs-build`, `needs-review`, `needs-author` |
| ⚠ closing stale pull requests with a reason | ⛔ a queue nobody can clear is a queue nobody reads |

⭐ **"CI does everything mechanical first" is the highest-value item here.** A
maintainer reading a script for a package that does not build is spending the
scarcest resource on the least useful thing.

---

## 5. A8: a trusted contributor turning hostile

⛔ **Not preventable, and it is bounded.**

| bound | |
| --- | --- |
| ⭐ merge does not publish alone | the sign workflow verifies independently |
| ⭐ signing is separated from CI | [`../security/security-model.md`](../security/security-model.md) §4 |
| ⚠ two approvals for a new package | recommended, not enforced by this design |
| ⭐ the reproducibility job | a build that stops reproducing is visible |
| ⭐ everything is attributable | git history, provenance, build log |

⚠ **A maintainer with both merge rights and the signing key is the single
point.** That is why key custody is the first thing
[`../workflows/maintainer.md`](../workflows/maintainer.md) §10 tells a new
maintainer to check.

---

## 6. First-time contributors

⭐ **GitHub's default requires approval before a workflow runs for a first-time
contributor. Keep it.**

| control | |
| --- | --- |
| ⭐ workflow approval required | ⛔ the default; do not disable it |
| ⚠ a limit on concurrent open pull requests per new account | ⭐ prevents A4 |
| ⭐ a template asking the questions review needs | reduces round trips |

⚠ **Disabling the approval requirement is the convenience that opens A3 and
A4 at once**, and the reason projects disable it is that approving runs is
tedious.

---

## 7. Takedown

A package must sometimes be removed for reasons that are not technical: a
licence violation, unlawful content, a trademark complaint.

⛔ **Follow [`../registry/retention.md`](../registry/retention.md) §5.** The
bytes go, a tombstone stays, and the coordinate is never reused.

| | |
| --- | --- |
| ⭐ who decides | a named maintainer set, not one person |
| ⭐ what is recorded | the coordinate, the digest, the date, the reason, a contact |
| ⚠ what is not recorded | ⛔ personal details of a complainant |
| appeal | a stated route, or say plainly that there is none |

⚠ **A takedown with no public record is indistinguishable from a compromise.**
A user whose pinned package vanished needs to be able to tell which happened.

---

## 8. Reporting

⭐ **A security contact that is monitored, and a stated response time.**

| | |
| --- | --- |
| where | `SECURITY.md` at the repository root |
| ⭐ for a suspected compromised artefact | ⭐ a private channel, and it is answered first |
| for a malicious package | private, then public once handled |
| ⚠ for a build failure | ⛔ the ordinary issue tracker; ⚠ do not route noise into the security channel |

⛔ **A security channel that receives ordinary bug reports stops being read.**
The distinction is stated in `SECURITY.md` and enforced by triage rather than
by hoping.
