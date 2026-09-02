# supply-chain resistance

Concrete attacks, in the order an attacker would try them, with what stops each
and what remains.

The model is [`security-model.md`](security-model.md). This is the **attack
walkthrough**, and §6 is the rebuild fan-out, which is the cost static linking
imposes and the mechanism that pays it.

---

## 1. Typosquatting

**The attack.** Publish `ripgrepp`, or `rlpgrep`, and wait.

| control | |
| --- | --- |
| ⛔ a new package name requires a merged pull request | there is no self-service publish |
| ⭐ the validator flags a name within edit distance 1 of an existing one | a reviewer sees it |
| ⭐ search ranks exact matches first, always | a typo does not surface a squatter above the real package |
| `provides` conflicts are surfaced at install | two packages claiming `rg` is visible |

⚠ **Edit distance is a heuristic and it has false positives**: `ripgrep` and
`ripgrep-all` are both legitimate. It flags for review; it does not refuse.

---

## 2. Dependency confusion

**The attack.** Register a public package with the same name as a private
internal one, and rely on a client preferring the public source.

| control | |
| --- | --- |
| ⛔ repository priority is explicit and ordered | [`../client/client-behaviour.md`](../client/client-behaviour.md) §priority |
| ⛔ a package can be pinned to a repository: `opk install internal/tool` | |
| ⭐ a name resolving in more than one repository is reported, not silently resolved | |
| a repository can be marked exclusive for a name prefix | |

⛔ **Never resolve ambiguity by preferring the higher version.** That is the
mechanism dependency confusion exploits: the attacker publishes version 99.

---

## 3. Compromised upstream release

**The attack.** The upstream project's account is taken over and a malicious
release is published.

| control | |
| --- | --- |
| ⛔ source pinned by commit, verified after fetch | a moved tag changes nothing |
| ⭐ a version bump is a pull request a human reads | |
| ⭐ a changed hash on an *unchanged* version | ⭐ direct evidence of an artefact swapped in place |

⭐ **That last row is the strongest signal this design produces**, and it is
free: because the release file records a hash per version, upstream replacing an
artefact without changing its version shows up as a hash diff on an otherwise
unchanged line. The update bot's pull-request body says so explicitly, which is
adopted from the studied system's third era.

⚠ **It does not defend against a malicious *new* release** that a reviewer
approves. §7.

---

## 4. Compromised build dependency

**The attack.** A crate, module or package the build pulls in contains
malicious code.

| control | |
| --- | --- |
| ⛔ no credentials in the container | nothing to exfiltrate |
| ⭐ `network = "none"`, or an allowlist proxy | limited egress |
| ⛔ the artefact map | it cannot add a file to what is published |
| ⭐ the SBOM records it | detectable afterwards |
| ⭐ reproducibility | ⚠ detects *nondeterministic* malice, not deterministic malice |

⚠ **Reproducibility is weaker here than it first appears.** A malicious
dependency that does the same malicious thing every time reproduces perfectly.
Reproducibility catches a builder that was tampered with, not a dependency that
was always hostile.

⛔ **It can corrupt the artefact it is compiled into.** That is not prevented.
It is made attributable.

---

## 5. Compromised builder or registry

Covered by [`security-model.md`](security-model.md) §3. The summary: an
attacker needs both the signing key and registry control to substitute an
artefact undetectably, and independent reproduction detects a tampered builder.

---

## 6. ⭐ The rebuild fan-out

⛔ **The cost static linking imposes, and the mechanism that pays it.**

A vulnerability is found in a library. In a dynamically linked distribution,
one package is patched. Here, every package containing that library needs
rebuilding.

⚠ **A system that links statically without automating this is worse than a
distribution**, because the vulnerability persists in dozens of packages with
nobody tracking which.

### 6.1 The mechanism

```
1. an advisory names a library and an affected version range
2. ⭐ query every published SBOM for that library within that range
3. produce the affected package set
4. for each: bump the REVISION, rebuild, republish
5. mark the old revisions in the advisory index
6. clients see an ordinary upgrade
```

| step | implementation |
| --- | --- |
| 2 | ⭐ the index carries an inverted map: component → packages. Built from SBOMs at index generation. |
| 4 | one bot pull request per affected package, or one batched, per [`../ci/update-automation.md`](../ci/update-automation.md) |
| 5 | [`../registry/retention.md`](../registry/retention.md) §4 |
| 6 | ⭐ nothing new: a revision bump is already an upgrade |

⭐ **The revision field exists for this.** It is why bumping a build without an
upstream version change is expressible.

### 6.2 ⚠ What limits it

| limit | consequence |
| --- | --- |
| ⛔ SBOM completeness | ⚠ a vendored C library a scanner cannot see is a package that never gets rebuilt. §1.2 of [`sbom-and-provenance.md`](sbom-and-provenance.md). |
| build capacity | a fan-out touching 400 packages is 400 builds |
| a package that no longer builds | ⚠ a rebuild surfaces bit rot at the worst moment |
| upstream has not fixed it | nothing to rebuild against |

⛔ **The first is the serious one.** The mechanism is only as good as the SBOM,
and the SBOM of a stripped static binary is weak. Generating it from the source
tree is the mitigation, and it is why that is specified as primary.

⚠ **Time to fix, measured end to end, is the metric that matters here**, and
this repository has no deployment to measure it on.
[`../open-questions.md`](../open-questions.md).

---

## 7. Malicious contribution

**The attack.** A contributor opens a pull request whose build script does
something hostile.

⛔ **There is no technical control that replaces review.** What the design does
is make review tractable.

| control | |
| --- | --- |
| ⭐ the recipe is inert | nothing runs before a human looks |
| ⭐ the script is the only place to look | fetching, patching and collection are declarative |
| the script is short | because of the above |
| ⛔ CI on a fork has no secrets | a hostile build cannot steal anything |
| the artefact map bounds the output | it cannot publish extra files |
| ⭐ a first-time contributor requires explicit approval to run CI | GitHub's default, and it should be kept |

⚠ **The residual risk is a subtly hostile build script that a reviewer
approves.** Review checklists are in
[`../workflows/maintainer.md`](../workflows/maintainer.md), and the honest
statement is that this is the least defended position in the system.

---

## 8. Attacks on the client

| attack | control |
| --- | --- |
| path traversal on unpack | ⛔ path validation, twice: metadata and extractor |
| symlink escape | ⛔ refused during collection and during unpack |
| ⛔ terminal escape injection through a description | ⛔ sanitised before printing. [`security-model.md`](security-model.md) §6. |
| a decompression bomb | ⛔ a size limit from the metadata, enforced during decompression |
| a hostile filename | validated against the path grammar |
| TOCTOU between verify and install | ⭐ verify the staged tree, then atomically rename it |

⚠ **The decompression bomb needs the limit enforced *during* decompression, not
after.** Checking the size after writing 40 GB to disk has already failed.

---

## 9. Where an attacker gets the best return

⭐ **Ranked, because a defender's effort should follow it.**

| rank | target | why | best control |
| --- | --- | --- | --- |
| 1 | ⛔ the index signing key | ⭐ redirects every resolution | separate key, offline or hardware-backed |
| 2 | ⛔ a maintainer's account | merge plus, in a weak setup, sign | mandatory review, signing separated from CI |
| 3 | ⛔ CI, if it holds the signing key | collapses three positions into one | ⭐ do not hold it there; use Sigstore |
| 4 | a widely used upstream project | reaches many packages | commit pinning, hash-diff signal |
| 5 | a popular build dependency | reaches many packages | lockfiles, network restriction, SBOM |
| 6 | the registry | ⚠ needs the key too | digest addressing |
| 7 | a mirror | ⚠ detectable | verify after copy |

⭐ **Ranks 1 to 3 are all about key custody and process, not about
cryptography.** A project that gets those right and uses only minisign is in a
better position than one with a sophisticated scheme and its key in a CI secret
that fifteen people can read.
