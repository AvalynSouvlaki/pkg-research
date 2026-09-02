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

⛔ **Five withdrawals, four of them counting or version errors, in one session.**
⭐ That rate is the argument for
[`../conventions.md`](../conventions.md) §4 and for
`tools/count-requirements.sh`, which derives a number rather than repeating one.

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
