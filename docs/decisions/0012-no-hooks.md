# 0012: no package-supplied lifecycle hooks

## Decision

⛔ **A package cannot run code at install or removal time. There is no field in
which to put one.**

## Problem

Package managers traditionally let a package run scripts around install.
Everything convenient about that is also the mechanism by which installing
software executes it.

## Alternatives

| alternative | why rejected |
| --- | --- |
| ⛔ **hooks, as most package managers have** | ⭐ installing becomes executing, and under `--system` it executes as root |
| ⚠ **sandboxed hooks** | ⛔ a sandbox that permits the useful cases permits the harmful ones; the useful cases are exactly "touch things outside the package" |
| ⚠ **declarative hooks**, a fixed set of actions | ⭐ closest alternative; ⚠ every such set grows, and each addition is a new privileged action |
| ⭐ **no hooks, plus replacements for each real need** | ⭐ chosen |

## Tradeoff

⭐ **Gained**: installing is verify, unpack, rename, symlink. ⭐ Four operations,
none of which execute package content, which is what makes `opk install` safe
to run on software nobody has audited. Install is atomic, because nothing can
fail halfway through a hook.

⚠ **Cost**: real capability is given up. A package cannot register a service,
create a user, or compile a schema at install. ⛔ Software needing those is
outside what this system distributes, and that narrows its scope.

## Evidence

⚠ **Recommended**, resting on one structural argument.

⭐ **The argument**: everything else in this design is built on verification
telling you something useful. A hook makes "this artefact is authentic" and
"installing this is safe" different claims, and only the first is checkable. ⛔
A signature covers bytes, not what they do.

⚠ **Inferred**: the cases people reach for hooks to solve are enumerable, and
[`../client/hooks.md`](../client/hooks.md) §3 lists eleven with a replacement
for each. ⚠ That enumeration is this repository's, not a survey, so a case may
be missing.

## Consequences

- ⛔ Shell completions ship as files and the client links them.
- ⛔ Config defaults ship under `etc/` and are copied on first install.
- ⛔ Anything needing a service or a system user is out of scope and says so.
- ⭐ User-configured hooks are supported; package-supplied ones are not. The
  distinction is who decided.

## Reversal

⛔ **Very expensive.** Adding hooks later would invalidate the central safety
property, and every existing client would have to be taught to run them.
⭐ Adding a *declarative* action to a fixed set is the cheap direction, and it
is the one to take if a real need appears.
