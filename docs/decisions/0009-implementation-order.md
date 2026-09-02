# 0009: the implementation order

## Decision

⭐ **Build in this order: validator, builder, publisher, index, client, then
signing.** ⛔ **Signing is item 6, not item 1.**

## Problem

A team implementing this can start anywhere. Some orders produce a working
system early; some produce months of work before anything runs.

## Alternatives

| alternative | why rejected |
| --- | --- |
| ⛔ **security first**: signing, then the rest | ⭐ signing a system whose artefacts are not yet content-addressed produces a signature over something that can still change underneath it |
| ⛔ **client first** | nothing to install |
| ⚠ **everything in parallel** | ⭐ works with enough people; ⛔ the interfaces are not settled until something has used them |
| ⭐ **the dependency order, ending in a usable system at step 5** | ⭐ chosen |

## Tradeoff

⭐ **Gained**: a working end-to-end system at step 5. Each step's output is the
next step's input, so an interface is exercised as soon as it exists.

⚠ **Cost**: the system is unsigned until step 6. ⛔ It must not be used for real
distribution before then, and that is a discipline rather than a mechanism.

## Evidence

⚠ **Recommended.** This is a judgement about how teams build, not a
measurement. What supports it:

- ⭐ **Observed**: `experiments/30-oci-pipeline.sh` was written in this order
  and the two defects it found were both in the interaction between steps 3
  and 6, which is exactly where an out-of-order build would not have looked.
- ⚠ **Inferred**: era 3 reached a working declarative system quickly because
  it started from pinning, which is the equivalent of step 1 to 5 with the
  builder omitted.

## Consequences

- ⛔ Do not publish real packages before step 6.
- ⭐ Step 5 is the milestone worth demonstrating: it is a system that installs
  software.
- [`../../README.md`](../../README.md) states the twelve-step path and marks
  the first five as the minimum.

## Reversal

⭐ **Free.** It is advice, not a constraint. A team with a reason to reorder
should, and ⛔ should still not sign before content addressing works.
