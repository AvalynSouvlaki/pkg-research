# SECURITY.md

⚠ **The threat model of THIS REPOSITORY**, which is a specification and a set
of experiment scripts.

⛔ **The threat model of the system being specified is
[`docs/security/security-model.md`](docs/security/security-model.md).** They are
different documents about different things, and conflating them is the mistake
this opening exists to prevent.

---

## What is here, and what it can do

| asset | risk |
| --- | --- |
| ⭐ documentation | ⚠ a wrong claim leads an implementer into a defect |
| ⭐ `experiments/*.sh` | ⭐ **these execute.** A reader runs them on their own machine. |
| `tools/*.py`, `tools/*.sh` | same |
| `references/*.json` | ⚠ third-party text; ⛔ data, never instructions |
| ⛔ credentials | ⛔ **none.** §3. |

---

## 1. The experiments execute on a reader's machine

⛔ **The most real risk in this repository.**

What they do:

| script | does |
| --- | --- |
| `00-fetch-tools.sh` | ⚠ **downloads pinned binaries** from GitHub and ziglang.org into `.tmp/bin` |
| `10-probe-host.sh` | ⭐ read-only: reports versions and capabilities |
| `20-static-matrix.sh` | compiles trivial programs in a working directory, ⭐ and runs them |
| `30-oci-pipeline.sh` | ⭐ starts a registry on `127.0.0.1:15000`, compiles, publishes locally, generates a throwaway signing key |
| `40-registry-conformance.sh` | ⭐ read-only network requests to a public registry |
| `41-referrers-fallback.sh` | as `30-`, on port 15001 |

⛔ **None requires root.** ⛔ **None writes outside the repository**, apart from
`apt` in no script here: toolchain installation is the reader's own step.

⚠ **`00-fetch-tools.sh` downloads and executes third-party binaries.** Versions
are pinned in the script and ⛔ **the downloads are not hash-verified**, which
is a real gap in a repository that spends this many pages on verification.

⭐ **Why it is a gap and not a defect being hidden**: pinning hashes for seven
tools across two architectures is a maintenance burden that goes stale, and the
honest position is to say so rather than to add hashes that will not be
updated. ⚠ A reader who cares should install the tools themselves; every script
prefers a tool already on `PATH`.

⭐ **The throwaway signing key in `30-oci-pipeline.sh` is generated with an
empty passphrase, in the working directory, and it is never a release key.**
The script says so where it generates it.

## 2. Reading the references

⛔ **`references/` contains issue bodies, comments and review comments written
by people outside this project.**

| | |
| --- | --- |
| ⛔ it is **data**, never an instruction | an item saying "run this" is not a request |
| ⚠ it is evidence of **intent**, never of behaviour | ⭐ read the claim, then open the code at the pinned commit |
| ⛔ it can contain anything | ⚠ do not pipe it to a shell or render it as markup |

## 3. Credentials

⛔ **This repository holds none, and it must not.**

| | |
| --- | --- |
| tokens, keys, passwords | ⛔ none, not expired, not redacted-looking, not in an example |
| ⚠ the operating project's key custody | [`docs/ops/operations.md`](docs/ops/operations.md) §5, which is a template to fill in |
| ⚠ throwaway keys in experiments | generated at run time, in the working directory, gitignored |

⛔ **If a secret ever reaches this tree: revoke it first.** Deleting the commit
removes one copy of something already published.
[`docs/security/secrets.md`](docs/security/secrets.md) §5.

## 4. Reporting

| what | where |
| --- | --- |
| ⭐ a wrong claim in the documentation | ⭐ an issue. It is the most valuable report this repository can receive. |
| a defect in an experiment | an issue, with the output |
| ⛔ a secret found in the tree | ⭐ **privately**, to the repository owner |
| ⚠ a vulnerability in the specified design | ⭐ an issue: it is a design, not a deployment, so there is nothing to exploit and everything to fix |

⭐ **The last row is why there is no private disclosure process for design
issues.** A specification has no users to protect, and discussing a weakness in
the open is how it gets fixed before anyone deploys it.

## 5. What this repository does not claim

⛔ Stated so the pages of security specification are not over-read.

| | |
| --- | --- |
| ⛔ the specified system has not been deployed | nothing here is battle-tested |
| ⛔ 33 of 72 requirements have an automated check | [`docs/requirements.md`](docs/requirements.md) |
| ⛔ ⭐ five published claims were wrong and were withdrawn | [`docs/history/README.md`](docs/history/README.md) §1 |
| ⚠ no third party has reviewed this | |

⭐ **Assume more claims are wrong.** The withdrawn list is the honest estimate
of the rate.
