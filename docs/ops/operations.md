# operations

The runbooks, the routine work, and what to check when something is wrong.

Incident diagnosis is [`failure-modes.md`](failure-modes.md).

---

## 1. What runs, and when

| job | cadence | ⛔ if it stops |
| --- | --- | --- |
| ⭐ `update` | daily | packages fall behind silently |
| ⭐ `index` | after each publish, plus daily | ⛔ new packages are invisible |
| `advisories` | daily | ⛔ vulnerable packages are not flagged |
| ⭐ `reproduce` | weekly | ⛔ a tampered builder is not detected |
| ⭐ `reconcile-referrers` | ⭐ daily | ⛔ lost signatures accumulate |
| `retention` | monthly | ⚠ storage grows |
| `image-refresh` | quarterly | base images age |
| `key-rotation-check` | monthly | ⚠ a key expires unnoticed |

⛔ **A scheduled job that stops running is silent by construction.** Each writes
a heartbeat and the monitor alerts on staleness, not only on failure.

⚠ **GitHub disables scheduled workflows in a repository with no activity for 60
days.** A quiet package set stops updating itself, and nothing says so. The
heartbeat check is what notices.

---

## 2. Dashboard

⭐ **Eight numbers. If they are right, the system is working.**

| metric | healthy | means |
| --- | --- | --- |
| index age | ⭐ under 24 h | generation is running |
| ⭐ unsigned published artefacts | ⭐ **0** | signing is running |
| fallback indexes missing an entry | ⭐ **0** | reconciliation is working |
| packages failing to build | ⚠ its own baseline | a jump means infrastructure |
| ⭐ reproducibility mismatches | ⭐ **0** | nothing has been tampered with |
| packages with an open advisory | ⚠ trending down | rebuilds are happening |
| ⭐ registry 429 rate | ⭐ under 1% | inside the budget |
| ⛔ log scrubber redactions | ⭐ **0** | ⛔ any non-zero is an incident |

⛔ **Two of these are zero-tolerance**: unsigned artefacts and scrubber
redactions. Both mean a control failed rather than a threshold being crossed.

---

## 3. Runbooks

### 3.1 A package will not build

```
1. opk log NAME --failed --host HOST
2. classify: source, build, verify, or infrastructure
3. reproduce locally:  opk build NAME --host HOST --keep
4. fix the recipe, or mark disabled WITH A REASON
5. ⛔ if infrastructure: fix the runner, do not touch the package
```

⚠ **Misclassifying infrastructure as a package failure is the common mistake**,
and it sends someone to debug a recipe that is fine. A disk-full or a runner
loss looks like a build error in the log.

### 3.2 The index is stale

```
1. did the `index` workflow run? did it fail?
2. it fails loudly on a disagreement between annotations, metadata and the
   recipe. ⭐ Read WHICH disagreement.
3. fix the source of the disagreement; ⛔ do not make the generator tolerant
4. re-run
```

⛔ **Do not "fix" the generator by making it prefer one source.** The
disagreement means one of three copies of an identity is wrong, and picking one
silently is how a corrupted entry enters a catalogue clients trust.

### 3.3 A package published unsigned

⭐ **Urgent: clients refuse it under the default policy.**

```
1. re-run the `sign` workflow for that digest
2. verify the signature is discoverable through the fallback tag
3. if signing failed: why? key access, or the artefact failed the
   signer's own verification?
4. ⛔ if the signer refused to verify, that is a finding, not a signing
   problem. Do not sign it manually.
```

⛔ **Never sign by hand to clear an alert.** The signer verifies before signing;
bypassing it removes the one check that stops a compromised build getting
arbitrary bytes signed.

### 3.4 A reproducibility mismatch

[`../workflows/maintainer.md`](../workflows/maintainer.md) §7.

### 3.5 Rate limited

```
1. reduce max-parallel in the build matrix
2. check whether one job is retrying in a loop
3. ⛔ honour Retry-After; ⚠ never a fixed sleep
4. if it persists, the budget is wrong: rate-limits.md
```

### 3.6 GHCR is down

```
1. confirm: is it GHCR or us? Try an anonymous pull of a known public image.
2. clients: mirrors take over automatically; ⭐ nothing to do
3. CI: pushes fail. ⭐ Let them fail and re-run; do not build around it.
4. ⛔ do NOT disable signature verification "temporarily"
```

⚠ **The temptation during an outage is to relax a check to get something
shipped.** A relaxation made during an incident is a relaxation nobody
remembers to undo.

### 3.7 A secret leaked

[`../security/secrets.md`](../security/secrets.md) §5. ⛔ **Revoke first.**

---

## 4. GHCR administration

⚠ **Things the registry API does not do, which surprise people.**

| task | where |
| --- | --- |
| make a package public | ⛔ GitHub Packages settings, not the registry API |
| ⛔ delete a version | the Packages REST API, by GitHub's version ID, ⛔ not by digest |
| grant a repository push access | the package's settings |
| see storage use | the org's billing page |

⛔ **The first push of a new repository creates a private package.** A new
package is invisible to users until someone makes it public, and this is the
most common "the publish worked and nobody can install it" cause.

⭐ **Automate the visibility step** in the publish workflow, or a new package
needs a manual click nobody remembers.

⚠ **Not measured here.** This repository has no GHCR namespace, so these are
from GitHub's documentation. [`../open-questions.md`](../open-questions.md)
carries the verification commands.

---

## 5. Credentials

| secret | owner | rotation | last rotated |
| --- | --- | --- | --- |
| package signing key | ⚠ (fill in) | ⭐ 2 years | ⚠ (fill in) |
| index signing key | ⚠ (fill in) | ⭐ 2 years | ⚠ (fill in) |
| bot app token | ⚠ (fill in) | 1 year | ⚠ (fill in) |
| deletion token | ⚠ (fill in) | 1 year | ⚠ (fill in) |

⛔ **This table is filled in by the operating project and kept current.** A
credential with no named owner is a credential nobody rotates.
[`../security/secrets.md`](../security/secrets.md) §1 is the inventory it
mirrors.

⚠ **A key with one holder is one accident from an unmaintainable project.**
[`long-term-maintenance.md`](long-term-maintenance.md) §custody.

---

## 6. Capacity

| resource | watch | when to act |
| --- | --- | --- |
| CI minutes | monthly burn | ⚠ a rebuild fan-out spikes it |
| registry storage | ⭐ object **count** more than bytes | [`../ci/build-logs.md`](../ci/build-logs.md) §8 |
| ⭐ API quota | requests per hour | [`rate-limits.md`](rate-limits.md) |
| runner concurrency | queue depth | builds waiting hours |

⭐ **A security rebuild fan-out is the load spike to plan for.** One advisory
against a common library can mean hundreds of builds in a day, and it is exactly
when you least want to be rate limited.
[`../security/supply-chain.md`](../security/supply-chain.md) §6.

---

## 7. Onboarding a maintainer

```
1. read README.md, then docs/architecture.md
2. run experiments/10-probe-host.sh and 30-oci-pipeline.sh locally
3. review one bot pull request with someone
4. review one new package with someone
5. ⭐ be added to the alert channel BEFORE being given any credential
6. ⭐ credentials last, one at a time, narrowest first
```

⭐ **Alerts before credentials.** Someone who has watched the system fail for a
week understands what the credentials are for.

---

## 8. Offboarding

⛔ **In this order, and none of it is optional.**

```
1. remove from the alert channel      (they stop being responsible)
2. revoke tokens                       (they stop being able)
3. ⛔ ROTATE any signing key they held  (⭐ revocation is not enough:
                                         they may have a copy)
4. remove repository access
5. update ops/operations.md §5
6. update SECURITY.md if they were a contact
```

⛔ **Step 3 is the one that gets skipped, and it is the only one that matters
for a signing key.** Removing someone's access does not remove the key material
they already have.
