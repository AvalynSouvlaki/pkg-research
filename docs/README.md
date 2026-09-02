# docs

The map. One row per file, saying which question it answers, so a reader opens
what their task needs rather than everything.

⭐ **Read the row, then read the document.** These summaries route; they do not
substitute. [`../README.md`](../README.md) is the orientation for a reader with
no context at all.

---

## The spine

| file | answers |
| --- | --- |
| ⭐ [`architecture.md`](architecture.md) | the technical reference: components, data flow, state machines, invariants, limits. ⛔ When any document conflicts with this one, this one is right and the other is the defect. |
| [`terminology.md`](terminology.md) | every term used anywhere in this tree, defined once |
| [`principles.md`](principles.md) | the rules that decided the design, each with what it costs |
| [`requirements.md`](requirements.md) | numbered, testable requirements, each traced to the document that satisfies it |
| [`conventions.md`](conventions.md) | how these documents are written, and what a number owes |

## format: what a package is

| file | answers |
| --- | --- |
| [`format/package-format.md`](format/package-format.md) | the on-disk package tree, the two file kinds, and why declarations are inert |
| ⭐ [`format/build-manifest.md`](format/build-manifest.md) | `opk.toml`, every field, type, default and validation rule |
| [`format/package-identity.md`](format/package-identity.md) | names, versions, revisions, epochs, host triples, and what makes two packages the same package |
| [`format/metadata-schema.md`](format/metadata-schema.md) | the JSON a client actually consumes, versioned |
| [`format/artifact-layout.md`](format/artifact-layout.md) | what is inside a published artefact and where |
| [`format/variants-and-features.md`](format/variants-and-features.md) | features, variants, profiles, and optional dependencies |
| [`format/dependencies.md`](format/dependencies.md) | build, runtime and optional dependencies, and why the runtime set is nearly always empty |

## registry: where it lives

| file | answers |
| --- | --- |
| ⭐ [`registry/oci-ghcr.md`](registry/oci-ghcr.md) | repository layout, manifests, referrers, tags, and ⛔ the GHCR limits that shaped all three |
| [`registry/media-types.md`](registry/media-types.md) | every media type and `artifactType` this system defines, and what a client does with an unknown one |
| [`registry/index-and-search.md`](registry/index-and-search.md) | the generated index, its format, its signature, and how search works without a server |
| [`registry/mirroring.md`](registry/mirroring.md) | mirrors, replication, and what a mirror is allowed to change |
| [`registry/retention.md`](registry/retention.md) | what is kept, for how long, and what deletes it |

## build: how it is made

| file | answers |
| --- | --- |
| ⭐ [`build/build-system.md`](build/build-system.md) | the builder's contract: inputs, environment, execution, output verification |
| [`build/build-environments.md`](build/build-environments.md) | base images, their pinning, and what a build may reach |
| [`build/toolchains.md`](build/toolchains.md) | selecting a toolchain, and pinning it so a rebuild means something |
| ⭐ [`build/reproducibility.md`](build/reproducibility.md) | determinism, hermeticity, `SOURCE_DATE_EPOCH`, archive normalisation, and the gaps that remain |
| ⭐ [`build/static-linking.md`](build/static-linking.md) | the general theory, the measured results, and when static linking is the wrong answer |
| [`build/cross-compilation.md`](build/cross-compilation.md) | building for an architecture with no runner, and proving the result |
| [`build/languages/README.md`](build/languages/README.md) | per-ecosystem static linking, one file each |

## security: why you may believe it

| file | answers |
| --- | --- |
| ⭐ [`security/security-model.md`](security/security-model.md) | the threat model: who can do what, and what each compromise costs |
| [`security/trust-and-verification.md`](security/trust-and-verification.md) | trust policies, key distribution, rotation, and what a client refuses |
| [`security/signing-and-attestations.md`](security/signing-and-attestations.md) | what is signed, with what, and how it is checked |
| [`security/sbom-and-provenance.md`](security/sbom-and-provenance.md) | SBOM generation and SLSA provenance, and what each is and is not evidence of |
| [`security/supply-chain.md`](security/supply-chain.md) | attack resistance, concretely, per attacker position |
| [`security/sandboxing.md`](security/sandboxing.md) | the build sandbox and the install-time permission model |
| [`security/secrets.md`](security/secrets.md) | what credentials exist, who holds them, and how logs are kept clean |

## client: what the user's machine does

| file | answers |
| --- | --- |
| ⭐ [`client/client-behaviour.md`](client/client-behaviour.md) | resolution, verification, install, upgrade, downgrade, rollback, and the invariants each holds |
| ⭐ [`client/cli.md`](client/cli.md) | every command, flag, exit code and output format |
| [`client/installation-layout.md`](client/installation-layout.md) | where files go, user versus system, and relocatability |
| [`client/offline-and-airgap.md`](client/offline-and-airgap.md) | bundles, air-gapped transfer, and operating with no network at all |
| [`client/delta-and-gc.md`](client/delta-and-gc.md) | delta updates, caching, and reclaiming disk |
| [`client/hooks.md`](client/hooks.md) | lifecycle hooks, and ⛔ why the default is that a package cannot run one |

## ci: what the robots do

| file | answers |
| --- | --- |
| [`ci/ci-system.md`](ci/ci-system.md) | the workflows, their triggers, their permissions, and their concurrency |
| [`ci/pull-requests.md`](ci/pull-requests.md) | the pull-request pipeline, from a fork, safely |
| [`ci/update-automation.md`](ci/update-automation.md) | how a new upstream version becomes a reviewed pull request |
| [`ci/build-logs.md`](ci/build-logs.md) | storing, publishing, retrieving and reading build logs |
| [`ci/error-reporting.md`](ci/error-reporting.md) | what a failure produces, and where a human reads it |

## workflows: what each kind of human does

| file | answers |
| --- | --- |
| [`workflows/package-author.md`](workflows/package-author.md) | adding a package, from nothing to merged |
| [`workflows/maintainer.md`](workflows/maintainer.md) | reviewing, merging, and the judgement calls that are not mechanical |
| [`workflows/end-user.md`](workflows/end-user.md) | installing, upgrading, diagnosing, and getting out of trouble |
| [`workflows/developer.md`](workflows/developer.md) | working on the system itself, locally |

## ops: running it for years

| file | answers |
| --- | --- |
| [`ops/operations.md`](ops/operations.md) | the runbooks, the dashboards, and the routine work |
| [`ops/failure-modes.md`](ops/failure-modes.md) | ⭐ what breaks, how it presents, and what to do. The table to read during an incident. |
| [`ops/rate-limits.md`](ops/rate-limits.md) | registry and forge limits, measured where possible, and how the system stays under them |
| [`ops/abuse-prevention.md`](ops/abuse-prevention.md) | what a hostile contributor can attempt, and what stops it |
| [`ops/long-term-maintenance.md`](ops/long-term-maintenance.md) | schema evolution, deprecation, and handing the project to its next maintainer |


## the rest

| file | answers |
| --- | --- |
| [`testing.md`](testing.md) | the test strategy, per layer, and the acceptance gate |
| [`migration.md`](migration.md) | moving an existing package set onto this system |
| [`compatibility.md`](compatibility.md) | target platforms, backward compatibility, and version skew |
| [`poc/README.md`](poc/README.md) | which experiment demonstrates which part of the specification |
| [`open-questions.md`](open-questions.md) | ⛔ what is genuinely unresolved, with what would resolve it |
| [`limits.md`](limits.md) | what is true and not going to change |
| [`lessons.md`](lessons.md) | what was learned, tagged, with its source |
| [`decisions/README.md`](decisions/README.md) | one record per decision: the problem, the alternatives, the cost, the consequences |
| [`interop/glibc-research.md`](interop/glibc-research.md) | ⭐ a sibling project that makes glibc portable, ⛔ **and the two claims of ours its measurements disprove** |
| [`history/README.md`](history/README.md) | ⛔ what was believed here and why that changed, plus the claims this repository has withdrawn |

---

## The rules these documents hold themselves to

Stated in full in [`conventions.md`](conventions.md). The four that matter most:

- ⛔ **One fact, one home.** A value in two documents with no check between
  them drifts, and the copy a reader trusts is the wrong one.
- ⛔ **Never a fabricated number.** A dash where the value is unknown, and a
  measurement carries its conditions or it is not a measurement.
- ⛔ **Observed, inferred and recommended are labelled**, every time, so a
  reader knows which sentences would survive contact with a different machine.
- ⚠ **A page nothing links to is a finding.** Unlinked means unread, which
  means uncorrected.
