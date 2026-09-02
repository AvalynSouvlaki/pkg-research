# 0010: both minisign and Sigstore

## Decision

⭐ **Publish both a minisign signature and a Sigstore signature. A client under
the default policy accepts either.**

## Problem

Sigstore is stronger against key theft and depends on external infrastructure.
minisign has no such dependency and has a long-lived key to steal. Choosing one
gives up what the other provides.

## Alternatives

| alternative | why rejected |
| --- | --- |
| ⚠ **minisign only** | ⭐ simple, offline-verifiable, explainable in a paragraph; ⛔ a long-lived key, and in CI that key collapses three attacker positions into one |
| ⚠ **Sigstore only** | ⭐ no long-lived key, public transparency log; ⛔ depends on Fulcio and Rekor being available, and cannot be explained to a user in a paragraph |
| ⛔ GPG | ⚠ the traditional answer; ⛔ key distribution and a trust model most users cannot operate |
| ⭐ **both** | ⭐ chosen |

## Tradeoff

⭐ **Gained**: key theft is bounded by Sigstore's short-lived certificates,
while minisign keeps working when Sigstore does not and when a verifier is
offline. ⭐ An adopter who wants only one can drop the other.

⚠ **Cost**: two signing paths, two verification paths, two things to get right.
⚠ A client must handle "one verified, the other did not", and the policy for
that is: one valid signature from a trusted key satisfies the default policy.

## Evidence

⚠ **Recommended.** This is a judgement about operational and human factors.

⭐ **Observed**: era 2 signs with minisign and stores the key as a CI secret,
which is the configuration that collapses the positions. ⭐ **Observed**: era 2
also uses `actions/attest-build-provenance`, which is Sigstore, and marks it
`continue-on-error: true`, so it is silently absent on failure.

⚠ **Inferred**: a project that cannot explain its trust root in a paragraph
will be forked by someone who can, which is the argument for keeping minisign
as the baseline rather than the fallback.

## Consequences

- ⛔ Both are attached as referrers, with distinct `artifactType` values.
- ⛔ The signing workflow is separate from the build workflow and holds the key.
- ⛔ A Sigstore identity pattern is anchored; an unanchored one is an
  authentication bypass.
- ⛔ A minisign verifier checks the trusted comment names the package.

## Reversal

⭐ **Cheap either way.** Dropping one is a publisher change plus a client
policy change. ⚠ Artefacts published with only the dropped scheme keep
verifying only under a policy that still accepts it, so a deprecation window is
needed.
