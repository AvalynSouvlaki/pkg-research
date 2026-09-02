# reference sweep: pkgforge

⭐ **What was read, at which commit, what transfers, and what does not.**

⛔ **Read section 1 before any conclusion in this file.** It says what this
sweep did not establish.

---

## 1. ⛔ What this sweep did NOT establish

| | |
| --- | --- |
| ⛔ **GitHub Discussions were not fetched.** | The credential-free route is REST and discussions are GraphQL only. A design argument that happened there is missing from this sweep, and `references/*/PROVENANCE.md` records it as a gap. |
| ⛔ **No maintainer was asked anything.** | Every inference about intent is read off code and trackers. Where a reason is not written down, this file says "not recorded" rather than guessing. |
| ⚠ **The `sbuilder` tool was not read.** | It is a separate repository and its source decides several behaviours this sweep could only observe from the outside, notably what `sbuild meta hash --exclude-version` covers. |
| ⚠ **No package was built with the historical tooling.** | Build behaviour is read from recipes, workflows and published artefacts, not reproduced. |
| ⚠ **Counts are of files, not of packages.** | A package with several recipes counts several times. |
| ⭐ **Two claims from a first revision of this write-up were wrong and are corrected here.** | §7. ⛔ Assume more remain. |

---

## 2. Provenance

| repository | commit read | why |
| --- | --- | --- |
| `pkgforge/soarpkgs` | ⭐ `6f1cbb9bf65b8d01dcfa5e3f9f9f31e66ca638c5` (2025-01-14) | **era 1**: the build-and-store system |
| `pkgforge/soarpkgs` | ⭐ `dc3bed54a040c896689bbafc424d6e8ce69aeb95` (2026-07-18) | **era 2**: peak CI automation |
| `pkgforge/soarpkgs` | ⭐ `50379aba83ce8b38c0dc32c6d784bd67419058ef` (2026-09-01) | **era 3**: the inert declarative system |
| `pkgforge/builds` | `6420cb3b5815b9f9778cb1510ef49e4643f7c2e8` (2026-08-28) | the build escape hatch |
| `pkgforge/devscripts` | `05574a0f8fa966a7d0e37032a4736e5066d36b8e` (2026-08-22) | runner images |
| `pkgforge/metadata` | `a5005c84df664eefc2fa3a9df6f17dbba4c73480` (2026-01-06) | the metadata and mirror layer |
| `pkgforge/docs` | ⚠ HEAD at 2026-09-02 | the SBUILD specification |
| `pkgforge/soar` | ⚠ HEAD at 2026-09-02 | the client |

**The trackers** are kept, tracked, under `references/`, fetched 2026-09-02
with the TEMPLATE methodology's own `mine-repo.sh` over the credential-free
proxy route, both issue states, plus comments, review comments, releases and
tags:

| repository | items | issues | pull requests |
| --- | ---: | ---: | ---: |
| `soarpkgs` | 885 | 61 | 824 |
| `soar` | 193 | 70 | 123 |
| `docs` | 84 | 76 | 8 |
| `metadata` | 36 | 30 | 6 |
| `devscripts` | 25 | 0 | 25 |
| `builds` | 8 | 0 | 8 |

⚠ **The source trees are not kept in this repository.** They are large and
re-fetchable; the commits above plus `git clone` reproduce them exactly. The
trackers are kept because a tracker moves and cannot be re-fetched as it was.

```sh
git clone https://github.com/pkgforge/soarpkgs && cd soarpkgs
git worktree add ../era1 6f1cbb9bf65b8d01dcfa5e3f9f9f31e66ca638c5
git worktree add ../era2 dc3bed54a040c896689bbafc424d6e8ce69aeb95
git worktree add ../era3 50379aba83ce8b38c0dc32c6d784bd67419058ef
```

---

## 3. Route the reader

| a reader with | reads |
| --- | --- |
| two minutes | §4, the three eras in one table |
| ten minutes | §1, §5 the central finding, §7 what was got wrong |
| the design to do | §6, mechanism by mechanism |
| a reason to distrust this | §1, then §7, then the commands in §2 |

---

## 4. The three eras

| | era 1 `6f1cbb9` | era 2 `dc3bed5` | era 3 `50379ab` |
| --- | --- | --- | --- |
| date | 2025-01-14 | 2026-07-18 | 2026-09-01 |
| recipe format | YAML with shell | YAML with shell | ⭐ TOML, inert |
| ⭐ builds | ⭐ yes, in-repo | ⭐ yes, full CI | ⛔ **none** |
| recipe files | 871 binaries, 1,582 packages | 462 | 566 directories |
| ⛔ disabled | ⛔ 385 of 871 (44%) binaries, 1,548 of 1,582 (97.9%) packages | 0 | 0 |
| CI workflows | 2 | ⭐ 10 | 5 |
| ⭐ GHCR artefacts | ⭐ yes | ⭐ yes | ⛔ no |
| ⭐ build logs | ⭐ yes, published | ⭐ yes | ⛔ no |
| provenance | no | ⚠ yes, `continue-on-error` | no |
| signing | ⚠ minisign, per file | minisign | minisign, index only |
| reproducibility | ⛔ no | ⛔ no | ⭐ yes, in `pkgforge/builds` |

⭐ **The shape of the story**: era 1 could build anything and could not maintain
it. Era 2 automated the maintenance and kept the risk. Era 3 removed the risk
by removing the capability.

---

## 5. ⭐ The central finding

⭐ **Build strategies with one uniform way to link statically survived.
Strategies needing bespoke per-package work did not.**

Counted at `6f1cbb9` over `binaries/`, classifying each file by what its
`x_exec.run` invokes:

| strategy | files | disabled | rate |
| --- | ---: | ---: | ---: |
| ⭐ `soar-dl` (fetch a prebuilt) | 48 | 0 | ⭐ **0.0%** |
| ⭐ `nix-build` | 96 | 3 | ⭐ **3.1%** |
| ⭐ `go build` | 194 | 8 | ⭐ **4.1%** |
| ⭐ `cargo build` | 156 | 11 | ⭐ **7.1%** |
| ⛔ `eget` (a superseded fetcher) | 267 | 267 | ⛔ 100.0% (see below) |
| ⛔ hand-written C build systems | 25 | 23 | ⛔ **92.0%** |
| ⛔ Python packaging | 12 | 11 | ⛔ **91.7%** |
| ⛔ `zig cc` glue | 11 | 11 | ⛔ 100.0% |
| **all** | **875** | **385** | **44.0%** |

⚠ **The `eget` row is not a survival statistic.** Those 267 files are a bulk
import from a previous generation, added in the repository's first commit
`1ac9fd23` ("takeoff", 2025-01-10, 6,406 files in one commit) and never
enabled. They are dead weight, not failed builds. ⭐ Reporting them as a 100%
failure rate would be wrong, and an earlier reading of this data did exactly
that.

⛔ **Every one of the 871 files is unique.** Zero byte-identical pairs, zero
whitespace-normalised identical pairs. There is no shared abstraction to
factor out, which is the maintenance cost made visible.

⭐ **What transfers**: the strategy set a system supports determines its
maintenance burden more than anything else about it. This design's answer is
[`../../decisions/0003-static-musl-default.md`](../../decisions/0003-static-musl-default.md)
and the per-ecosystem files.

---

## 6. Mechanisms, with verdicts

⭐ **adopt** = going into this design, cited. **confirms** = independent
support for something already decided. ⛔ **anti-pattern exhibit** = kept on
purpose, because a shipped defect is worth more than an absence.

### 6.1 ⭐ adopt

| mechanism | where observed | why |
| --- | --- | --- |
| ⭐ **build log published with the artefact** | era 1, `ghcr_files` includes `<pkg>.log` | ⭐ the most useful property the system had. [`../../ci/build-logs.md`](../../ci/build-logs.md) |
| ⭐ **a package page linking to the CI run and the recipe** | era 1 metadata `build_gha`, `build_script` | ⚠ adopted with the drift fixed; §6.3 |
| ⭐ **`SOURCE_DATE_EPOCH` from the source commit** | `pkgforge/builds/build.py` | ⭐ [`../../build/reproducibility.md`](../../build/reproducibility.md) |
| ⭐ **image pinned by digest, source by commit, verified after fetch** | same | ⭐ the whole reproducibility basis |
| ⭐ **reproducibility checked off the publish path** | `builds/.github/workflows/reproducibility.yaml` | ⭐ [`../../decisions/0007-reproducibility-off-path.md`](../../decisions/0007-reproducibility-off-path.md) |
| ⭐ **verify the artefact by reading the ELF header, then run it under qemu** | `builds/build.py` `elf_header`, `verify` | ⭐ `tools/elfprobe.py` is the same idea, extended |
| ⭐ **file mode decided by content, not by name** | same | [`../../format/build-manifest.md`](../../format/build-manifest.md) §6 |
| ⭐ **tar and gzip normalisation, with the gzip header pinned separately** | same | [`../../format/artifact-layout.md`](../../format/artifact-layout.md) §6 |
| ⭐ **a mandatory `reason` field for building rather than pinning** | `builds/packages/*/build.toml` | ⭐ [`../../workflows/package-author.md`](../../workflows/package-author.md) §1 |
| ⭐ **two hashes with distinct jobs** | era 3 `soarpkgs/docs/FORMAT.md` | ⭐ [`../../decisions/0006-two-hashes.md`](../../decisions/0006-two-hashes.md) |
| ⭐ **a changed hash on an unchanged version is a signal** | era 3 update workflow body | ⭐ [`../../ci/update-automation.md`](../../ci/update-automation.md) §6 |
| ⭐ **resolve, then hashfill, then validate, then commit** | era 3 `update-packages.yaml` | ⛔ a pinned URL with no hash must not reach a commit |
| ⭐ **only 404 and 410 mean a link is dead** | era 3 `validate.yaml` | ⭐ [`../../ci/pull-requests.md`](../../ci/pull-requests.md) §3.1 |
| ⭐ **per-commit CI concurrency** | era 2 `build-on-change.yaml` comment | ⭐ [`../../ci/ci-system.md`](../../ci/ci-system.md) §3 |
| ⭐ **`provides` with alias, symlink and symlink-only operators** | `pkgforge/docs` spec 16 | ⭐ [`../../format/package-identity.md`](../../format/package-identity.md) §1.1 |
| ⭐ **`snapshots`: version history in the metadata** | era 1 metadata, era 2 recipes | ⭐ makes rollback resolvable without a round trip |
| ⭐ **a floor check before a destructive sync** | `metadata/bincache/scripts/sync_hf_mirror.sh` | ⭐ refuses when the fetched index has under 20 entries |
| ⭐ **three-state check results** | era 2 `validate-recipes.py` | ⭐ true, false, and "could not check" are different |
| ⭐ **the two-file split: identity plus pinned release** | era 3 | ⭐ [`../../format/package-format.md`](../../format/package-format.md) §2 |

### 6.2 confirms

| | |
| --- | --- |
| an inert package tree is achievable at 566 packages | era 3 |
| ⭐ a bot can carry the routine load | ⭐ 615 of 824 pull requests (74.6%) were `github-actions[bot]` |
| OCI is a workable substrate for non-image artefacts | era 1 at scale |
| native aarch64 runners exist and are used | era 2 matrix |

### 6.3 ⛔ anti-pattern exhibits

⛔ **Kept on purpose. Each is a shipped defect, which is worth more than an
absence.**

| # | defect | observed | consequence | this design |
| --- | --- | --- | --- | --- |
| X1 | ⛔ **unvalidated version from a shell pipeline** | `binaries/bash/static.nixpkgs.stable.yaml` @`6f1cbb9`; live index shows `445.3p3` for upstream `5.3p3`, 2026-09-02 | ⛔ corrupt versions in a public index clients resolve against | ⭐ a version grammar plus seven checks |
| X2 | ⛔ **credentials passed into every build script** | `pkgforge/docs` env-vars page: `GITHUB_TOKEN`, `GITLAB_TOKEN`, `HF_TOKEN` available in `x_exec.run` | any package's script could read them | ⛔ no credential in the container |
| X3 | ⛔ **`--privileged --net=host` inside a recipe** | era 1 recipes | isolation the recipe can switch off | ⛔ the builder owns isolation |
| X4 | ⛔ **`sed -i` on YAML, and a YAML parser in grep** | era 2 `update-checker.yaml` lines 155 to 205 | fragile, ~50 lines reimplementing a parser | ⭐ TOML with a real parser |
| X5 | ⛔ **comment body interpolated into a shell** | era 2 `pr-bot.yaml` line 42, job holds four write permissions | ⚠ script injection, gated only by `author_association` | ⛔ interpolate through the environment |
| X6 | ⛔ **log scrubber deleting whole lines on common English words** | era 2 `matrix_builds.yaml`: `sed -E '/(ghp_\|...\|token\|secret)/Id'` | destroys compiler errors; misses a token in a URL | ⭐ redact the value, keep the line, report the count |
| X7 | ⛔ **`continue-on-error` on the attestation step** | era 2 `matrix_builds.yaml` | provenance silently absent | ⛔ never on a step that changes what is published |
| X8 | ⛔ **signing that fails open** | era 2 `release-metadata.yaml`: warns and `exit 0` when the key is absent | unsigned metadata published as success | ⛔ a failed sign is an urgent alert |
| X9 | ⛔ **an 830-line image with `--latest --upgrade`, `set +e`, `2>/dev/null`** | `devscripts/Github/Runners/alpine-builder.dockerfile` | ⭐ the image differs every build; a failed install is invisible | ⛔ digest-pinned images |
| X10 | ⛔ **every linter step `continue-on-error`** | era 1 `repo_linter.yaml` | a gate that cannot fail | ⛔ validation is a hard gate |
| X11 | ⛔ **a blob digest in a manifest reference position** | era 1 metadata `ghcr_blob: ...@sha256:<layer digest>` | a standard client cannot resolve it | ⭐ digests used in the position that addresses them |
| X12 | ⛔ **no `artifactType`, and layers typed `...layer.v1.tar` holding raw files** | measured 2026-09-02 | a generic OCI tool cannot tell what it is, and untarring fails | ⭐ accurate media types, `artifactType` set |
| X13 | ⛔ **empty config declared `size: 0` with the empty-string digest** | same | the spec says `{}`, size 2, and says why | ⭐ the spec's value, verified |
| X14 | ⛔ **`CHECKSUM` covering 4 of 15 files, with one listed twice** | same | ⚠ a false sense of coverage | ⛔ every shipped file, exactly once |
| X15 | ⛔ **a mirror rewriting URLs inside the artefact it copies** | `sync_hf_mirror.sh` | the mirrored bytes are not the published bytes | ⭐ a mirror copies; the client rewrites |
| X16 | ⛔ **a mirror pulling by mutable tag and never verifying signatures** | same | a moved tag is mirrored silently | ⛔ mirror by digest, verify after copy |
| X17 | ⛔ **git as a blob store, hard-reset every 5000 commits** | `metadata` README | history destroyed to keep the repository usable | ⭐ an index as a signed OCI artefact |
| X18 | ⛔ **385 disabled recipes with almost no reasons** | era 1 | ⭐ nobody can tell why a package is absent | ⛔ `disabled-reason` required |
| X19 | ⛔ **a recipe link pinned to `refs/heads/main`** | era 1 `build_script` | follows to the current recipe, not the one that built it | ⭐ pin the commit, record the hash |
| X20 | ⚠ **rolling packages identified by a grep heuristic** | era 2 `rolling-rebuilds.yaml` | a guess about file shape | ⭐ declare it |

### 6.4 refused

| | why |
| --- | --- |
| ⛔ **UPX compression** | 29 recipes used it at `6f1cbb9`. ⚠ Real size win; ⛔ antivirus false positives, sandbox refusals, defeats SBOM and debug tooling. [`../../build/static-linking.md`](../../build/static-linking.md) §6. |
| ⛔ **StaticX-style self-extracting wrappers** | ⚠ used for Python packages; ⛔ fails on `noexec /tmp`, bundles a glibc, opaque to provenance |
| ⛔ **AppImage as a primary format** | ⚠ era 1's `packages/` was 97.9% disabled. ⭐ A different problem needing a different system. |
| ⛔ **filenames encoding type, provider and channel** | ⚠ era 1 `static.nixpkgs.stable.yaml`; every consumer reimplements the precedence rule |
| ⛔ **one metadata file per host triple** | ⚠ era 1 and 3; ⭐ a search then cannot say "this exists, but not for your machine" |

---

## 7. ⛔ What a first revision of this write-up got wrong

⭐ **Two claims were published in drafts of these documents and corrected. Both
were counting errors of the same kind: a token frequency read as a file count.**

| claim published | correct | how it was caught |
| --- | --- | --- |
| ⛔ "UPX used in 133 recipes" | ⭐ **29** | 133 was `grep -o` token occurrences; 29 is `grep -l` files |
| ⛔ "six of seventeen language ecosystems measured" | ⭐ **seven files** | the same sentence listed seven items |

⚠ **A third, in `requirements.md`, was a coverage table written from memory**:
67, 20 and 45 where the real values are 72, 33 and 35.
`tools/count-requirements.sh` exists because of it.

⛔ **Assume more remain.** ⭐ Three counting errors in one sweep is the honest
estimate of the rate, and the response was to derive counts with a script
rather than to be more careful.

---

## 8. Adopt ideas, not architectures

⚠ **The recurring conclusion, reached here as elsewhere.**

⭐ **What transfers is a mechanism, cited at file and line, with the reason it
applies.** §6.1 is that list.

⛔ **What does not transfer is the shape of somebody else's solution to a
problem you do not have.** Era 1's fifteen-layers-per-package structure exists
because it fed an HTTP gateway serving per-file downloads; this design fetches
evidence as referrers, which achieves the same selective fetch with fewer
objects. Copying the layer structure without the gateway would be copying a
solution to a problem that is not here.

⚠ **Direction is easy to get backwards.** `pkgforge/builds` is a *small*
repository, eleven packages, and its discipline is affordable partly because it
is small. Applying its per-package rigour to 871 packages is a different
proposition, and this design's answer is to make the rigour mechanical rather
than to assume it scales by will.
