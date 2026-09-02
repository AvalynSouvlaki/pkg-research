# update automation

How a new upstream version becomes a reviewed pull request, and why the bot
opens one rather than merging it.

---

## 1. Why automate this, with the number

⭐ **Measured from the studied system: 615 of 824 pull requests, 74.6%, were
opened by `github-actions[bot]`.** Counted from
`references/pkgforge__soarpkgs/api/issues.json`.

⚠ **Version bumps at that volume are not human work**, and a system that
requires them to be will fall behind and then be abandoned. The 385 disabled
recipes out of 871 in era 1 are what falling behind looks like.

⛔ **The bot opens a pull request. It does not merge one.** The diff is small,
literal and reviewable precisely because the recipe is inert, and that is what
makes automation safe here rather than merely fast.

---

## 2. The cycle

```
schedule (daily)
   │
   ├─ for each package with [update].strategy != "static"
   │     query the strategy's source
   │     ⛔ validate the discovered version against the grammar
   │     ⛔ check it is greater than the current version
   │     skip if in [update].ignore
   │
   ├─ for each update found
   │     resolve the artefact URL per [source]
   │     ⭐ fetch and hash it
   │     write the release file
   │
   ├─ validate the whole tree offline
   └─ open ONE pull request with every change
```

⭐ **One pull request for all updates, not one per package.** Era 2 opened one
per package; era 3 batched them. Batching is better: one review, one CI run, one
merge, and the diff is still small per package. A package whose update is
contentious is split out by hand.

⚠ **The trade is that one bad update blocks the batch.** The bot supports
`--split NAME` to re-open a single package separately, and the reviewer uses it
rather than the bot guessing.

---

## 3. Strategies

⛔ **A closed set.** Adding one changes the bot, not a recipe.

| strategy | reads | rate cost |
| --- | --- | --- |
| `github-releases` | the releases API | 1 request |
| `github-tags` | the tags API | 1 request |
| `gitlab-tags` | the tags API | 1 request |
| `git-tags` | ⭐ `git ls-remote --tags`, ⭐ no API token | 1 connection |
| `html-regex` | a page, matched against a pattern | 1 request |
| `static` | nothing | ⭐ 0 |

⭐ **`git-tags` uses no API quota**, which matters at scale.
[`../ops/rate-limits.md`](../ops/rate-limits.md).

### 3.1 ⚠ `html-regex`, the one that breaks

It matches a pattern against a page whose author owes you nothing.

| control | value |
| --- | --- |
| ⛔ regular expression time limit | 2 s, ⭐ enforced with a timeout, not by hoping |
| ⛔ input size limit | 1 MiB; the fetch stops there |
| ⛔ exactly one capture group | a pattern with none or several is rejected by the validator |
| ⚠ a recipe using it SHOULD carry a `note` | naming what to check when it stops working |

⚠ **A pathological regular expression against a large page is a denial of
service against your own bot.** The timeout is not defensive theatre; it is the
control.

---

## 4. ⛔ Validating a discovered version

**The countermeasure to the corruption this design was shaped by.**

The live public index of the studied system records `bash` at version
`445.3p3` where upstream calls it `5.3p3`, because a `jq` expression emitted
several matches and `tr -d '[:space:]'` concatenated them. Observed 2026-09-02.

⛔ **Every discovered version passes all of these before it is used
anywhere:**

| # | check | catches |
| --- | --- | --- |
| 1 | matches the version grammar | ⭐ arbitrary junk |
| 2 | length 1 to 64 | ⭐ a pipeline that concatenated its whole output |
| 3 | at most 6 release components | the same, subtler |
| 4 | no component exceeds 9 digits | ⭐ `445.3p3`: a prefix glued on |
| 5 | ⭐ **greater than the current version** | ⭐ a resolver returning something older or corrupt |
| 6 | not in `[update].ignore` | known-bad releases |
| 7 | ⚠ not more than 2 major versions ahead | a strategy that matched an unrelated tag |

⛔ **Check 5 is the one that catches the observed defect.** `445.3p3` parses;
compared against the previous `5.3p3` it is greater, so check 5 passes and check
4 is what fires. Both are needed.

⚠ **Check 7 has false positives** for projects that genuinely jump versions. It
warns and asks rather than refusing, and the pull request says so.

⛔ **A version failing any check produces an alert and no pull request.** It
never produces a pull request with a note saying the version looks odd, because
that is a pull request somebody merges at four in the afternoon.

---

## 5. Hashing

```
resolve [source].url with the new version
⭐ fetch it
compute sha256 and blake3
record url, both hashes and the size in the release file
```

⭐ **Prefer a digest the forge itself reports, and cross-check.** GitHub's
release asset API returns a digest for many assets; where it does, the bot
compares it against what it computed and ⛔ fails on a mismatch rather than
preferring either.

⛔ **A pinned URL with no hash must never reach a commit.** The workflow order
is resolve, then hash, then validate, then commit, and validation refuses a
release file with a missing hash.

⚠ **This ordering is adopted directly from the studied system's era-3 update
workflow**, which states the reason in a comment: forges that report no digest
leave a pinned URL with no hash, and that state must not be committed.

---

## 6. The pull request

⭐ **Its body is the review aid.**

```markdown
## Package updates

| package | from | to | hash |
|---|---|---|---|
| ripgrep | 14.1.0-1 | 14.1.1 | new |
| fd | 9.0.0-1 | 9.0.0-1 | ⚠ CHANGED for an UNCHANGED version |

### ⚠ Review these first

**fd**: the artefact hash changed but the version did not. Upstream replaced
a published artefact in place. Investigate before merging.

  before  b3:9f8e7d6c...
  after   b3:1a2b3c4d...
  url     https://github.com/sharkdp/fd/releases/download/v9.0.0/fd-...

### Checklist
- [ ] versions look right
- [ ] no unexpected hash change on an unchanged version
- [ ] build passes on every declared host
```

⭐ **Surfacing "changed hash, unchanged version" is the single most valuable
thing this bot does.** It is direct evidence of an artefact replaced in place,
it costs nothing to compute, and no human would notice it in a diff of forty
packages.

⚠ **Adopted from era 3's update workflow**, whose pull-request body says the
same thing in prose. This design makes it a computed, highlighted row rather
than a standing instruction, because a standing instruction is read once.

### 6.1 ⛔ Editing the files

⛔ **The bot parses and re-serialises TOML with a real parser.** It never edits
with `sed`.

⚠ **The studied system's era-2 bot used `sed -i` on YAML**, plus roughly fifty
lines of `grep` and `sed` reimplementing a YAML parser to extract a description
for the pull-request body, at
`.github/workflows/update-checker.yaml` lines 155 to 205. The two-file split in
this design removes the need entirely: the bot writes a small generated file
and never touches the human-written recipe.

---

## 7. Idempotency and rate

| control | |
| --- | --- |
| ⭐ a fixed branch name, `automated/package-updates` | a re-run updates the existing pull request |
| ⛔ check for an open pull request before opening one | |
| ⛔ check the branch exists remotely | ⚠ a pull request can be closed with the branch alive |
| ⭐ `concurrency: group: update, cancel-in-progress: false` | one run at a time |
| a per-run budget on API requests | [`../ops/rate-limits.md`](../ops/rate-limits.md) |
| ⚠ back off on 429, honouring `Retry-After` | ⛔ never a fixed sleep |

⚠ **Era 2 used `sleep 2` between pull requests as its rate control.** It works
until it does not, and it does not adapt when the limit tightens. Honouring
`Retry-After` and tracking the remaining budget from the response headers is
the mechanism that scales.

---

## 8. Rolling packages

A package tracking a branch rather than a release has no version to compare.

| property | |
| --- | --- |
| identified by | ⭐ `[update].strategy = "git-commit"` with a branch |
| version | `HEAD-<short>-<YYYYMMDDTHHMMSS>`, derived from the commit |
| rebuild when | ⭐ the commit changed |
| cadence | ⚠ its own schedule, not the daily one |

⚠ **Era 2 identified rolling packages by a grep heuristic**: no top-level
`pkgver`, but an indented one. That is a guess about file shape rather than a
declaration, and it misfires on a comment. ⭐ **This design declares it.**

⛔ **A rolling package's version must still pass the grammar**, and the derived
form is constructed by the bot rather than parsed out of upstream, so it cannot
be corrupted by a bad pipeline.
