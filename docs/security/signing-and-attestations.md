# signing and attestations

What is signed, with what, and how the signature reaches a client.

Client policy is [`trust-and-verification.md`](trust-and-verification.md). This
document is the **producer side**.

---

## 1. ⛔ What is signed

**The manifest digest. Never a tag, never the payload alone.**

```
payload bytes ──► layer digest ──┐
metadata      ──► layer digest ──┼──► MANIFEST ──► manifest digest ──► SIGNED
checksums     ──► layer digest ──┘
```

⭐ **Signing the manifest digest covers every layer transitively**, because the
manifest lists their digests and any change to a layer changes the manifest.
One signature, complete coverage.

⛔ **Signing a tag would be meaningless**: a tag is mutable, so a signature over
it says nothing about bytes.

⚠ **Signing only the payload would leave the metadata unprotected**, and the
metadata carries the install paths and the provides list. An attacker able to
swap it could redirect where files land.

---

## 2. Scheme 1: minisign

⭐ **The baseline.** Small keys, no infrastructure, verifiable with one command
and one public key.

**Signing:**

```sh
printf '%s' "sha256:d4311144c0b4d63b4e2f6e22e3286602a9f8508fe14a02822c9c0ba1e5f60b07" > digest.txt

minisign -S -s release.key -m digest.txt -x digest.txt.minisig \
  -c "opk package signature" \
  -t "opk ripgrep 14.1.1-1 x86_64-linux 2026-09-01T10:04:11Z"
```

⭐ **The trusted comment (`-t`) is signed and it carries the coordinate.** That
is what stops a valid signature for one package being presented as the
signature for another.

⛔ **A verifier MUST parse the trusted comment and check it names the package it
is verifying.** A signature that verifies cryptographically and describes a
different package is a signature-transplant attack, and minisign will not catch
it for you.

**Verifying:**

```sh
minisign -V -p release.pub -m digest.txt -x digest.txt.minisig
```

**Publishing:** attached as a referrer with `artifactType`
`application/vnd.opk.signature.v1` and a layer of
`application/vnd.opk.signature.minisign.v1`.

⭐ **Proven working** by `experiments/30-oci-pipeline.sh`, which signs a digest,
attaches it, discovers it through the registry, verifies it, and then proves the
guard can fail by verifying a tampered digest against the same signature.

⚠ **That guard-mutation check passed vacuously on its first run** because the
signature file was missing and a `minisign` verify against a missing file also
exits non-zero. The experiment now asserts the artefact is present before making
any claim about the guard. [`../principles.md`](../principles.md) §5.

---

## 3. Scheme 2: Sigstore

⭐ **No long-lived key.** The identity is the CI workflow, the certificate is
short-lived, and the signature is recorded in a public transparency log.

```sh
COSIGN_EXPERIMENTAL=1 cosign sign \
  --yes "ghcr.io/example/opk/ripgrep/ripgrep@sha256:d4311144..."
```

```sh
cosign verify \
  --certificate-identity-regexp '^https://github\.com/example/opk-packages/\.github/workflows/publish\.yaml@refs/heads/main$' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  "ghcr.io/example/opk/ripgrep/ripgrep@sha256:d4311144..."
```

| | minisign | Sigstore |
| --- | --- | --- |
| long-lived key to steal | ⛔ yes | ⭐ no |
| ⭐ transparency log | no | ⭐ yes: a forged signature is publicly visible |
| offline verification | ⭐ yes | ⚠ needs the bundle; the log can be checked offline with a trust root |
| ⛔ dependency on external infrastructure | none | ⚠ Fulcio and Rekor |
| explainable in a paragraph | ⭐ yes | ⚠ no |
| revocation | ⚠ rotate the key | ⚠ short-lived certificates make it moot |

⛔ **The identity regular expression is anchored.** An unanchored
`--certificate-identity-regexp` matching a substring accepts a signature from
any workflow whose identity contains that string, which is an authentication
bypass and has been a real finding in other projects.

⭐ **Both schemes are supported and both are attached.** A client under
`default` accepts either. The reasoning is in
[`../decisions/0010-signing-scheme.md`](../decisions/0010-signing-scheme.md):
Sigstore is stronger against key theft, minisign survives Sigstore being
unavailable, and a project that cannot explain its trust root in a paragraph
loses users who need to.

---

## 4. Scheme 3: GitHub build attestations

```yaml
- uses: actions/attest-build-provenance@v3
  with:
    subject-name: ghcr.io/example/opk/ripgrep/ripgrep
    subject-digest: sha256:d4311144...
    push-to-registry: true
```

⭐ **Produces a SLSA provenance attestation signed through Sigstore with the
workflow's identity**, and pushes it as a referrer.

⛔ **It MUST NOT be `continue-on-error`.** The studied system's era-2 workflow
marks its attestation step `continue-on-error: true`, so provenance is silently
absent whenever the step fails, and every downstream consumer sees an
unattested artefact with nothing recording why.

⚠ **`push-to-registry: true` writes the attestation as a referrer**, which on
GHCR means it lands wherever GitHub's tooling puts it. Since GHCR has no
referrers API ([`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) §5.1), the
publisher **MUST** confirm the attestation is reachable through the fallback tag
and add it there if not.

---

## 5. The signing workflow

⛔ **Separated from the build.**

```
build workflow                    signing workflow
──────────────                    ────────────────
builds, verifies                  ⛔ triggered by a published artefact
pushes the artefact               fetches the manifest digest
records the digest        ──────► verifies the artefact independently
⛔ has NO signing key              signs the digest
                                  attaches the signature
                                  updates the fallback tag
```

| control | |
| --- | --- |
| ⛔ the signing key is available only to the signing workflow | a compromised build cannot sign |
| ⭐ the signer re-verifies before signing | it does not sign what it was told, it signs what it checked |
| the signing workflow has no network access beyond the registry | |
| ⚠ signing is serialised per subject | the fallback tag is not atomic; [`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) §5.2 |

⚠ **Separation is a control this design specifies and cannot enforce.** A
project that puts the signing key in the build workflow gets a working system
with a weaker property, and [`security-model.md`](security-model.md) §4 says
exactly which property is lost.

---

## 6. Signing the index

The index is signed the same way, over the digest of the compressed catalogue,
with the generation timestamp in the trusted comment.

⛔ **Index signing is more sensitive than package signing**, because the index
decides what every resolution returns. A compromised index key redirects every
user to a chosen digest, and the only remaining defence is that the digest must
still have a valid package signature.

⭐ **Use a different key for the index than for packages.** Compromising one
should not grant the other, and it is free to do.

---

## 7. What a signature does not tell you

⛔ Stated plainly, because signatures are routinely over-read.

| a valid signature means | it does not mean |
| --- | --- |
| a key holder approved these bytes | ⛔ the software is safe |
| the bytes have not changed since | ⛔ the build was reproducible |
| ⭐ the artefact came from this project | ⛔ the upstream source was not malicious |
| the coordinate in the trusted comment matches | ⛔ that coordinate is the one you wanted |

⭐ **A signature is an authenticity claim, not a quality claim.** The
provenance attestation says how it was built; the SBOM says what is in it; the
build log says what happened. Each answers a different question and the
signature answers only "who approved this".
