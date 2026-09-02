# lessons

What was learned here, tagged, with its source.

| tag | means |
| --- | --- |
| ⭐ `adopt` | do this. It was measured or it was paid for. |
| ⛔ `avoid` | rejected, with the reason, so nobody re-derives it |
| `future` | a good idea, not now, with what would make it now |
| ⛔ `off-host` | ⛔ **A claim about how software behaves on a machine you do not have is inferred, not documented.** Two such claims here survived six review passes and were disproved by a sibling project measuring 11 distributions: [`interop/glibc-research.md`](interop/glibc-research.md). ⭐ Label them, or measure them. |
| ⚠ `honest-limit` | a truth to keep documented where a user will see it |

---

## From building this

| tag | lesson | source |
| --- | --- | --- |
| ⭐ `adopt` | ⭐ **Plant the defect before believing a guard.** A signature check here passed while testing nothing, because a verify against a *missing* file also exits non-zero. | `30-oci-pipeline.sh`, first run |
| ⭐ `adopt` | ⭐ **Derive a number with a script rather than writing it.** Three counting errors in one session; the response was a counter, not more care. | [`history/README.md`](history/README.md) §1 |
| ⭐ `adopt` | ⭐ **Assert against what came back out, not what went in.** A pipeline checking its own inputs proves the script ran. | `30-oci-pipeline.sh` |
| ⭐ `adopt` | **A 404 is evidence only beside a control.** Two controls turn "the endpoint returned 404" into "the API is absent". | `40-registry-conformance.sh` |
| ⭐ `adopt` | ⭐ **Read the artefact, not the tool's prose.** `file` differs between "statically linked" and "static-pie linked", so a grep rejects a portable binary. | [`history/README.md`](history/README.md) W5 |
| ⛔ `avoid` | ⛔ **Do not cache a listing across a mutation.** The referrers listing captured before an attach made a later lookup search a stale set. | same |
| ⛔ `avoid` | ⛔ **Do not read a token frequency as a file count.** `grep -o` and `grep -l` answer different questions. | W1 |
| ⚠ `honest-limit` | ⚠ **A same-host rebuild demonstrates timestamps and paths and nothing about toolchains.** | [`build/reproducibility.md`](build/reproducibility.md) §6 |

---

## From the reference sweep

| tag | lesson | source |
| --- | --- | --- |
| ⭐ `adopt` | ⭐ **The strategy set determines the maintenance burden.** 3.1% disabled for nix against 92% for hand-written C builds, in one tree. | [`history/references/README.md`](history/references/README.md) §5 |
| ⭐ `adopt` | ⭐ **Publish the build log with the artefact.** The most useful property era 1 had, and era 3 lost it. | §6.1 |
| ⭐ `adopt` | **Reproducibility checks belong off the publish path.** Rebuilding twice in one job catches only timestamps and paths. | `pkgforge/builds` |
| ⭐ `adopt` | ⭐ **A changed hash on an unchanged version is free evidence of an artefact swapped in place.** | era 3 |
| ⭐ `adopt` | **Require a `reason` for building rather than pinning.** It keeps the built set small on purpose. | `pkgforge/builds` |
| ⛔ `avoid` | ⛔ **Never let a version string out of an unvalidated pipeline.** `445.3p3` reached a public index for upstream `5.3p3`. | X1 |
| ⛔ `avoid` | ⛔ **Never pass a credential into a build script.** Three tokens were documented as available in era 1's. | X2 |
| ⛔ `avoid` | ⛔ **Never interpolate a comment body into a shell.** In a job holding four write permissions. | X5 |
| ⛔ `avoid` | ⛔ **Never `continue-on-error` a step whose absence changes what is published.** Provenance was silently optional. | X7 |
| ⛔ `avoid` | ⛔ **Never let signing fail open.** A warning and `exit 0` published unsigned metadata as success. | X8 |
| ⛔ `avoid` | ⛔ **Never `--latest --upgrade` in a builder image.** 830 lines of it, with `set +e` and `2>/dev/null`. | X9 |
| ⛔ `avoid` | ⛔ **Never scrub a log by deleting lines matching common English words.** It destroys compiler errors and misses tokens in URLs. | X6 |
| ⛔ `avoid` | ⛔ **Never let a mirror rewrite what it mirrors.** | X15 |
| ⚠ `honest-limit` | ⚠ **A disabled package with no reason is information destroyed.** 385 of them. | X18 |
| `future` | ⚠ A bundle format for software that cannot be static. ⭐ What would make it now: a measured demand from users whose packages are refused. | [`open-questions.md`](open-questions.md) Q11 |
| `future` | ⚠ Binary delta updates. ⭐ What would make it now: a measurement showing a delta is a small fraction of the artefact. | Q8 |

---

## About documentation

| tag | lesson |
| --- | --- |
| ⭐ `adopt` | ⭐ **A page nothing links to is a finding.** `check-links.sh` found a double home the moment it existed. |
| ⭐ `adopt` | ⭐ **State what was not established before the recommendations.** A reader who reaches the recommendation first has stopped reading. |
| ⭐ `adopt` | **Label every claim observed, measured, inferred or recommended.** A reader needs to know which sentences survive a different machine. |
| ⛔ `avoid` | ⛔ **Do not stack a dated correction under retired text.** Rewrite the rule; move the old wording to the history. |
| ⚠ `honest-limit` | ⚠ **A specification with 36 automated checks out of 75 requirements is a specification, not an implementation.** Saying so is more useful than a green badge. |
