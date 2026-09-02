# history

⭐ **What was believed here and why that changed.** Superseded wording, reversed
decisions, dead ends, and ⛔ **the claims this repository has published and
later withdrawn.**

⛔ **This is not the work order and it is not the changelog.** Every other
document says what is true now; this says what was believed and why that
changed.

⛔ **Append, never edit.** A premise a later measurement disproves keeps its
wording, and the correction is written underneath it. A silently corrected
document teaches nobody, and the reader who needs this directory is the one
about to make the same mistake.

---

## 1. ⛔ Claims published here and later withdrawn

⭐ **Read this list before trusting any number in this tree.**

| # | published | withdrawn | correct | how it was caught |
| --- | --- | --- | --- | --- |
| W1 | "the studied system used UPX on **133** recipes" | 2026-09-02 | ⭐ **29** | ⭐ the claim audit: 133 was `grep -o` token occurrences, 29 is `grep -l` files |
| W2 | "gfortran, gnatmake and gdc **13.2.0**" | 2026-09-02 | ⭐ **13.3.0** | the same pass: the versions were never read, only assumed |
| W3 | "**67** requirements, **20** checked, **45** unchecked" | 2026-09-02 | ⭐ **72, 33, 35** | ⭐ counted rather than estimated, after writing the table from memory |
| W4 | "**six** of seventeen language ecosystems measured" | 2026-09-02 | ⭐ **seven files** | the same sentence listed seven items |
| W5 | ⛔ "`file` calls a static-pie binary dynamically linked" | 2026-09-02 | ⭐ `file` 5.45 correctly says "static-pie linked" | ⭐ running `file` against the four cases instead of asserting from memory |
| W6 | "⛔ 33 of 72 requirements have an automated check", in `SECURITY.md` and `lessons.md` | 2026-09-02 | ⭐ **36 of 75** | ⭐ `count-requirements.sh --check` extended past its own defining document, in pass 4 |
| W7 | ⛔ `check-consistency.sh` reporting a clean section-reference check | 2026-09-02 | ⭐ it had examined **zero** citations | ⭐ the guard-mutation test: a planted `§99` did not fail it |

⛔ **Seven withdrawals, five of them counting or version errors, in one
session.** ⭐ That rate is the argument for
[`../conventions.md`](../conventions.md) §4 and for
`tools/count-requirements.sh`, which derives a number rather than repeating one.

⚠ **W3 and W6 are the same defect twice.** The first time, a coverage table was
written from memory. The second time it was derived correctly and two *copies*
of it in other documents were not, because the guard only ever checked the
document it lived in. ⛔ **A derived number is only as good as the set of places
the derivation checks**, which is now the whole tree.

⚠ **Assume more remain.**

### W5 in full, because it is the instructive one

The original wording in `tools/elfprobe.py` read:

> `file` reports "statically linked" from a heuristic, and has been observed to
> call a static-pie binary "dynamically linked" because it carries a
> PT_DYNAMIC segment with no PT_INTERP.

⭐ **It was written from memory and it is wrong.** Measured on the probe host,
`file` 5.45 reports:

| binary | `file` says |
| --- | --- |
| `gcc -O2 t.c` | "dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2" |
| `gcc -static` | "statically linked" |
| `musl-gcc -static` | "statically linked" |
| ⭐ `gcc -static-pie` | ⭐ **"static-pie linked"** |

⭐ **The real argument survived and got better.** `file` is not wrong; it prints
prose meant for a human, and the *string differs between the two static cases*,
so a check grepping for "statically linked" silently rejects a static-pie
binary. The corrected wording says that, and it is a stronger reason to read the
field than the false one it replaced.

---

## 2. Superseded wording

⛔ **Kept verbatim, with what replaced it.**

### 2.1 The `eget` survival rate

**Published in an early reading of the era-1 data:**

> `eget` at 100% disabled is the worst-performing strategy in the corpus.

⛔ **Withdrawn.** Those 267 files were added in the repository's first commit,
`1ac9fd23` "takeoff" on 2025-01-10, which added 6,406 files at once. They are a
bulk import from a previous generation and were never enabled. ⭐ Reporting them
as a 100% failure rate treats dead weight as failed builds.

⭐ **What replaced it**:
[`references/README.md`](references/README.md) section 5 reports the row and
annotates it, and the "all" figure of 44.0% is stated with the caveat rather
than without.

⚠ **The lesson generalises**: a rate needs its denominator interrogated, not
just computed.

### 2.2 The retention document's location

**Published**: a retention page under the ops directory, linked from three
documents.

⛔ **Withdrawn.** Retention is a registry concern and the document that owns it
is [`../registry/retention.md`](../registry/retention.md). Having a second path meant two homes for one
fact. The links were repointed and the `ops/` entry removed.

---

## 3. Dead ends

⭐ **What was tried and did not work, so nobody spends it again.**

### 3.1 `gdc` static against glibc

⛔ **Does not link.** Measured:

```
libgphobos.a(elf.o): undefined reference to `__tls_get_addr'
```

`libgphobos` resolves thread-local storage through the dynamic loader's
`__tls_get_addr`, which a fully static link does not provide.

⭐ **Kept as a committed negative result** in
`experiments/20-static-matrix.sh`, as an expected-failure row that does not
fail the experiment. ⭐ The recommendation for D is LDC against musl, and
[`../build/languages/d.md`](../build/languages/d.md) records why the obvious
recipe is not the recommended one.

### 3.2 Probing a container runtime with `--version`

⚠ **Tried first, and it was wrong.** `docker --version` answered happily on the
probe host and every real command failed, because there was no daemon.

⭐ **What replaced it**: `experiments/10-probe-host.sh` probes `docker info` and
`podman info`, and reported `docker_daemon UNAVAILABLE` beside a working
podman 4.9.3.

---

## 4. Review passes

⛔ **Each pass says what it swept that the others did not.** A pass reporting
nothing was too shallow.

### Pass 1: the guard mutation, 2026-09-02

**Question**: can each new guard actually fail?

| swept | found |
| --- | --- |
| `tools/elfprobe.py --expect-static` | ⭐ **passes**: exit 1 on a planted dynamic binary, 0 on three static ones |
| ⛔ the signature check in `30-oci-pipeline.sh` | ⛔ **THEATRE.** It passed while testing nothing: the referrers listing was captured before the signature was attached, so the signature file was never fetched, and a `minisign` verify against a *missing* file also exits non-zero. |
| `tools/count-requirements.sh --check` | ⭐ **passes**: exit 1 on a planted wrong count |

⭐ **The fix**: assert the signature artefact is present before making any claim
about the guard, and re-read the referrers listing after every attach.

⭐ **This is the single most valuable finding of the whole session**, because
the check had already been reported as passing.

### Pass 2: the claim audit, 2026-09-02

**Question**: which sentence about to be published is not backed by an artefact
that can be pointed at?

| swept | found |
| --- | --- |
| every number in `static-linking.md` | ⛔ W1: 133 against 29 |
| the conditions line under the measured table | ⛔ W2: 13.2.0 against 13.3.0 |
| ⛔ the `file` claim in `elfprobe.py`'s docstring | ⛔ W5: the claim was false and the argument survived |
| the two OCI empty-config digests | ⭐ **verified correct** against the spec and against `sha256sum` |
| the 62 MB to 318 KB index ratio | ⭐ **verified** against the file sizes |
| the coverage table in `requirements.md` | ⛔ W3: all three numbers wrong |
| the ecosystem count in `languages/README.md` | ⛔ W4 |

### Pass 3: the door sweep, 2026-09-02

**Question**: what other path reaches this?

| swept | found |
| --- | --- |
| every `oras` call site in `30-oci-pipeline.sh` | ⛔ the plain-HTTP flag was needed at ten sites; ⭐ made one variable so a real deployment flips it once |
| every experiment's tool resolution | ⛔ three did not find `.tmp/bin`, so zig read as ABSENT; ⭐ fixed, and `00-fetch-tools.sh` added so a fresh clone can run them |
| ⭐ referrer discovery paths | ⛔ the API path worked locally and would fail on GHCR; ⭐ `41-referrers-fallback.sh` added, running discovery with the API disabled |
| ⭐ `image.title` on attached files | ⛔ the puller recreated the staging subdirectory, so a build log could not be retrieved by name |
| every link in the tree | ⭐ `tools/check-links.sh` added; ⛔ it found the `ops/retention.md` double home |

⚠ **What pass 3 did not look at**: the documents' prose for internal
contradiction between two files that do not link to each other. `check-links.sh`
cannot see that, and no pass here swept for it.

### Pass 4: the declarer-and-user sweep, 2026-09-02

**Question**: the gap pass 3 left. Where does one document use a thing that
another document is supposed to declare, and the two disagree?

⭐ **This is the pass that produced `tools/check-consistency.sh`.** Every finding
below was found by hand first, and each one became a check so the class stays
closed.

| swept | found |
| --- | --- |
| ⭐ every `application/vnd.opk.*` string against `registry/media-types.md`, which states it is the only place they are written | ⛔ **two were not in it**: `catalog-db.v1` from `index-and-search.md` and `debuginfo.v1` from `static-linking.md`. Both are real artefacts; the registry was incomplete. |
| ⭐ every `opk` verb against `client/cli.md`, whose first line claims the command surface can be built from it alone | ⛔ **four verbs used and undeclared**: `config`, `debug`, `migrate`, `run`; and `completions` and `env` appeared only in a §7 example, not in the command tables |
| every `§N` citation against the target's headings | ⛔ **one dangling**: a reference to `migration.md` §6, which has five sections |
| ⭐ the `R<n>` identifier namespace | ⛔ **a collision**: `reproducibility.md` used `R1`..`R15` for sources of nondeterminism while `requirements.md` uses `R<n>.<n>` for requirements. Renamed to `D1`..`D15`. |
| ⭐ every copy of the requirement counts | ⛔ **W6**: the defining table was regenerated and two other documents were not |
| ⛔ the new checker against a planted defect, one per class | ⛔ **W7**: the section check had never run. It resolved each link's *label* instead of its *target*, matched nothing across 95 documents, and reported success. |

⭐ **W7 is the finding worth carrying forward.** A checker that reports zero
failures and a checker that examined zero claims print the same thing. ⛔ Every
check in `check-consistency.sh` now prints its denominator and exits 1 when that
denominator is zero, which is the only difference between the two states that a
reader can see.

⚠ **What pass 4 could not close**: two documents that describe the same
*behaviour* in different words. There is no declaring file to check against, so
it stays a reading. Pass 5 is that reading.

### Pass 5: the behaviour reading, 2026-09-02

**Question**: where do two documents describe the same behaviour differently,
in words no checker can compare?

| swept | found |
| --- | --- |
| trust policy names and the default | ⭐ **agree** across nine documents: `strict`, `default`, `hash-only`, `unverified` |
| the registry namespace and tag shape | ⭐ **agree**; the worked example matches the rule |
| the two hashes and their prefixes | ⭐ agree in the documents; ⛔ **and not proven anywhere**, see below |
| ⛔ `max-index-age` | ⛔ **contradiction**: the *warning* threshold in `index-and-search.md`, the *refusal* threshold in `offline-and-airgap.md`, and the offline table implied a second, earlier "stale" tier that was never given a value |
| the exit code for a stale index | ⛔ **wrong in the fix as first written**: staleness is a freshness failure, which the table numbers **11**, not the 10 used for an absent index |
| ⭐ every `opk` flag against the CLI specification | ⛔ **ten flags used and undeclared**, among them `--download-only`, `--pin-cache`, `--allow-epoch-change` and `--allow-stale-index` |
| ⛔ **the hash the client verifies** | ⛔ **no experiment computed one.** See below. |

⛔ **The BLAKE3 gap is the finding of this pass.**
[`../decisions/0006-two-hashes.md`](../decisions/0006-two-hashes.md) says BLAKE3
is what the client verifies and SHA-256 is what a registry independently
reports. Every experiment checked SHA-256, which is the registry's hash. The
PoC's `metadata.json` had no `blake3` field at all, and wrote its `sha256` as
bare hex where [`../format/metadata-schema.md`](../format/metadata-schema.md)
specifies a `sha256:` prefix, so the document the pipeline produced did not
conform to the schema the pipeline claimed to demonstrate.

⭐ **Closed rather than noted.** `b3sum` 1.8.7 is now pinned in
`experiments/00-fetch-tools.sh` and validated against the two published BLAKE3
test vectors; the pipeline computes the hash, writes both values with their
prefixes, verifies BLAKE3 against the artefact **pulled back out of the
registry**, and asserts that appending one byte changes it. 30 assertions
became 33.

⚠ **Why four passes missed it.** Every earlier pass asked whether a claim was
*supported*. This one asked which claims had *no experiment at all* behind
them, which is a different question: an unproven claim and a proven one read
identically on the page.

⚠ **A limit of the new checker, stated because it looks stronger than it is.**
The section-reference check proves a cited `§N` **exists**, not that it is the
right section. Two citations in this pass pointed at a real section that was
the wrong one, and only reading caught them.

### Pass 6: the checkers themselves, 2026-09-02

**Question**: the checks now carry the review. ⛔ **What are the checks not
looking at, and what did they quietly exclude?**

| swept | found |
| --- | --- |
| ⛔ what the file walk excludes | ⛔ **a document was invisible to every check.** Both checkers pruned any directory named `references`, meaning to skip the mined corpus at the repository root. It also pruned `docs/history/references/`, a 16 KB authored page in this tree. Pruning is by path now, and the first run over the restored file found a broken citation in it. |
| ⭐ the reachability rule | ⛔ **it tested the weaker property.** "A page nothing links to" is satisfied by two orphan pages that link to each other. The deliverable's contract is that an implementer reads `README.md` and follows its links, so the check now walks that graph from `README.md`. Guard-mutation tested with exactly that orphan pair. |
| ⛔ the evidence files themselves | ⛔ **three were corrupt.** Each experiment `tee`s its own `out/*.txt`; re-running one with a shell redirect to that path gives the file two writers, and the result is correct output followed by a block of NUL bytes. Every check still passed, because nothing read past the counts. |

⭐ **The pattern across passes 4, 5 and 6 is one thing.** Every defect was a
check that reported success over something it was not looking at: a section
check that matched no citations, a count check that read one document of three,
a file walk that skipped a page, a reachability rule that tested a weaker
property, and evidence files nothing read to the end. ⛔ **A green check is a
claim about coverage, and coverage is the part that was never stated.** That is
why every check in `tools/check-consistency.sh` now prints its denominator.

⚠ **What pass 6 did not do**: run the experiments on a second host. Every
number in this tree is still one machine on one day, and
[`../open-questions.md`](../open-questions.md) Q5 carries the job that would
change that.

---

## 5. What is NOT here

| | why |
| --- | --- |
| ⛔ the current answer to anything | it belongs in the page that answers that question |
| ⛔ the work order | ⚠ there is none; this is a specification |
| what shipped and when | `CHANGELOG.md` |
| ⛔ a rule anybody still follows | if it is live, it is not history |

---

## 6. How to add an entry

```
1. ⛔ do not edit the original wording. Quote it.
2. state what replaced it, and the measurement or reasoning that did
3. ⭐ if it was a published claim, add a row to §1
4. say how it was caught, because that is what improves the process
```

⭐ **§1 is the front-page list on purpose.** A reader who trusts this tree
without checking that list trusts sentences that are wrong.
