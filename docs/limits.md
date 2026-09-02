# limits

⛔ **What is true and not going to change.** Properties of the substrate, the
physics, or the trade this design accepted. Nothing here is fixable by
implementing better.

⚠ **Distinct from [`open-questions.md`](open-questions.md)**, which is what is
unresolved. A limit is resolved: the answer is "no".

---

## Substrate

| # | limit | consequence | evidence |
| --- | --- | --- | --- |
| L1 | ⛔ **GHCR does not implement the referrers API** | the fallback tag is mandatory | ⭐ measured, `experiments/40-registry-conformance.sh`, controls held |
| L2 | ⛔ a registry tag is mutable | a tag is never an integrity claim | OCI distribution-spec |
| L3 | ⛔ a registry has no search | an external index is required | same |
| L4 | ⛔ GitHub hosts Linux runners for x86-64 and aarch64 only | ⚠ every other architecture is cross-compiled | GitHub documentation |
| L5 | ⚠ the fallback tag write is read-modify-write | ⛔ it must be serialised and reconciled | the scheme's shape |

## Static linking

| # | limit | consequence | evidence |
| --- | --- | --- | --- |
| L6 | ⛔ **a static binary cannot `dlopen`** | plugin architectures cannot be static | ⭐ measured for glibc; structural for musl |
| L7 | ⛔ a static glibc binary cannot use NSS | LDAP and mDNS resolution are lost | glibc documentation, and its own link warning |
| L8 | ⛔ **a static binary carries no shared-library security updates** | ⭐ a vulnerable library means a rebuild of every package containing it | structural |
| L9 | ⚠ musl provides `C` and `C.UTF-8` only | locale-aware formatting behaves as `C` | musl documentation |
| L10 | ⛔ a plain `-static` binary is `ET_EXEC` and gets no ASLR | `-static-pie` where available, or record `pie = false` | ⭐ measured |
| L11 | ⚠ a static binary still calls the kernel | "runs anywhere" has a floor | structural |
| L12 | ⛔ macOS does not support statically linking libSystem | ⚠ the static premise does not hold there | Apple documentation |

## Reproducibility

| # | limit | consequence | evidence |
| --- | --- | --- | --- |
| L13 | ⛔ **`apk` and `apt` do not version-pin by default** | ⚠ reproducibility holds within a window unless the base image carries the dependencies | ⭐ observed, and independently reached by `pkgforge/builds` |
| L14 | ⛔ a build cannot be proven reproducible by the party that built it | ⭐ only an independent rebuild establishes it | structural |
| L15 | ⚠ reproducibility does not detect a dependency that was always hostile | ⭐ it detects change, not malice | structural |
| L16 | ⛔ an upstream source or base image that is deleted cannot be rebuilt from | ⭐ mirror pinned inputs | structural |

## Trust

| # | limit | consequence | evidence |
| --- | --- | --- | --- |
| L17 | ⛔ **no technical control replaces review of a build script** | ⚠ the least defended position in the system | structural |
| L18 | ⛔ a signature is an authenticity claim, not a quality claim | ⚠ routinely over-read | structural |
| L19 | ⛔ an SBOM of a stripped static binary is thin | ⭐ generate from the source tree instead | ⭐ measured: a 739-byte SPDX document naming essentially nothing |
| L20 | ⚠ a signed index is replayable within its staleness window | ⛔ closing it needs an online key | structural |
| L21 | ⛔ a rotated-out key means old artefacts stop verifying | ⭐ re-sign the archive at rotation | structural |

## Scope

| # | limit | consequence |
| --- | --- | --- |
| L22 | ⛔ **a package cannot run code at install time** | no services, no system users, no capabilities |
| L23 | ⛔ this system distributes programs, not libraries | nothing links against what it installs |
| L24 | ⚠ it is a poor fit for desktop applications and plugin-based software | ⭐ era 1's AppImage side reached 97.9% disabled |
| L25 | ⛔ the project's review capacity is its publishing rate | ⭐ there is no self-service publish |

---

## ⭐ The two that matter most

⛔ **L8**, the rebuild fan-out. Static linking trades one patch point for
portability. ⭐ A system that links statically without automating the rebuild is
worse than a distribution, and the automation is
[`security/supply-chain.md`](security/supply-chain.md) §6.

⛔ **L17**, review. Everything else here is mechanism. The one place a
determined attacker meets only a human is a build script in a pull request, and
the design's answer is to make that script short and the only place to look,
not to claim it is solved.
