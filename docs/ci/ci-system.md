# CI system

The workflows, their triggers, their permissions, their concurrency, and the
rule that keeps a fork's pull request from reaching a secret.

---

## 1. The workflows

| workflow | trigger | permissions | does |
| --- | --- | --- | --- |
| `validate` | `pull_request`, `merge_group` | ⭐ `contents: read` | parse and validate; ⛔ executes nothing |
| `build-pr` | `pull_request` | ⭐ `contents: read` | ⛔ build in a fork's context, no secrets |
| `build-publish` | `push` to main, `workflow_dispatch` | `contents: read`, `packages: write` | build and push |
| `sign` | ⭐ `workflow_run` after `build-publish` | `packages: write`, `id-token: write` | ⛔ the only job with a signing key |
| `index` | after `sign`, and on a schedule | `packages: write` | regenerate and sign the index |
| `update` | schedule, `workflow_dispatch` | `contents: write`, `pull-requests: write` | ⭐ open version-bump pull requests |
| `reproduce` | schedule, weekly | `contents: read` | ⭐ rebuild and compare, off the publish path |
| `advisories` | schedule, daily | `contents: write` | scan SBOMs, publish advisories |
| `retention` | schedule, monthly | ⛔ `packages: delete` only | collect unreferenced manifests |

⛔ **Every workflow declares `permissions` explicitly at the top level.** A
workflow with no block inherits the repository default, which is often write to
everything.

⛔ **`retention` is the only workflow that can delete, and it can do nothing
else.** A publish workflow that can also delete is one bug away from deleting
what it just published.

---

## 2. ⛔ The fork boundary

**This is the rule that matters most and it is the easiest to get wrong.**

| trigger | runs in | secrets | token |
| --- | --- | --- | --- |
| ⭐ `pull_request` | ⭐ the **fork's** context | ⭐ **none** | read-only |
| ⛔ `pull_request_target` | ⛔ the **base** repository's context | ⛔ **all** | writable |
| ⛔ `issue_comment` | ⛔ the base repository's context | ⛔ **all** | writable |

⛔ **A workflow that builds a contributor's recipe uses `pull_request`.
Never `pull_request_target`.**

⚠ **`pull_request_target` exists for a reason and it is not this one.** It is
for workflows that need to label or comment on a pull request without running
its code. A workflow that both holds secrets and checks out the pull request's
head is the "pwn request" shape, and it hands a repository's secrets to anyone
who can open a pull request.

### 2.1 Untrusted input into a shell

⛔ **Never interpolate an event field into a script body.**

```yaml
# ⛔ WRONG: a title containing $(...) or backticks executes.
run: echo "Building ${{ github.event.pull_request.title }}"
```

```yaml
# ⭐ RIGHT: it reaches the shell as data.
env:
  TITLE: ${{ github.event.pull_request.title }}
run: printf '%s\n' "$TITLE"
```

⚠ **The studied system's era-2 `pr-bot.yaml` does the first**, with a comment
body, in a job holding `contents: write`, `packages: write`, `id-token: write`
and `actions: write`. The gate on `author_association` narrows who can reach it
and does not close it.

---

## 3. Concurrency

```yaml
concurrency:
  group: build-${{ github.sha }}
  cancel-in-progress: false
```

⛔ **Per-commit, not per-branch.** A shared group keeps one running and one
pending per group, so a merge queue draining several package pull requests
cancels the intermediate ones and their packages are never built.

⚠ **That reasoning is adopted from the studied system's era-2 workflow, which
documents it in a comment.** It is the kind of thing that is obvious in
hindsight and expensive to discover.

| workflow | group | cancel |
| --- | --- | --- |
| `validate` | `validate-${{ github.ref }}` | ⭐ yes: only the newest matters |
| `build-pr` | `build-pr-${{ github.event.pull_request.number }}` | yes |
| `build-publish` | ⭐ `build-${{ github.sha }}` | ⛔ no |
| `sign` | ⛔ `sign-${{ subject digest }}` | ⛔ no: §3.1 |
| `index` | `index` | ⚠ no: an index run must complete |

### 3.1 ⛔ Serialising the fallback tag

⛔ **Writing a referrers fallback tag is read-modify-write and it is not
atomic.** Two attaches to one subject race and the second loses the first.

| control | |
| --- | --- |
| ⭐ signing is serialised per subject digest | one writer per tag |
| ⭐ a reconciliation step re-reads and repairs | after every attach |
| ⭐ a scheduled job re-verifies every fallback index | catches what slipped |

⚠ **A lost signature entry presents to a user as an unsigned package**, which
under the default trust policy is a refused install. This is not a cosmetic
race.

---

## 4. The build matrix

```yaml
strategy:
  fail-fast: false
  max-parallel: 4
  matrix:
    include:
      - host: x86_64-linux      runner: ubuntu-latest
      - host: aarch64-linux     runner: ubuntu-24.04-arm
      - host: riscv64-linux     runner: ubuntu-latest    # cross
```

⛔ **`fail-fast: false`.** One architecture failing must not cancel the others.
A package on three of four architectures is better than none, and the failure
record for the fourth tells a user why.

⚠ **`max-parallel` is a rate-limit control as much as a cost one.**
[`../ops/rate-limits.md`](../ops/rate-limits.md).

---

## 5. What to build

⛔ **Changed recipes, decided by content, not by whether a file was touched.**

```
changed files -> affected packages
                 for each: compute the recipe hash
                 compare against the last built hash for that host
                 build if different, or if forced
```

| property | |
| --- | --- |
| ⭐ the hash covers the recipe, its patches, and the release file | |
| ⛔ the hash includes the version | ⚠ see below |
| the last-built hash is recorded per package per host | |
| ⭐ a hash match with a `success` status skips the build | |

⚠ **The studied system's era-2 workflow computes its skip hash with
`sbuild meta hash --exclude-version`.** Reading that workflow alone, a
version-only bump produces an unchanged hash and would be skipped, which is the
opposite of what a version bump should do. Whether the tool includes the version
by another route is not determinable from the workflow, so this design states
the rule explicitly rather than inheriting an ambiguity: ⛔ **the skip hash
includes the version and the revision.**

---

## 6. Publishing

```
build ──► verify ──► push artefact ──► attach SBOM, provenance, log
                                   │
                                   └──► `sign` workflow (separate)
                                          verify independently
                                          sign the manifest digest
                                          attach, update fallback tag
                                          │
                                          └──► `index` workflow
```

⛔ **The build workflow has no signing key.**
[`../security/security-model.md`](../security/security-model.md) §4.

⛔ **The sign workflow verifies before signing.** It does not sign what it was
told to sign; it fetches the artefact, checks it against the recipe's declared
outputs, and then signs. Otherwise a compromised build workflow can get
arbitrary bytes signed by asking.

---

## 7. Failure handling

⛔ **A failed build publishes a failure record.**
[`../ci/error-reporting.md`](error-reporting.md).

| failure | action |
| --- | --- |
| validation | ⛔ no build; annotate the pull request with file and line |
| build | publish the log under `buildfailure`; comment once on the pull request |
| verification | ⛔ same, and ⛔ never publish the artefact |
| push | retry with backoff; ⚠ a partial push leaves untagged manifests that retention collects |
| sign | ⛔ alert; the artefact stays unsigned and clients refuse it under the default policy |
| index | ⛔ alert; the previous index stays published |

⛔ **Never `continue-on-error` on a step whose absence changes what is
published.** The studied system marks its attestation step
`continue-on-error: true`, so provenance is silently absent whenever it fails.

⚠ **`continue-on-error` is acceptable on a step that only reports**, for
example posting a summary comment. The test is whether a consumer could tell
the difference between the step succeeding and the step not running.

---

## 8. Self-hosted runners

⚠ **Needed for architectures GitHub does not host, and they change the threat
model.**

| | hosted | self-hosted |
| --- | --- | --- |
| ⭐ fresh per job | ⭐ yes | ⚠ only if configured ephemeral |
| ⛔ reachable by a fork's pull request | no, without approval | ⛔ **only if you allow it** |
| ⭐ persistence between jobs | ⭐ none | ⚠ a real risk |

⛔ **A self-hosted runner MUST be ephemeral and MUST NOT run `pull_request`
jobs from forks.** A persistent runner that builds untrusted code is a
persistent compromise waiting to happen, and this is the single most common
self-hosted runner mistake.

⭐ **Cross-compilation on hosted runners is preferred over self-hosted
runners** for exactly this reason, and it is why
[`../build/cross-compilation.md`](../build/cross-compilation.md) treats
emulated verification as the answer for architectures with no runner.
