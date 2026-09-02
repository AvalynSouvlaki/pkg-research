# 0003: static linking by default, musl as the default libc

## Decision

⭐ **Packages are statically linked against musl unless they declare
otherwise.**

## Problem

A binary built on one distribution must run on another. Dynamic linking against
glibc makes that a version-compatibility problem the user experiences as
`GLIBC_2.38 not found`.

## Alternatives

| alternative | why rejected |
| --- | --- |
| ⛔ **dynamic against glibc** | ⭐ the problem this system exists to remove |
| ⚠ **static against glibc** | ⛔ works, and: 44x larger measured, ⛔ NSS unavailable, `dlopen` broken |
| build on the oldest supported distribution | ⚠ the traditional answer; ⛔ needs an old build machine forever and still fails on anything older |
| ⚠ a bundle carrying its own libraries, AppImage-style | ⭐ solves it differently and is a different system; §see reversal |
| ⭐ **static against musl** | ⭐ chosen |

## Tradeoff

⭐ **Gained**: one binary per architecture, no libc dependency, no
`GLIBC_2.38` class of failure, a much smaller artefact, and MIT rather than
LGPL for the libc.

⚠ **Cost**: ⛔ no `dlopen`, so plugin architectures cannot be static. musl's
locale support is `C` only. ⛔ A vulnerable library needs a rebuild of every
package containing it, which must be automated.

## Evidence

⭐ **Measured**, `experiments/20-static-matrix.sh` on the probe host,
2026-09-02:

| recipe | bytes |
| --- | ---: |
| `gcc -static` glibc | 785,360 |
| ⭐ `musl-gcc -static`, stripped | **17,816** |

⭐ **Measured**: `CGO_ENABLED=1` with `net` produced a binary carrying
`PT_INTERP` although nothing in the source asked for it, and it ran on the
build host.

⭐ **Observed**: era 1's disabled rate by strategy ran from 3.1% for nix and
4.1% for Go to 92% for hand-written C build systems, which is the same split
between "one uniform way to link statically" and "bespoke work per package".

## Consequences

- ⛔ Verifier check V3 rejects a `PT_INTERP` unless declared.
- A package that cannot be static sets `portable = false` with a reason.
- ⛔ The rebuild fan-out must be automated.
  [`../security/supply-chain.md`](../security/supply-chain.md) §6.
- `-static-pie` is used where available, because a plain `-static` binary gets
  no ASLR.

## Reversal

⚠ **Per package, cheap. Globally, expensive.** An individual package can
declare itself non-portable at any time. Changing the default would mean every
published artefact's portability claim no longer holds, and clients would need
a libc compatibility model that does not currently exist.
