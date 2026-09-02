# 0004: the registry namespace shape

## Decision

```
ghcr.io/<org>/opk/<family>/<name>:<version>-<revision>-<host>
```

## Problem

A repository path must be unambiguous, must not collide with the index or with
non-package repositories in the same org, and must be readable.

## Alternatives

| alternative | why rejected |
| --- | --- |
| `ghcr.io/<org>/<name>` | ⛔ collides with anything else the org publishes, and a package named `index` collides with the index |
| ⚠ `ghcr.io/<org>/opk-<name>` | works; ⚠ unreadable, and no grouping for variants |
| `<name>/<host>` as separate repositories | ⛔ a multi-arch index cannot span repositories |
| ⚠ era 1's `<family>/<provider>/<name>` | ⭐ close to this, and `<provider>` encodes a disambiguator that variants make unnecessary |
| ⭐ `<org>/opk/<family>/<name>` | ⭐ chosen |

## Tradeoff

⭐ **Gained**: no collision with anything else in the org. Variants of one
project group together. The path reads as what it is.

⚠ **Cost**: deeper paths, and GHCR lists the package under its full nested
name, which is longer in the UI.

## Evidence

⚠ **Inferred** from GHCR's documented mapping of a repository path to a GitHub
Packages entry, plus ⭐ **observed** era 1 layout
`ghcr.io/pkgforge/bincache/b3sum/official/b3sum`, which nests three levels for
the same reason.

⚠ **Not measured**: this repository has no GHCR namespace, so the collision
behaviour is reasoned about rather than tested.
[`../open-questions.md`](../open-questions.md).

## Consequences

- The literal `opk` segment is fixed and appears in every path.
- `<family>` defaults to `<name>` and differs only for variants.
- ⛔ The tag carries the host, so one repository holds every architecture.

## Reversal

⛔ **Expensive.** Every published digest is addressed under this path. Changing
it means re-publishing everything and re-signing, and every pinned reference a
user holds breaks. ⭐ Adopters must choose their own segment before the first
publish.
