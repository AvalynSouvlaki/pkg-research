# pull-request workflow

What happens between a contributor opening a pull request and a maintainer
merging it, and how a fork's code is built without handing it a secret.

---

## 1. The pipeline

```
open ──► validate ──► build (no secrets) ──► report ──► human review ──► merge
           │              │                                                │
           │ fail         │ fail                                           │
           ▼              ▼                                                ▼
        annotate      publish the log,                              publish, sign,
        file:line     comment once                                  reindex
```

| stage | seconds, ⚠ estimated | needs network |
| --- | ---: | --- |
| validate | ⭐ under 5 | ⭐ no |
| lint | under 10 | no |
| audit changed URLs | ⚠ 10 to 60 | yes |
| build, per host | ⚠ 60 to 3600 | yes |

⚠ **Those durations are estimates, not measurements.** This repository has no
deployment to measure them on. The shape, that validation is free and building
is not, is what the pipeline is ordered around.

---

## 2. Validation, and why it runs on everything

```sh
opk validate            # ⭐ the whole tree, not just the diff
```

⭐ **Cheap enough that a subset is not worth computing**: no network, no
downloads, and a change to one package can invalidate another, for example by
taking a name that now collides.

⚠ **Adopted from era 3's validate workflow, which says the same in a comment.**

| check | fails |
| --- | --- |
| TOML parses | ⛔ yes |
| every required field present and well typed | ⛔ yes |
| ⛔ every unknown key | ⛔ yes |
| ⛔ every build input pinned by digest or hash | ⛔ yes |
| every path passes the path grammar | ⛔ yes |
| the version matches the grammar | ⛔ yes |
| ⛔ every pinned URL has a hash | ⛔ yes |
| name collides with an existing package | ⛔ yes |
| ⚠ name within edit distance 1 of an existing one | ⚠ warns |
| a licence identifier is not valid SPDX | ⛔ yes |

⛔ **Nothing here executes recipe content**, and there is a test that proves it:
[`../testing.md`](../testing.md) plants a recipe whose script would create a
file and asserts the file does not exist after validation.

---

## 3. Auditing the changed files

⛔ **Only what changed, because it costs network.**

| check | on |
| --- | --- |
| ⭐ every pinned URL resolves | changed release files |
| its content hashes to the recorded value | ⭐ changed release files |
| ⭐ every `[artifact]` source path exists in the real archive | changed URL-source packages |

⭐ **The last one is the check static analysis cannot do**, and it is worth the
download: a typo in an install path is invisible until a build, and this catches
it in seconds.

### 3.1 ⚠ Interpreting an HTTP status

⛔ **Only 404 and 410 mean the thing is gone.** A 403 or a timeout means the
check was blocked, which says nothing about the link.

| status | verdict |
| --- | --- |
| 200 | ✅ |
| ⛔ 404, 410 | ❌ fail |
| 403, 429, 5xx, timeout | ⚠ warn: not checked |

⚠ **Escalate rather than assume**, because hosts disagree about what they will
answer: HEAD, then GET, then GET with a browser user-agent, stopping at the
first that answers.

⚠ **This is adopted from era 3's workflow**, which documents the reason: some
hosts refuse HEAD, some refuse curl's own agent, and GitLab refuses a browser
agent it does not believe.

⛔ **Homepages are not checked.** Project sites routinely refuse CI runners, so
checking them produces warnings nobody can act on. Era 2 checked them and had to
make every result a warning, which is a check that has stopped being one.

---

## 4. Building a fork's pull request

⛔ **`pull_request`, never `pull_request_target`.**
[`ci-system.md`](ci-system.md) §2.

| property | |
| --- | --- |
| ⭐ secrets | ⭐ **none** |
| token | read-only |
| ⛔ registry push | ⛔ not possible, and not needed |
| what it proves | ⭐ it builds, verifies and produces a runnable artefact |
| ⚠ first-time contributor | ⭐ a maintainer approves the run, GitHub's default; keep it |

⭐ **The artefact is uploaded as a CI artefact, not pushed to the registry**, so
a reviewer can download and try it without anything being published.

⚠ **A build that succeeds on a pull request is not the build that gets
published.** The published one runs after merge, from the merge commit. They
should agree and the reproducibility job is what eventually says whether they
do.

---

## 5. Reporting

⛔ **Failures are reported where a contributor will see them, once.**

| mechanism | for |
| --- | --- |
| ⭐ annotations at file and line | ⭐ validation and lint |
| the job summary | the per-host result table |
| ⭐ one comment, updated in place | ⭐ the overall status |
| a check run | the merge gate |

⛔ **One comment, edited on each run.** A bot that adds a comment per push
produces a thread nobody reads, and it buries the human discussion.

```markdown
### opk build

| host | result | log |
|---|---|---|
| x86_64-linux | ✅ 5.0 MiB, static | [log](...) |
| aarch64-linux | ✅ 4.9 MiB, static | [log](...) |
| riscv64-linux | ❌ link error | [log](...) |

<details><summary>riscv64-linux, last 20 lines</summary>

```
error: linking with `cc` failed: exit status: 1
  = note: /usr/bin/ld: cannot find -lz
```
</details>

`riscv64-linux` needs `zlib-static` in `[build].deps`.
```

⭐ **Naming the likely fix is worth more than the log link.** A contributor who
has to read 4,000 lines to find "add a dependency" often does not.

---

## 6. Commands on a pull request

⚠ **Supported, and narrowly.**

| command | who | permissions the job needs |
| --- | --- | --- |
| `/rebuild [host]` | ⭐ anyone with write | `contents: read` |
| `/lint` | anyone with write | ⭐ `contents: read` |
| ⚠ `/build-and-publish` | a maintainer | ⛔ the full publish set |

⛔ **The command is parsed by a real parser and never interpolated into a
shell.** [`../security/secrets.md`](../security/secrets.md) §4.1.

⛔ **Each command's job requests only the permissions it needs.** Era 2's PR bot
gave one job `contents: write`, `packages: write`, `id-token: write` and
`actions: write` for every command including `/help`.

⚠ **`author_association` is a weak gate on its own.** It is checked, and it is
not the only control: the narrow permission set is what bounds the damage if it
is wrong.

---

## 7. Merge

| gate | required |
| --- | --- |
| validation | ⛔ yes |
| build on every declared host | ⛔ yes |
| ⚠ a build failing on one host | ⛔ blocks, unless the host is removed from the recipe with a note |
| human approval | ⛔ yes |
| ⭐ a second approval for a new package | ⭐ recommended |

⛔ **Merging is not automatic, ever, including for the update bot.** The bot's
pull requests are small, and small is what makes review fast rather than what
makes it unnecessary.

⚠ **A merge queue is worth having above a few merges a day**, and it interacts
with the concurrency rule: the per-commit group in
[`ci-system.md`](ci-system.md) §3 exists so a queue draining several package
pull requests does not cancel the intermediate builds.

---

## 8. After merge

```
merge ──► build-publish ──► sign ──► index
```

⛔ **The published artefact is built from the merge commit**, not promoted from
the pull-request run. A promoted artefact was built from code that was never on
the main branch.

⚠ **That means the work is done twice**, and it is the right trade: the
pull-request build proves the change works, the publish build produces what
ships, and the reproducibility job later confirms they agree.
