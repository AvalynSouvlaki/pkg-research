# secrets

Every credential this system uses, who holds it, what it can do, and how logs
are kept clean.

---

## 1. The inventory

⛔ **If it is not in this table, it does not exist.** A credential nobody
inventoried is a credential nobody rotates.

| # | secret | held by | grants | lifetime |
| --- | --- | --- | --- | --- |
| S1 | ⛔ the package signing key | ⭐ offline or hardware-backed; the signing workflow only | signing package digests | years, rotated per [`trust-and-verification.md`](trust-and-verification.md) §4.2 |
| S2 | ⛔ the index signing key | ⭐ separate from S1 | signing the catalogue | years |
| S3 | the registry push credential | the publishing workflow | pushing to the org's packages | ⭐ ephemeral: the run's `GITHUB_TOKEN` |
| S4 | the bot's repository token | the update workflow | opening pull requests | ephemeral, or a scoped app token |
| S5 | ⚠ a forge read token | the update workflow | raising API rate limits | ephemeral |
| S6 | ⚠ a package deletion token | ⭐ the retention workflow only | deleting package versions | ephemeral, and see §4 |
| S7 | a mirror's write credential | the mirror agent | pushing to the mirror | rotated per its host's policy |

⛔ **The build container holds none of these.** Not one.
[`../build/build-system.md`](../build/build-system.md) §3.1.

⚠ **The studied system's era 1 passed `GITHUB_TOKEN`, `GITLAB_TOKEN` and
`HF_TOKEN` into every package's build script**, documented as available inside
`x_exec.run`. Any package could read them. This design fetches outside the
container and passes nothing in, which is why `[source]` and `[[tool]]` are
declarative fields rather than things a script does.

---

## 2. Custody rules

⛔ **Six rules. Each has a failure behind it somewhere.**

1. **A secret never enters the tree.** Not a recipe, not a workflow file, not
   a test fixture, not an example. Not expired, not redacted-looking.
2. **A secret never enters a log**, and §3 is what enforces that when rule 1
   holds and something prints one anyway.
3. ⛔ **The signing key is not held by the workflow that builds.**
   [`security-model.md`](security-model.md) §4.
4. **The narrowest scope that works.** A token that can push packages does not
   need to delete them.
5. ⛔ **Ephemeral over long-lived.** In GitHub Actions the run's own token
   expires with the run; a personal access token does not.
6. **Every secret has a named owner and a rotation date**, recorded in
   [`../ops/operations.md`](../ops/operations.md).

---

## 3. Keeping logs clean

⛔ **A build log is published.** [`../ci/build-logs.md`](../ci/build-logs.md).
So log hygiene is not a convenience.

### 3.1 The layers

| layer | catches |
| --- | --- |
| 1 | ⭐ **there is no secret in the container** | ⭐ the strongest control by far |
| 2 | the CI platform masks registered secrets | values it knows about |
| 3 | ⭐ the publisher scrubs before publishing | anything the first two missed |
| 4 | ⚠ a review of the scrubber's own findings | a scrub that fired is a signal something leaked |

⭐ **Layer 1 is why this works.** Scrubbing is a backstop, and a system relying
on scrubbing alone is one regular expression away from publishing a token.

### 3.2 ⛔ How not to scrub

The studied system's era-2 build workflow scrubs with:

```sh
sed -i -E '/(ghp_|github_pat|token|secret|access_key)/Id' build.log
```

Three defects:

| | |
| --- | --- |
| ⛔ it deletes whole **lines** | a compiler error on the same line as the word "token" is destroyed, so the log loses the information it exists for |
| ⛔ it matches **words**, not **values** | a token embedded in a URL with none of those words beside it survives |
| ⚠ `token` and `secret` are common English words | it fires constantly on innocent output, training everyone to ignore it |

### 3.3 ⭐ How to scrub

**Redact the value, keep the line:**

```sh
python3 - build.log <<'PY'
import re, sys, os
patterns = [
    (re.compile(r'gh[pousr]_[A-Za-z0-9]{36,}'),           'github-token'),
    (re.compile(r'github_pat_[A-Za-z0-9_]{80,}'),          'github-pat'),
    (re.compile(r'glpat-[A-Za-z0-9_-]{20,}'),              'gitlab-token'),
    (re.compile(r'AKIA[0-9A-Z]{16}'),                      'aws-key-id'),
    (re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'),    'private-key'),
    (re.compile(r'(?i)(authorization:\s*(?:bearer|basic)\s+)\S+'), 'auth-header'),
    (re.compile(r'://[^/\s:@]+:[^/\s@]+@'),                'url-credential'),
]
path = sys.argv[1]
text = open(path, encoding='utf-8', errors='replace').read()
hits = 0
for rx, label in patterns:
    text, n = rx.subn(f'[REDACTED:{label}]', text)
    hits += n
open(path, 'w', encoding='utf-8').write(text)
# ⛔ Report, so a scrub that fired is visible rather than silent.
print(f'::warning::log scrubber redacted {hits} value(s)' if hits else 'log scrubber: clean')
sys.exit(0)
PY
```

| property | |
| --- | --- |
| ⭐ redacts the value, keeps the line | the log stays useful |
| ⭐ matches credential **shapes** | a token in a URL is caught |
| ⭐ reports a count | ⛔ a scrub that fired means layer 1 failed and someone must find out why |
| ⚠ it is a backstop | ⛔ never the primary control |

⛔ **A non-zero redaction count is an incident, not a success.** Something put a
credential where it could be printed.

---

## 4. Least privilege in CI

```yaml
permissions:
  contents: read          # ⛔ the default for every job

jobs:
  build:
    permissions:
      contents: read      # ⭐ nothing else: the build needs nothing else
  publish:
    permissions:
      contents: read
      packages: write     # ⭐ only this job pushes
      id-token: write     # only for Sigstore
  update-bot:
    permissions:
      contents: write
      pull-requests: write
```

⛔ **Top-level `permissions` is set explicitly**, not inherited. A workflow with
no `permissions` block gets whatever the repository default is, which is often
write to everything.

⛔ **`delete:packages` (S6) is never in a workflow that also builds or
publishes.** A publish workflow that can also delete is one bug away from
deleting what it just published.
[`../registry/retention.md`](../registry/retention.md) §6.

### 4.1 ⛔ `issue_comment` and `pull_request_target`

⚠ **The two triggers that turn a repository into a foothold**, because they run
with the base repository's permissions and secrets.

⛔ **Never interpolate untrusted text into a shell.**

```yaml
# ⛔ WRONG. A comment body containing $(...) or backticks executes.
run: |
  COMMENT="${{ github.event.comment.body }}"
```

```yaml
# ⭐ RIGHT. The value reaches the shell as data through the environment.
env:
  COMMENT: ${{ github.event.comment.body }}
run: |
  printf '%s' "$COMMENT" | head -1
```

⚠ **The studied system's era-2 `pr-bot.yaml` does the first**, at line 42 of
that file, in a job holding `contents: write`, `packages: write`,
`id-token: write` and `actions: write`. It is gated to
`author_association` in OWNER, MEMBER or COLLABORATOR, which reduces the
exposure and does not remove it: a collaborator with triage rights, or a
compromised collaborator account, reaches a shell with those permissions.

⭐ **Two rules together**: interpolate through the environment, never into the
script body; and give a comment-triggered job the narrowest permission set that
lets it do its job, which for a `/lint` command is `contents: read`.

---

## 5. What to do when a secret leaks

⛔ **In this order. Deletion is not first.**

| # | step | why |
| --- | --- | --- |
| 1 | ⭐ **revoke it** | ⭐ the only step that actually helps. Everything else is cleanup. |
| 2 | issue a replacement, update the workflow | restore service |
| 3 | ⚠ assess what it could reach while valid | scope the incident |
| 4 | remove it from the log or artefact | ⚠ one copy of many |
| 5 | if it reached the tree, rewrite history | ⚠ still one copy of many |
| 6 | record it in the changelog and the incident log | so the process improves |
| 7 | fix the layer-1 failure that allowed it | ⛔ otherwise it recurs |

⚠ **Steps 4 and 5 feel like the fix and are not.** A published log has been
fetched, mirrored, and cached. Revocation is what closes the exposure;
deletion reduces the number of copies of something already compromised.
