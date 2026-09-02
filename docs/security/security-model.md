# security model

⭐ **The threat model.** Who can attempt what, what stops them, and what each
compromise actually costs.

Signing mechanics are [`signing-and-attestations.md`](signing-and-attestations.md).
Client policy is [`trust-and-verification.md`](trust-and-verification.md).
Attack resistance per position is [`supply-chain.md`](supply-chain.md). This
document is the **model**.

---

## 1. Assets

| # | asset | why an attacker wants it |
| --- | --- | --- |
| A1 | the bytes a user executes | ⭐ arbitrary code on every machine that installs |
| A2 | the signing key | forge A1 so it verifies |
| A3 | the index | redirect resolution to a chosen digest |
| A4 | the package tree in git | change a build so it produces A1 |
| A5 | the CI credential | publish A1 directly |
| A6 | the base images | change the toolchain so it produces A1 |
| A7 | user data on the installing machine | ordinary theft, through A1 |
| A8 | build logs | ⚠ secrets that leaked into them |

⭐ **A1 is the only asset that matters on its own.** Every other row is a route
to it, which is what makes the model tractable.

---

## 2. Attacker positions

| # | position | can | cannot |
| --- | --- | --- | --- |
| P1 | a stranger opening a pull request | propose any recipe change | merge, publish, sign |
| P2 | a package's upstream maintainer | change what a pinned commit's *tag* points at; publish a malicious release | change a pinned commit's content |
| P3 | a compromised dependency in a build | run code in the build container | ⭐ reach a credential, or change what is published beyond the artefact map |
| P4 | a project maintainer | merge, and cause a publish | ⛔ not sign alone, if signing is separated |
| P5 | whoever holds the signing key | sign anything | change what the index resolves to, without also being P6 |
| P6 | whoever controls the registry | serve different bytes for a tag | ⛔ produce bytes matching a signed digest |
| P7 | a network attacker between client and registry | ⛔ nothing, given TLS and digest verification | |
| P8 | a mirror operator | serve stale or partial content | ⛔ alter content undetectably |
| P9 | a user on the installing machine | install anything they choose | ⛔ escalate through the package manager, if it is user-scoped |

⭐ **P5 and P6 must be combined to substitute an artefact undetectably.** That
separation is the design's central security property and it comes from checking
the hash and the signature independently, invariant I6 in
[`../architecture.md`](../architecture.md).

---

## 3. Controls, per position

### P1: a pull request from a stranger

| control | |
| --- | --- |
| ⭐ the recipe is inert | reading, validating and indexing it runs nothing |
| ⛔ CI on a fork runs with no secrets | a `pull_request` workflow gets a read-only token and no repository secrets |
| ⛔ the build runs in a disposable container with no credentials | [`../build/build-system.md`](../build/build-system.md) §3.1 |
| the artefact map bounds what can be published | a script writing an extra file publishes nothing extra |
| ⭐ human review of a small diff | the diff is small *because* the recipe is inert |

⚠ **The residual risk is a reviewer approving a malicious build script.** No
mechanism removes it. What the design does is make the script the *only* place
to look, and keep it short by moving fetching, patching and collection into
declarative fields.

### P2: a hostile upstream

| control | |
| --- | --- |
| ⛔ source pinned by commit, verified after fetch | a moved tag cannot change what is built |
| ⭐ a version bump is a reviewable diff | a new upstream release is a pull request, not an automatic rebuild |
| ⭐ a changed hash on an unchanged version is a signal | ⭐ direct evidence of an artefact replaced in place |

⚠ **This is the position with the least protection, and it is honest to say
so.** If a project's maintainer publishes a malicious release and a reviewer
approves the bump, the system distributes it. What it provides afterwards is
attribution: the exact commit, the exact build, the exact log.

### P3: a compromised build dependency

| control | |
| --- | --- |
| ⛔ no credential in the container | nothing to steal |
| ⭐ `network = "none"` or a proxy allowlist | limited exfiltration |
| ⛔ the artefact map | it cannot add a file to the published artefact |
| the container is destroyed | no persistence |
| ⭐ reproducibility | a build that produces different bytes on a second machine is detectable |

⚠ **It CAN corrupt the artefact it is part of.** A malicious crate compiled
into the binary is in the binary. The control is that this is detectable in the
SBOM and reproducible across machines, not that it is prevented.

### P4 to P6: the publishing chain

| control | |
| --- | --- |
| ⭐ signature over the manifest digest | a moved tag does not verify |
| ⭐ hash in the signed index, checked against the bytes | a forged signature over different bytes still fails |
| ⛔ signing key not held by the build workflow | see §4 |
| provenance attestation | the builder identity is recorded and checkable |
| ⭐ reproducibility | an independent rebuild detects a tampered builder |

### P7: the network

⛔ **Nothing to do beyond TLS and digest verification**, both of which are
mandatory. A network attacker cannot produce bytes matching a digest.

⚠ **Except a downgrade.** An attacker who can serve an old, validly signed
index pins a client to an old version. The freshness controls in
[`../registry/index-and-search.md`](../registry/index-and-search.md) §4 bound
it and do not eliminate it.

### P9: the installing user

⛔ **A package MUST NOT be able to escalate.**

| control | |
| --- | --- |
| ⭐ user-scoped install by default | no root, nothing outside the user's directory |
| ⛔ no install hooks | [`../client/hooks.md`](../client/hooks.md) |
| ⛔ no setuid or setgid files | verifier check V8 |
| ⛔ path validation on extraction | nothing escapes the install prefix |
| system-wide install is an explicit, separate action | root is opt-in and visible |

---

## 4. Key custody

⛔ **The signing key is not available to the workflow that builds.**

| what | where | who |
| --- | --- | --- |
| the release signing key | ⭐ an offline or hardware-backed store | a small named set of maintainers |
| a CI signing key, if used | a repository secret, scoped to one workflow | ⚠ see below |
| the registry push credential | the workflow's ephemeral token | CI |

⚠ **A CI-held signing key means compromising CI compromises signing**, which
collapses P4, P5 and P6 into one position and removes the design's main
separation. It is offered because the alternative, a human signing every
release, does not survive contact with 615 bot pull requests.

⭐ **Sigstore keyless signing is the better answer to this specific tension**
and is why it is supported alongside minisign:
[`signing-and-attestations.md`](signing-and-attestations.md) §3. The identity is
the workflow, the certificate is short-lived, and there is no long-lived key to
steal.

---

## 5. What this design does not defend against

⛔ Stated here rather than discovered later.

| # | not defended | why |
| --- | --- | --- |
| D1 | a malicious upstream release approved by a reviewer | no technical control replaces review |
| D2 | a malicious build script approved by a reviewer | same |
| D3 | a maintainer with commit and signing rights acting maliciously | ⚠ requires separation of duties this design permits but does not require |
| D4 | a vulnerability in the software being packaged | not a packaging concern; the advisory mechanism surfaces it |
| D5 | ⚠ an index replay within the staleness window | needs an online timestamp role |
| D6 | a compromised base image whose digest we pinned | ⭐ reproducibility detects a *change*, not a compromise that was always there |
| D7 | ⚠ a compromised language-registry dependency | pinned by lockfile, and a lockfile pins what was published, not that it is safe |

⭐ **D6 deserves the emphasis.** Pinning by digest guarantees you get the same
image every time. It does not guarantee that image was ever trustworthy. The
mitigation is to use images from a small set of well-known publishers and to
review the pin when it is bumped, which is a process control, not a technical
one.

---

## 6. Display and rendering

⛔ **Every string that came from a package is untrusted display text.**

A recipe's `description`, `note`, `maintainer` and `homepage` are written by
whoever proposed the package. A build log contains whatever a compiler printed.

**A client MUST**:

- ⛔ strip or escape terminal control sequences before printing any of it;
- ⛔ never pass it to a shell;
- never render it as markup in a web view without escaping;
- bound its length before printing.

⚠ **Terminal escape injection is the concrete attack.** A `description`
containing escape sequences can rewrite earlier lines of the terminal, hiding a
warning the client just printed, or move the cursor to fake a prompt. It costs
one sanitising function and it is easy to forget.

---

## 7. The properties this model provides

⭐ Stated as claims a reader can check against §3.

1. Reading the package tree executes nothing from it.
2. A build cannot reach a credential or publish outside its declared artefacts.
3. A published artefact cannot be substituted without controlling both the
   signing key and the registry.
4. A tag moved on the registry does not change what a client installs.
5. An artefact can be independently rebuilt and compared.
6. Installing a package cannot escalate privilege on the user's machine.
7. A build failure is published rather than hidden.

⛔ **Claim 3 is the one with a caveat**: it holds only while the signing key is
not held by the same system that can push to the registry. §4.
