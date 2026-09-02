# testing and validation

The test strategy per layer, the acceptance gate, and the rule that a guard
which has never been seen to fail is not a guard.

Requirements traceability is [`requirements.md`](requirements.md).

---

## 1. ⛔ The rule that shapes everything here

**Plant the defect the guard exists to catch, and read the exit code unpiped.**

⚠ **This is not a style preference.** In `experiments/30-oci-pipeline.sh`, a
check asserting that a tampered digest fails signature verification passed on
its first run while testing nothing: the signature file had never been fetched,
and a `minisign` verify against a missing file also exits non-zero. It was
green, it was trusted, and it was theatre.

⛔ **Every check in this system ships with its negative case.**

---

## 2. The tiers

| tier | proves | speed | runs |
| --- | --- | --- | --- |
| T1 unit | ⭐ one function's behaviour | ms | every commit |
| T2 property | ⭐ an invariant over generated input | s | every commit |
| T3 integration | components against a real registry | ⚠ s to min | every commit |
| T4 acceptance | ⭐ the whole lifecycle end to end | min | every commit |
| T5 conformance | a real registry's actual behaviour | ⚠ min, network | daily |
| T6 reproducibility | ⭐ a rebuild matches, on another machine | ⚠ hours | weekly |

⭐ **T4 exists as `experiments/30-oci-pipeline.sh` today.** T5 exists as
`experiments/40-registry-conformance.sh`. T1 to T3 and T6 are specified here
and not implemented, because there is no implementation to test.

---

## 3. T1: unit

⭐ **The parsers and the grammars, because they are where a wrong answer is
silent.**

| subject | cases that must exist |
| --- | --- |
| version grammar | ⭐ `445.3p3` rejected by check V4; `5.3p3` accepted; `1.0.0-rc.1 < 1.0.0` |
| version comparison | every row of [`format/package-identity.md`](format/package-identity.md) §2.1 |
| name grammar | uppercase rejected; every reserved name rejected |
| ⭐ path validation | ⭐ §6 |
| substitution | ⛔ an unknown `${...}` is an error, not a literal |
| `provides` parsing | `a:b`, `a==b`, `a=>b`, and ⛔ the program-first rule |
| ELF probe | ⭐ already covered: `tools/elfprobe.py` against known-static and known-dynamic inputs |

---

## 4. T2: property

⭐ **Where generated input finds what examples do not.**

| property | generator |
| --- | --- |
| ⭐ parse then serialise is identity | valid recipes |
| ⭐ version comparison is a total order | random version strings |
| ⛔ path validation rejects every escape | ⭐ random paths containing `..`, absolute prefixes, NULs |
| archive normalisation is deterministic | random file trees |
| ⭐ an index round-trips through JSON and SQLite identically | generated catalogues |

⚠ **A total-order test on version comparison catches the class of bug where
`a < b` and `b < a` are both true**, which a hand-written example set almost
never finds.

---

## 5. T3 and T4: integration and acceptance

⭐ **Against a real registry on loopback, never a mock.**

⛔ **A mock registry proves your mock.** The whole reason
`experiments/30-oci-pipeline.sh` starts a real zot is that the defects it found
were in the interaction with a registry: a stale referrers listing, and a media
type storing a path where a basename was expected. Neither would have appeared
against a mock.

⭐ **The acceptance test is the lifecycle**, and it asserts against what came
back out of the registry rather than what went in. 33 assertions, all passing
on the probe host.

### 5.1 The negative cases that must exist

⛔ **Each of these is a test that must FAIL the thing it plants.**

| plant | must |
| --- | --- |
| ⭐ a recipe whose script writes a file | ⛔ validation completes and ⭐ **the file does not exist** |
| a recipe with an image pinned by tag | validation rejects it |
| an artefact path of `../../etc/passwd` | collection refuses |
| ⭐ a build script that exits 0 producing nothing | ⛔ verification fails |
| a dynamically linked artefact | ⭐ V3 fails |
| an artefact for the wrong architecture | V2 fails |
| a tampered digest against a real signature | ⭐ verification fails, ⛔ **and the signature file is proven present first** |
| a payload whose hash differs from the index | install refuses, exit 13 |
| ⭐ a subject with no referrers | ⭐ discovery returns empty, does not crash |

⭐ **The first row is the conformance test for invariant I1**, and it is the
single most important test in the suite. Without it, "the recipe is inert" is a
claim.

---

## 6. Path validation, specifically

⛔ **Its own section because it is the highest-consequence input handling.**

| input | must be rejected |
| --- | --- |
| `/etc/passwd` | absolute |
| `../../../etc/passwd` | traversal |
| `out/../../etc/passwd` | ⭐ traversal after a valid prefix |
| `out/${target}/bin` where `${target}` is `../../etc` | ⛔ ⭐ **traversal after substitution** |
| a path containing a NUL or a newline | control bytes |
| `-rf` | ⭐ begins with a dash |
| a symlink resolving outside the tree | ⛔ ⭐ **checked at collection, not only at declaration** |

⚠ **The fourth and last rows are the ones an implementation gets wrong.** A
pre-substitution check passes a path that escapes after substitution, and a
declaration check passes a path that a build script later replaced with a
symlink.

---

## 7. T5: registry conformance

⭐ **Against the real thing, daily, because a registry's behaviour is not a
constant.**

`experiments/40-registry-conformance.sh` establishes, with controls:

- the base endpoint and its advertised version;
- ⭐ that a digest we compute equals the registry's own
  `Docker-Content-Digest`;
- that the digest resolves as a manifest;
- ⭐ whether the referrers API answers;
- whether a fallback index exists.

⛔ **It refuses to report a verdict unless both controls hold**, because a
referrers 404 on its own equally means the digest was wrong.

⚠ **Running it daily matters**: if GHCR implements the referrers API next
month, this design's fallback is still correct and the client should notice the
API works.

---

## 8. T6: reproducibility

⛔ **On a different runner, on a different day.**
[`build/reproducibility.md`](build/reproducibility.md) §3.

⚠ **Not run in this repository**: one host, one day. `30-oci-pipeline.sh`
rebuilds and compares on the same machine, which demonstrates the timestamp,
path, locale and archive controls and ⛔ **not** the toolchain or dependency
ones.

---

## 9. The gate

⛔ **Three parts, none skippable. Each is blind to what the other two catch.**

### (a) The automated checks, one command

```sh
sh tools/check-links.sh
sh tools/check-consistency.sh
sh tools/count-requirements.sh --check
bash experiments/20-static-matrix.sh
bash experiments/30-oci-pipeline.sh
bash experiments/41-referrers-fallback.sh
bash experiments/50-mirror.sh
```

⛔ **A skipped check is reported as a skip, never as a pass.** A tool that is
not installed means nothing about its subject was verified.

### (b) Drive the real thing

⛔ **For every user-facing change, run the actual system and use it as a user
would.**

⚠ **The class this catches is invisible to a green suite**: a control enforced
on one path and not its siblings, or a component that is tested, documented and
has no reachable caller. You find it by trying to do the thing.

### (c) The deep reviews

⛔ **At least three, each asking a different question**, not one sweep written
up three times.

| lens | question |
| --- | --- |
| 1 the door sweep | ⭐ what other path reaches this code? |
| 2 the guard mutation | ⭐ can my new guard actually fail? |
| 3 the claim audit | ⭐ which sentence am I about to publish that no artefact backs? |

⭐ **A pass reporting nothing was too shallow.** Where one genuinely finds
nothing, the record says what would have had to be true for it to fire.

⚠ **What each pass found here is in
[`history/README.md`](history/README.md).**

---

## 10. What is not tested here

⛔ Stated so nobody reads the green results as broader than they are.

| | why |
| --- | --- |
| ⛔ anything against real GHCR that writes | no namespace, no credentials |
| ⛔ cross-host reproducibility | one machine |
| ⛔ the client | not implemented |
| ⛔ the update bot | not implemented |
| ⛔ non-Linux targets | Linux host only |
| ⚠ ten of the seventeen language files | ⭐ absent toolchains, marked per file |
| ⛔ behaviour at scale | no deployment |

⭐ **Every one has the command that would close it** in
[`open-questions.md`](open-questions.md).
