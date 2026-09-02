# requirements

Numbered, testable requirements. Each names the document that specifies it and
the check that proves it.

⭐ **The purpose of this file is traceability**: an implementer can tick these
off, and a reviewer can ask "which requirement does this satisfy".

| strength | meaning |
| --- | --- |
| **MUST** | an implementation that does otherwise is not conformant |
| **SHOULD** | do this unless you have a stated reason not to |
| **MAY** | genuinely optional |

⚠ **A requirement with no check is a wish.** Rows whose check column says
`⚠ none yet` are honest gaps, and they are collected in
[`open-questions.md`](open-questions.md).

---

## R1: package format

| # | requirement | specified in | check |
| --- | --- | --- | --- |
| R1.1 | A recipe **MUST** be inert: parsing, validating, resolving or indexing it executes nothing it contains | [`format/package-format.md`](format/package-format.md) §3 | [`testing.md`](testing.md) §inert |
| R1.2 | A recipe **MUST** declare every build input pinned by digest or cryptographic hash | [`format/build-manifest.md`](format/build-manifest.md) §4 | validator |
| R1.3 | `[build].image` **MUST** be digest-pinned; a tag is rejected | same §4 | validator |
| R1.4 | `[source].commit` **MUST** be a full hash; a tag or branch is rejected | same §2.1 | validator |
| R1.5 | An unknown key **MUST** be an error, not a warning | same §0 | validator |
| R1.6 | Every path **MUST** pass the path grammar, before and after substitution | same §9 | [`testing.md`](testing.md) §paths |
| R1.7 | Substitution **MUST** be limited to four variables with no expressions | same §8 | validator |
| R1.8 | A validation error **MUST** name file, line, key, expected and found | same §11 | ⚠ none yet |
| R1.9 | The validator **MUST** report all errors, not only the first | same §11 | ⚠ none yet |

## R2: identity

| # | requirement | specified in | check |
| --- | --- | --- | --- |
| R2.1 | A name **MUST** match the name grammar and be lowercase | [`format/package-identity.md`](format/package-identity.md) §1 | validator |
| R2.2 | A version **MUST** match the version grammar and pass checks V1 to V5 | same §2 | [`ci/update-automation.md`](ci/update-automation.md) §4 |
| R2.3 | A discovered version **MUST** compare greater than the current, or carry an explicit override | same §2 | update bot |
| R2.4 | A release coordinate **MUST** map to exactly one digest, forever | [`architecture.md`](architecture.md) I10 | publisher |
| R2.5 | A retired coordinate **MUST NOT** be reused | [`registry/retention.md`](registry/retention.md) §5 | ⚠ none yet |
| R2.6 | A package publishing a raised microarchitecture level **MUST** also publish the baseline | [`format/package-identity.md`](format/package-identity.md) §5.1 | ⚠ none yet |

## R3: build

| # | requirement | specified in | check |
| --- | --- | --- | --- |
| R3.1 | The builder **MUST** be the only component that executes recipe content | [`architecture.md`](architecture.md) §2.1 | [`testing.md`](testing.md) §inert |
| R3.2 | A build **MUST** run in a container pinned by image digest, or be marked unsandboxed and refused publication | [`build/build-system.md`](build/build-system.md) §6 | ⚠ none yet |
| R3.3 | The build container **MUST NOT** receive any credential | same §3.1 | ⚠ none yet |
| R3.4 | The source commit **MUST** be verified after fetch | same §2.3 | `experiments/30-oci-pipeline.sh` |
| R3.5 | The environment **MUST** be enumerated; no host variable is inherited | same §3 | ⚠ none yet |
| R3.6 | Artefacts **MUST** be collected only through the `[artifact]` map | same §2.7 | ⚠ none yet |
| R3.7 | Collection **MUST** refuse a path resolving outside the build tree | same §2.7 | [`testing.md`](testing.md) §paths |
| R3.8 | Verification checks V1 to V9 **MUST** pass before publication | same §2.8 | `experiments/20-static-matrix.sh` |
| R3.9 | A build failing verification **MUST NOT** publish a payload | [`architecture.md`](architecture.md) I7 | `experiments/30-oci-pipeline.sh` |
| R3.10 | A failed build **MUST** publish its log | same I11 | `experiments/30-oci-pipeline.sh` |

## R4: reproducibility

| # | requirement | specified in | check |
| --- | --- | --- | --- |
| R4.1 | `SOURCE_DATE_EPOCH` **MUST** come from the source, never the clock | [`build/reproducibility.md`](build/reproducibility.md) §2.1 | `experiments/30-oci-pipeline.sh` |
| R4.2 | The build path **MUST** be fixed | same §2 R2 | `experiments/30-oci-pipeline.sh` |
| R4.3 | Locale and timezone **MUST** be normalised | same §2 R5, R6 | `experiments/30-oci-pipeline.sh` |
| R4.4 | Archives **MUST** be normalised: sorted, fixed mtime, uid and gid zero | [`format/artifact-layout.md`](format/artifact-layout.md) §6 | ⚠ none yet |
| R4.5 | A compressor's own timestamp **MUST** be pinned | same §6 | ⚠ none yet |
| R4.6 | A rebuild **SHOULD** be verified on a different runner, off the publish path | [`build/reproducibility.md`](build/reproducibility.md) §3 | ⚠ **not run here**: one host only |
| R4.7 | Metadata **MUST** record the reproducibility level reached | same §5 | ⚠ none yet |

## R5: registry

| # | requirement | specified in | check |
| --- | --- | --- | --- |
| R5.1 | A package manifest **MUST** set `artifactType` | [`registry/oci-ghcr.md`](registry/oci-ghcr.md) §3.1 | `experiments/30-oci-pipeline.sh` |
| R5.2 | Layer media types **MUST** describe the layer's actual content | same §3.1 | `experiments/30-oci-pipeline.sh` |
| R5.3 | The empty config blob **MUST** be `{}`, two bytes | same §3.1 | `experiments/30-oci-pipeline.sh` |
| R5.4 | Evidence **MUST** be attached as referrers | same §5 | `experiments/30-oci-pipeline.sh` |
| R5.5 | A publisher **MUST** write the referrers fallback tag | same §5.2 | `experiments/41-referrers-fallback.sh` |
| R5.6 | A client **MUST** try the referrers API, then the fallback tag | same §5.3 | `experiments/41-referrers-fallback.sh` |
| R5.7 | Fallback-tag writes **MUST** be serialised per subject | [`ci/ci-system.md`](ci/ci-system.md) §3.1 | ⚠ none yet |
| R5.8 | Annotations **SHOULD NOT** exceed the budget in §6.1 | [`registry/oci-ghcr.md`](registry/oci-ghcr.md) §6.1 | ⚠ none yet |

## R6: verification

| # | requirement | specified in | check |
| --- | --- | --- | --- |
| R6.1 | A signature **MUST** cover a manifest digest, never a tag | [`architecture.md`](architecture.md) I5 | `experiments/30-oci-pipeline.sh` |
| R6.2 | Hash and signature verification **MUST** be independent | same I6 | ⚠ partial |
| R6.3 | A client **MUST** fetch by digest and verify what arrived | [`security/trust-and-verification.md`](security/trust-and-verification.md) §2 | `experiments/30-oci-pipeline.sh` |
| R6.4 | A client **MUST** refuse an index older than the last it saw | same §4 | ⚠ none yet |
| R6.5 | A verifier **MUST** check a minisign trusted comment names the package | [`security/signing-and-attestations.md`](security/signing-and-attestations.md) §2 | ⚠ none yet |
| R6.6 | A Sigstore identity pattern **MUST** be anchored | same §3 | ⚠ none yet |
| R6.7 | The hash check **MUST** run under every trust policy | [`security/trust-and-verification.md`](security/trust-and-verification.md) §3 | ⚠ none yet |
| R6.8 | Every guard **MUST** be shown to fail on a planted defect | [`principles.md`](principles.md) §5 | `experiments/30-oci-pipeline.sh` |

## R7: client

| # | requirement | specified in | check |
| --- | --- | --- | --- |
| R7.1 | Nothing **MUST** be executable before the atomic rename | [`architecture.md`](architecture.md) I9 | ⚠ none yet |
| R7.2 | Staging **MUST** be on the same filesystem as the target | [`client/client-behaviour.md`](client/client-behaviour.md) §2 | ⚠ none yet |
| R7.3 | A failed install **MUST** leave nothing behind | same §2 | ⚠ none yet |
| R7.4 | Ambiguous resolution **MUST** be reported, never resolved by version | same §1.3 | ⚠ none yet |
| R7.5 | A conflict **MUST** be detected before staging | same §3 | ⚠ none yet |
| R7.6 | Installing **MUST NOT** execute package content | [`client/hooks.md`](client/hooks.md) §1 | ⚠ none yet |
| R7.7 | A setuid or setgid file **MUST** be refused at build and at unpack | [`security/sandboxing.md`](security/sandboxing.md) §2 | ⚠ none yet |
| R7.8 | User-scoped install **MUST** be the default and require no root | same §4 | ⚠ none yet |
| R7.9 | Untrusted display text **MUST** be sanitised before printing | [`security/security-model.md`](security/security-model.md) §6 | ⚠ none yet |
| R7.10 | Exit codes **MUST** follow [`client/cli.md`](client/cli.md) §4 | | ⚠ none yet |

## R8: automation

| # | requirement | specified in | check |
| --- | --- | --- | --- |
| R8.1 | The update bot **MUST** open pull requests, never merge | [`ci/update-automation.md`](ci/update-automation.md) §1 | ⚠ none yet |
| R8.2 | A discovered version **MUST** pass all seven checks | same §4 | ⚠ none yet |
| R8.3 | A pinned URL with no hash **MUST NOT** reach a commit | same §5 | ⚠ none yet |
| R8.4 | A changed hash on an unchanged version **MUST** be highlighted | same §6 | ⚠ none yet |
| R8.5 | The bot **MUST** use a real parser, never line editing | same §6.1 | ⚠ none yet |
| R8.6 | Fork pull requests **MUST** run under `pull_request`, never `pull_request_target` | [`ci/ci-system.md`](ci/ci-system.md) §2 | ⚠ none yet |
| R8.7 | Untrusted event fields **MUST NOT** be interpolated into a script body | same §2.1 | ⚠ none yet |
| R8.8 | A step whose absence changes what is published **MUST NOT** be `continue-on-error` | same §7 | ⚠ none yet |

## R9: documentation

| # | requirement | specified in | check |
| --- | --- | --- | --- |
| R9.1 | Every relative link **MUST** resolve | [`conventions.md`](conventions.md) | `tools/check-links.sh` |
| R9.2 | Every cited path **MUST** exist | same | `tools/check-links.sh` |
| R9.3 | No page **MUST** be unreachable | same | `tools/check-links.sh` |
| R9.4 | No banned vocabulary | same | `tools/check-links.sh` |
| R9.5 | Every number **MUST** carry its conditions or be a dash | same | ⚠ reading |
| R9.6 | Observed, inferred and recommended **MUST** be labelled | same | ⚠ reading |
| R9.7 | A media type, CLI verb or identifier used anywhere **MUST** be declared in its home document | same | `tools/check-consistency.sh` |
| R9.8 | A `§N` citation **MUST** name a section that exists | same | `tools/check-consistency.sh` |
| R9.9 | ⛔ A check **MUST** report how many claims it examined, and exit non-zero when that is zero | same §4 | `tools/check-consistency.sh` |

---

## Coverage

⭐ **Counted from the tables above by `tools/count-requirements.sh`**, so the
numbers cannot drift from the rows:

```sh
sh tools/count-requirements.sh
```

| | count |
| --- | ---: |
| requirements stated | 75 |
| ⭐ with an automated check today | 36 |
| ⚠ with `none yet` | 35 |
| ⚠ checked by reading only | 2 |
| ⚠ partial | 1 |
| ⚠ specified but not run here | 1 |

⚠ **A first draft of this table said 67, 20 and 45.** They were estimates
written before anything was counted, and all three were wrong. The counter
exists because of that.

⛔ **The ratio is the honest state of this repository**: a specification with
proofs for the load-bearing mechanisms, not an implementation with a test
suite. The 36 that are checked are the ones the design most depends on being
true.

⭐ **An implementer's first task after the minimum path is to convert
`⚠ none yet` rows into tests**, and [`testing.md`](testing.md) says how each
would be written.
