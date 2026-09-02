# AGENTS.md

⭐ **The router.** What to read for which task. It restates nothing that is
written elsewhere, so the two cannot fork. Every link is the authority.

⚠ **This repository is a specification, not a running system.** There is no
application to start and no service to deploy. What it contains is the
documentation an engineering team implements from, the research behind it, and
runnable proofs of the load-bearing mechanisms.

---

## Which job is this?

| the situation | read |
| --- | --- |
| ⭐ you have no context at all | ⭐ [`README.md`](README.md), in order |
| you are implementing this | [`docs/architecture.md`](docs/architecture.md), then the minimum path in `README.md` |
| you are changing a specification | [`docs/conventions.md`](docs/conventions.md) first, ⛔ then the document that owns the fact |
| you are adding or fixing a proof | [`experiments/README.md`](experiments/README.md) |
| you are reviewing this work | [`docs/history/README.md`](docs/history/README.md) §1, the withdrawn claims |
| you are checking a number | ⭐ `experiments/out/`, and the script that wrote it |

---

## The absolutes

⛔ **Seven rules. Each is written once, in full, in the document named.**

| # | rule | lives in |
| --- | --- | --- |
| 1 | ⛔ **Never a fabricated number.** A dash where the value is unknown, and a measurement carries its conditions. | [`docs/conventions.md`](docs/conventions.md) §4 |
| 2 | ⛔ **Every claim is labelled** observed, measured, inferred or recommended. | same §3 |
| 3 | ⛔ **One fact, one home.** Link, do not repeat. | same §5 |
| 4 | ⛔ **A guard that has never been seen to fail is not a guard.** Plant the defect and read the exit code unpiped. | [`docs/testing.md`](docs/testing.md) §1 |
| 5 | ⛔ **Documentation changes in the same commit as the behaviour it describes.** | [`docs/workflows/developer.md`](docs/workflows/developer.md) §8 |
| 6 | ⛔ **A superseded claim is moved, never deleted**, and a withdrawn one gets a row in the front-page list. | [`docs/history/README.md`](docs/history/README.md) |
| 7 | ⛔ **No secret enters the tree**, not expired, not redacted-looking, not in an example. | [`SECURITY.md`](SECURITY.md) |

---

## Before declaring anything green

```sh
sh tools/check-links.sh
sh tools/check-consistency.sh
sh tools/count-requirements.sh --check
bash experiments/30-oci-pipeline.sh
```

⛔ **Read each exit code from the process that produced it.** A check piped into
anything reports the pipeline's status, so a guard that failed reads as green.

⚠ **A skipped check is reported as a skip, never as a pass.** A tool that is not
installed means nothing about its subject was verified.

---

## What is here

| path | what |
| --- | --- |
| [`README.md`](README.md) | ⭐ the single entrypoint |
| [`docs/README.md`](docs/README.md) | the map, one row per file |
| [`docs/architecture.md`](docs/architecture.md) | ⭐ the technical reference. ⛔ It wins conflicts. |
| [`experiments/`](experiments/README.md) | runnable proofs, numbered in the order written |
| [`tools/`](tools/) | the instruments: `elfprobe.py`, `check-links.sh`, `check-consistency.sh`, `count-requirements.sh` |
| [`references/`](references/) | ⭐ the mined trackers of the systems studied, kept so a claim can be re-checked |
| [`CHANGELOG.md`](CHANGELOG.md) | what changed here, newest first |
| [`SECURITY.md`](SECURITY.md) | the threat model of this repository itself |

---

## When you are unsure

⭐ **In order**: what the user said, what the linked document says, what a
script measured, then ask.

⛔ **Never settle a contradiction between two of those by taking the convenient
one.** A contradiction is a finding, and a finding is reported.
