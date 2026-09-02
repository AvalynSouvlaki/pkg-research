# 0001: recipes are inert, with one contained escape hatch

## Decision

⛔ **A package definition is data. Only the builder executes anything from it,
and only inside a container.**

## Problem

A packaging system needs to express how software is built. Expressing it as
code makes reading a definition dangerous; expressing it as data alone makes
some software unpackageable.

## Alternatives

| alternative | why rejected |
| --- | --- |
| ⛔ **arbitrary shell everywhere**, era 1's model | ⭐ learning a package's *version* ran a maintainer's shell with a `GITHUB_TOKEN` in the environment |
| ⛔ **no execution at all**, era 3's model | ⭐ removes building; the capability moved to a second repository, which is the same escape hatch with more steps |
| a restricted expression language | ⚠ every such language grows until it is a programming language, and then it is alternative 1 with worse tooling |
| ⭐ **inert data plus one contained script** | ⭐ chosen |

## Tradeoff

⭐ **Gained**: reading, validating, resolving and indexing are all safe. One
component to audit. A reviewable diff.

⚠ **Cost**: version discovery becomes a fixed set of strategies, so a project
with a genuinely unusual release scheme cannot be expressed until a strategy is
added. A container runtime is required to build.

## Evidence

⭐ **Observed**, at `pkgforge/soarpkgs` commit `6f1cbb9`,
`binaries/bash/static.nixpkgs.stable.yaml`: `x_exec.pkgver` is a shell pipeline
run during metadata generation. Its output is unvalidated, and the live public
index records `bash` at version `445.3p3` where upstream says `5.3p3`, observed
2026-09-02.

⭐ **Observed**, at commit `50379ab`, in that repository's own format
document: it opens with "Nothing in
this tree executes", and `pkgforge/builds` exists as a separate repository
carrying the build capability that removal took away.

## Consequences

- ⛔ Validators, resolvers, indexers and clients must not execute recipe
  content. [`../architecture.md`](../architecture.md) I1.
- ⛔ A conformance test plants a recipe whose script would write a file and
  asserts the file does not exist. [`../testing.md`](../testing.md) §5.1.
- Version discovery is a closed strategy set.
  [`../ci/update-automation.md`](../ci/update-automation.md) §3.
- The builder gets its own document and its own trust boundary.

## Reversal

⭐ **Cheap in one direction, expensive in the other.** Adding a strategy is a
change to the bot. ⛔ Widening the escape hatch, for example letting a recipe
run code during resolution, cannot be undone once packages depend on it, and it
would invalidate every claim in
[`../security/security-model.md`](../security/security-model.md) §3.
