# 0007: reproducibility checked off the publish path

## Decision

⭐ **A scheduled weekly job rebuilds published packages on a different runner
and compares bytes. It does not gate publication.**

## Problem

Reproducibility is what makes an independent party able to check the builder.
Checking it costs a second build, and where that check sits changes what it
proves and what it breaks.

## Alternatives

| alternative | why rejected |
| --- | --- |
| ⛔ **no check** | ⭐ the claim becomes untested and decays silently |
| ⚠ **build twice in the publish job** | ⛔ doubles publish time, and ⭐ **catches almost nothing**: same runner, minutes apart, so only timestamps and paths vary |
| ⛔ **gate publication on reproducing** | ⚠ a transient difference blocks a release nobody has pinned yet, and doubles the ways a release can fail |
| ⭐ **a scheduled job on a different runner** | ⭐ chosen |

## Tradeoff

⭐ **Gained**: the check tests what it claims to, because the runner and the day
both differ. A failure is investigated rather than blocking.

⚠ **Cost**: a window. A package that never reproduced is published and stays
published until the weekly job runs. ⭐ Mitigated by a same-runner double build
on a package's *first* publish, which is cheap and catches gross errors.

## Evidence

⭐ **Observed**, `pkgforge/builds`, `.github/workflows/reproducibility.yaml`,
whose own comment states the reasoning: rebuilding twice in one job "only ever
caught timestamps and paths", and the job is "deliberately off the publish path"
because a failure "is something to investigate, not a reason to block a release
nobody has pinned yet".

⭐ **Measured**, `experiments/30-oci-pipeline.sh`: a same-host rebuild is
byte-identical, which demonstrates the timestamp, path, locale and archive
controls. ⚠ It demonstrates nothing about toolchain or dependency drift,
because the same host built both.

## Consequences

- A `SUSPECT` state exists and does not unpublish.
  [`../architecture.md`](../architecture.md) §6.1.
- The weekly job is on the operations schedule and its output is read.
  [`../ops/operations.md`](../ops/operations.md) §6.
- ⛔ Metadata records the reproducibility level reached, so a consumer knows
  what the hash means.

## Reversal

⭐ **Cheap.** Moving the check onto the publish path is a workflow change. ⚠ Do
not: the reason it is off-path is measured by somebody who tried both.
