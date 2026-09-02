# compatibility

Target platforms, what is verified, backward compatibility, and version skew.

---

## 1. ⛔ What is verified, and what is not

⛔ **This repository ran on one Linux x86-64 host.** Every non-Linux claim below
is specified from documentation and **not measured**.

| target | status here |
| --- | --- |
| ⭐ `x86_64-linux` | ⭐ **measured**: builds, artefacts, registry, install |
| `aarch64-linux` | ⚠ **specified**; cross-compilation measured, no arm host |
| `riscv64-linux` | ⚠ specified |
| `loongarch64-linux` | ⚠ specified |
| `armv7-linux` | ⚠ specified |
| `*-darwin` | ⛔ ⚠ specified, **nothing measured**, §3 |
| `*-windows` | ⛔ ⚠ specified, **nothing measured**, §4 |
| `*-freebsd` | ⛔ ⚠ specified, **nothing measured**, §5 |

⚠ **A specification for a platform nobody ran is a plan, not a guarantee.**
Each section below states what would have to be true and what would have to be
tested first.

---

## 2. Linux

⭐ **The primary target, and the one the design is shaped around.**

| dimension | position |
| --- | --- |
| distribution | ⭐ irrelevant: a static binary has no distribution dependency |
| libc | ⭐ irrelevant for a static musl binary |
| ⚠ kernel | ⭐ **the one real floor.** [`format/package-identity.md`](format/package-identity.md) §5.2 |
| architecture | per host triple |
| init system | irrelevant: nothing installs a service |
| ⚠ filesystem | ⭐ needs `rename(2)` atomicity within one filesystem |

⚠ **The kernel floor is the only place "runs anywhere" is untrue**, and it is
declared per package rather than assumed.

---

## 3. macOS

⚠ **Specified, not measured. The differences are structural, not incidental.**

| difference | consequence |
| --- | --- |
| ⛔ **no static libc** | ⭐ Apple does not support statically linking libSystem. Every macOS binary is dynamically linked against it. |
| the platform SDK | a binary records a minimum macOS version |
| ⛔ code signing | an unsigned binary from the internet is refused by Gatekeeper |
| ⛔ notarisation | required for distribution outside the App Store |
| ⚠ quarantine | a downloaded file carries `com.apple.quarantine` and is blocked until cleared |
| ⭐ universal binaries | ⭐ one file can carry x86-64 and arm64 |

⛔ **The static-linking premise does not hold on macOS.** What replaces it:

- link everything except libSystem statically;
- ⭐ record the minimum macOS version and check it at install;
- ⛔ sign and notarise, which means an Apple Developer account and a signing
  identity in CI;
- ⭐ the client clears the quarantine attribute on files it verified itself,
  which it can do because it verified them.

⚠ **The last point is a real design question, not a detail.** Clearing
quarantine on a user's behalf is exactly what the attribute exists to prevent,
and doing it is defensible only because the client verified a signature and a
hash first. A macOS implementation should decide this deliberately.
[`open-questions.md`](open-questions.md).

---

## 4. Windows

⚠ **Specified, not measured. Several core mechanisms differ.**

| difference | consequence |
| --- | --- |
| ⛔ **no symlinks without privilege** | ⭐ the `bin/` symlink farm cannot work; use shim executables |
| ⛔ **no atomic rename over an open file** | a running program cannot be replaced |
| ⭐ static CRT | ⭐ `/MT` links the C runtime statically; this part works |
| ⚠ path length | 260 characters unless long paths are enabled |
| ⛔ executable bit | ⚠ does not exist; extension decides |
| ⚠ Authenticode | unsigned binaries trigger SmartScreen warnings |
| ⚠ antivirus | ⭐ scans and can quarantine a freshly written binary |

⛔ **The two that change the design:**

**Symlinks.** `bin/` holds a small shim `.exe` per program instead of a link.
⚠ That changes what `opk which` reports and adds a build artefact the Linux
path does not have.

**Replacing a running binary.** Windows locks an executing file. An upgrade of
a program the user is running fails. ⭐ The answer is the same one Windows
software has always used: rename the old file aside, write the new one, delete
the old on next start. ⚠ It is not atomic and it needs a recovery path.

⭐ **`ETW`, `MSI` and the registry are deliberately untouched.** Nothing is
registered, nothing is added to `PATH` system-wide, and nothing needs
administrator rights, which keeps the user-scoped property intact.

---

## 5. BSD

⚠ **Specified, not measured. The closest to Linux of the three.**

| | |
| --- | --- |
| ⭐ static linking | ⭐ supported; FreeBSD's base system links statically without difficulty |
| ⭐ ELF | ⭐ the same format, so `tools/elfprobe.py` works unchanged |
| ⚠ syscall ABI | ⛔ **different from Linux**: a Linux binary does not run on FreeBSD without the Linux compatibility layer |
| ⚠ libc | FreeBSD libc, not glibc or musl |
| ⚠ package set | ⭐ a separate host triple; nothing is shared with Linux |
| ⚠ toolchains | ⭐ clang is the system compiler; Rust and Go support it |

⭐ **`freebsd` is an ordinary host triple** and the machinery needs no change.
What it needs is a builder that runs FreeBSD, and GitHub hosts none.

---

## 6. Backward compatibility

⛔ **Within a major version of this specification:**

| | rule |
| --- | --- |
| ⭐ a client **MUST** read every index and metadata `schemaVersion` its major supports | |
| ⭐ a client **MUST** ignore unknown *optional* fields | forward compatibility |
| ⛔ a client **MUST** refuse an unknown `schemaVersion` | ⚠ never guess from field presence |
| a publisher **MUST NOT** remove a field without a version bump | |
| ⛔ a publisher **MUST NOT** change a field's meaning without a version bump | ⚠ the one that gets missed |

⭐ **A published artefact stays installable forever**, subject to key rotation:
[`security/trust-and-verification.md`](security/trust-and-verification.md)
§4.2 states the one case where an old artefact stops verifying, and what is
done about it.

---

## 7. Version skew

⚠ **Every combination that can occur in practice.**

| new | old | behaviour |
| --- | --- | --- |
| ⭐ client, old index | | ⭐ works: the client supports the older schema |
| old client, new index | | ⭐ works if the schema major is unchanged; ⛔ refuses with a clear message otherwise |
| old client, new media type on an optional layer | | ⭐ ignores it |
| ⛔ old client, new media type on a **required** layer | | ⛔ refuses. ⚠ This is why the payload type is versioned. |
| new client, artefact signed by a rotated-out key | | ⛔ refuses; §6 |
| client, registry without referrers | | ⭐ falls back to the tag |
| ⚠ client, registry **with** referrers where the publisher wrote only the tag | | ⭐ works: the API returns empty, the client falls back |

⚠ **The last row is why the client tries the API first and the fallback
second, rather than choosing one based on the registry.** A registry that
implements the API can still hold artefacts whose referrers were only ever
written as a fallback tag.

---

## 8. Interoperating with other OCI tooling

⭐ **A deliberate property: an `opk` artefact is an ordinary OCI artefact.**

| tool | works |
| --- | --- |
| ⭐ `oras pull` | ⭐ yes; it is how the experiments do it |
| ⭐ `crane`, `skopeo` | ⭐ yes, for copying and inspection |
| `cosign verify` | ⭐ yes, for Sigstore-signed artefacts |
| `syft`, `grype` | ⭐ yes, against the SBOM |
| ⚠ `docker pull` | ⛔ **no**, and correctly so: it is not a runnable image |

⚠ **`docker pull` failing is the intended behaviour.** The artefact has an
`artifactType` and no runnable config, so a container runtime refuses it rather
than producing something broken.

⛔ **Not setting `artifactType`, as the historical system does, makes a
container runtime try harder to interpret it**, which is worse than a clean
refusal.
