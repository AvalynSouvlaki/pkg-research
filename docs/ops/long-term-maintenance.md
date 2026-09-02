# long-term maintenance

Schema evolution, deprecation, key custody, and handing the project to whoever
comes next.

⭐ **Written on the assumption that the people who build this will not be the
people who run it in five years.**

---

## 1. What must survive

⛔ **Two things whose loss is not repairable by recomputation.**

| | recoverable | why |
| --- | --- | --- |
| ⭐ the package tree in git | ⛔ **no** | it is the source; everything else derives from it |
| ⭐ the signing keys | ⛔ **no** | rotation is possible; the old signatures are not |
| the index | ⭐ yes | regenerate |
| published artefacts | ⭐ yes | rebuild from the tree |
| ⚠ base images | ⛔ **no, if upstream deletes them** | §4 |
| ⚠ upstream sources | ⛔ **no, if upstream deletes them** | §4 |

⭐ **Everything else is derived**, which is what makes this system recoverable
from a git repository and a key.

---

## 2. Key custody

⛔ **A key with one holder is one accident from an unmaintainable project.**

| rule | |
| --- | --- |
| ⭐ at least two people can sign | ⛔ or the project stops when one is unavailable |
| ⭐ the key is backed up offline, in two places | |
| ⚠ the backup is tested | ⭐ an untested backup is a belief, not a backup |
| ⛔ rotation is scheduled, not reactive | [`../security/trust-and-verification.md`](../security/trust-and-verification.md) §4.2 |
| ⛔ offboarding rotates, not just revokes | [`operations.md`](operations.md) §8 |
| ⭐ the successor knows where it is before they need it | §6 |

⚠ **Sigstore's keyless signing removes most of this problem** and replaces it
with a dependency on external infrastructure. Supporting both is why
[`../decisions/0010-signing-scheme.md`](../decisions/0010-signing-scheme.md)
does not pick one.

---

## 3. Schema evolution

⛔ **Every schema carries a version. Nothing is inferred from field presence.**

| schema | versioned by |
| --- | --- |
| the recipe | ⚠ implicitly by the tool version; ⭐ see §3.1 |
| metadata | `schemaVersion`, [`../format/metadata-schema.md`](../format/metadata-schema.md) |
| the index | `schemaVersion` |
| media types | ⭐ a `v<N>` segment |
| provenance | `predicateType` |

### 3.1 ⚠ The recipe has no version field, and that is a decision

A recipe is read only by this project's own tooling, which is versioned, and
the validator rejects unknown keys. Adding a version field would let a recipe
declare a schema the validator does not implement, and the useful behaviour
there is to fail, which is what already happens.

⛔ **If that ever stops being true, because third-party tooling reads
recipes, a version field is required and adding it is a breaking change.**
Recorded here so the decision is visible rather than an omission.

### 3.2 Changing a schema

| change | version bump | |
| --- | --- | --- |
| add an optional field | ⭐ no | clients ignore unknown optional fields |
| add a required field | ⛔ yes | |
| remove a field | ⛔ yes | |
| change a type | ⛔ yes | |
| ⛔ change a meaning while keeping the name and type | ⛔ **yes**, and ⚠ this is the dangerous one | |

⛔ **The last row is the one that gets missed.** A field whose meaning changed
without a version bump is read by old clients as the old meaning, silently.

**The rollout:**

```
1. new clients accept v1 and v2; old clients accept v1
2. publish v2 alongside v1 for one deprecation window
3. ⭐ measure: are old clients still fetching v1?
4. stop publishing v1
```

⚠ **Step 3 needs telemetry the design does not have.** With no client
reporting, the deprecation window is a guess. ⭐ The honest substitute is a long
window and an announcement, and it is recorded in
[`../open-questions.md`](../open-questions.md).

---

## 4. ⛔ Inputs that can vanish

⚠ **The quiet long-term risk. Nothing fails today.**

| input | vanishes when | mitigation |
| --- | --- | --- |
| ⛔ a pinned base image | the publisher deletes the tag and the registry collects it | ⭐ mirror every pinned image into your own registry |
| ⛔ an upstream source commit | a repository is deleted or rewritten | ⭐ mirror the source archive for anything critical |
| a `[[tool]]` download | a release asset is removed | ⭐ mirror it |
| a licence URL | a branch moves | ⭐ already pinned by hash; the *content* is safe, the URL is not |

⭐ **Mirroring pinned build inputs is cheap and it is the difference between a
package that can be rebuilt in five years and one that cannot.** A base image
is tens of megabytes; a source archive is smaller.

⛔ **Without it, the reproducibility claim decays silently**: the artefacts stay
verifiable against their hashes, and nobody can ever rebuild them to check.

---

## 5. Deprecating a package

⛔ **Disable with a reason. Do not delete.**

```toml
[package]
disabled        = true
disabled-reason = "upstream archived 2026-08; no releases since 2024-11; use `fd` instead"
```

| effect | |
| --- | --- |
| ⭐ it stops being built | |
| ⭐ published versions stay installable | ⛔ a user with it pinned is not broken |
| search reports it as disabled, with the reason | |
| ⭐ the next person to propose it finds out why it is not there | |

⚠ **Era 1 carried 385 disabled recipes out of 871 with almost no reasons
recorded.** The information about why each was disabled is gone, so every one
is a question somebody will ask again.

---

## 6. Succession

⭐ **What a new maintainer needs, in the order they need it.**

| # | | where |
| --- | --- | --- |
| 1 | what this is and why | [`../../README.md`](../../README.md), [`../architecture.md`](../architecture.md) |
| 2 | ⭐ how to run it | [`operations.md`](operations.md) |
| 3 | ⭐ what credentials exist and **who else holds them** | [`../security/secrets.md`](../security/secrets.md) §1, [`operations.md`](operations.md) §5 |
| 4 | ⭐ where the signing keys are, and how to prove they work | ⚠ the operating project fills this in |
| 5 | what breaks | [`failure-modes.md`](failure-modes.md) |
| 6 | ⭐ what was tried and why it changed | [`../history/README.md`](../history/README.md) |
| 7 | what is unresolved | [`../open-questions.md`](../open-questions.md) |

⛔ **A handover that transfers access without transferring §6 hands over a
system whose decisions get re-litigated from scratch.** That is what the history
directory is for.

### 6.1 The test

⭐ **One sentence: can somebody who has never met you run this from the
documents alone?**

The check is not hypothetical. It is:

```
1. give a new maintainer only the repository and the credentials
2. ⭐ have them run experiments/30-oci-pipeline.sh locally
3. have them review one bot pull request and one new package
4. ⭐ have them handle one real incident with the runbooks
5. ⚠ every question they had to ask is a documentation defect. Fix it.
```

---

## 7. Winding down

⛔ **A project that stops should say so, and leave what it published usable.**

| step | |
| --- | --- |
| 1 | ⭐ announce, with a date, in the repository and the index |
| 2 | ⭐ publish a final index and keep it served |
| 3 | ⛔ do not delete published artefacts |
| 4 | ⭐ publish the signing public keys somewhere durable |
| 5 | ⚠ mark every package `disabled` with a reason pointing at the announcement |
| 6 | ⭐ document how to fork: the tree, the keys, the registry namespace |

⚠ **An unmaintained system that keeps serving is more useful than one that
disappears**, and it is more dangerous if users believe it is still receiving
security updates. Step 1 and step 5 are what separate the two.
