# principles

The rules that decided this design. Each states what it costs, because a
principle with no cost attached is a slogan, and a reader cannot tell which
ones were actually load-bearing.

⚠ These are not requirements. [`requirements.md`](requirements.md) is the
numbered, testable list. These are the reasons the requirements read the way
they do.

---

## 1. Reading a package definition must never run it

⛔ **A validator, resolver, indexer or client that executes recipe content is
not conformant.** Invariant I1 in [`architecture.md`](architecture.md).

**Why.** In era 1 of the studied system, learning a package's version meant
running the maintainer's shell. The recipe for `bash` fetched its version with
this pipeline, quoted from `binaries/bash/static.nixpkgs.stable.yaml` at commit
`6f1cbb9`:

```
nix derivation show "nixpkgs#bash" --impure --refresh --quiet 1>&1 2>/dev/null \
  | sed -n '/^[[:space:]]*{/,$p' \
  | jq -r '.. | objects | (select(has("version")).version, ...)' \
  | tr -d '[:space:]'
```

That `jq` expression emits one line per match and `tr -d '[:space:]'`
concatenates them. The live public index records the resulting version as
`445.3p3` for what upstream calls `5.3p3`. Observed on 2026-09-02 at
`https://pkgs.pkgforge.dev/repo/bincache/x86_64-linux/bash/nixpkgs/bash/`.

⭐ **Two separate failures in one line.** Arbitrary code ran to answer a
question that should have been a field lookup, and the answer was not validated
before it entered a public index that clients resolve against.

**What it costs.** Version discovery becomes a fixed set of strategies rather
than arbitrary code, so a project with a genuinely unusual release scheme
cannot be expressed until a strategy is added.
[`ci/update-automation.md`](ci/update-automation.md) has the strategy set and
the procedure for adding one.

---

## 2. Building is code, so put it in a box rather than pretending otherwise

⭐ **The escape hatch exists because removing it does not work.** Era 3 removed
execution entirely and thereby removed building; the capability moved to a
separate repository, which is the same escape hatch with more steps.

So `[build.script].run` is arbitrary shell, and everything around it is
constrained:

| constraint | effect |
| --- | --- |
| runs only in the builder, never in any other component | one component to audit |
| inside a container pinned by image digest | the toolchain cannot drift |
| source fetched at a pinned commit, verified after fetch | the input cannot drift |
| environment normalised and enumerated | the machine cannot leak in |
| outputs declared by an `[artifact]` map | the script cannot decide what ships |
| output verified independently of the script's exit code | a script that lies about success is caught |

⛔ **The script does not choose what is published.** It produces files; the
`[artifact]` map names which become the artefact. A script that writes an extra
binary publishes nothing extra.

**What it costs.** A container runtime is required to build. Nothing else in
the system needs one, and [`build/build-system.md`](build/build-system.md)
specifies the reduced-isolation fallback for hosts without one, along with what
that fallback gives up.

---

## 3. Content addressing everywhere, tags nowhere that matters

⛔ **A tag is a lookup key. A digest is the truth.** A signature covers a
manifest digest. A client fetches by digest. An index maps a coordinate to a
digest.

**Why.** A tag can be moved to different bytes at any time by anyone with push
rights, and the historical system's own metadata exposes the consequence: it
publishes `ghcr_blob` as `ghcr.io/.../b3sum@sha256:eccbc90e...`, which is a
*blob* digest written in the position an OCI reference reserves for a
*manifest*. A standard client resolving that reference does not get the binary;
it gets an error. The mirror script it feeds pulls by mutable tag instead, so a
tag moved between index generation and mirroring is mirrored silently.

**What it costs.** Every layer carries digests, which makes the index larger
and the diffs noisier. Measured: a version bump changes a hash line, which is
exactly the signal
[`ci/update-automation.md`](ci/update-automation.md) wants a human to see.

---

## 4. Verify from outside the thing being verified

⭐ **A subject's self-report is not a measurement.** A compiler saying it
produced a static binary is not evidence; the ELF header is.

Applied concretely:

| question | the wrong instrument | what this system uses |
| --- | --- | --- |
| is this static? | the compiler's flags | `tools/elfprobe.py` reads PT_INTERP from the bytes |
| did the build succeed? | the script's exit code alone | the `[artifact]` map's declared outputs must exist |
| does the binary work? | that it compiled | run it, under emulation when cross-built |
| is this the right architecture? | the target triple passed in | `e_machine` from the ELF header |
| did the registry store it? | the push command's exit code | fetch it back and compare |

⚠ **And check whether the instrument changed the answer.** `ldd` answers the
linkage question by *running the binary's loader*, which is impossible for a
cross-built artefact and dangerous for an untrusted one.

**What it costs.** More code, and an ELF parser to maintain. `tools/elfprobe.py`
is 190 lines and it caught a real defect in this repository's own pipeline
during development.

---

## 5. A guard that has never been seen to fail is not a guard

⛔ **Plant the defect, read the exit code unpiped.** Every check in this system
ships with the negative case.

**This is not theoretical here.** In `experiments/30-oci-pipeline.sh`, a check
asserting that a tampered digest fails signature verification passed on its
first run while testing nothing: the referrers listing had been captured before
the signature was attached, so the signature file was never fetched, and a
`minisign` verify against a *missing* file also exits non-zero. The check
reported success for the wrong reason.

The fix was to assert that the signature artefact exists before making any
claim about the guard. Both the defect and the fix are in the commit history,
and the pattern is now a rule.

**What it costs.** Roughly a third more test code, and every check needs a way
to be made to fail on purpose.

---

## 6. State what is not true, in the place a reader will look

⛔ **A limit hidden is a defect filed against a user later.**

[`architecture.md`](architecture.md) §10 lists the limits. `README.md` opens
its "what this does not establish" section before the recommendations rather
than after. [`open-questions.md`](open-questions.md) exists and is linked from
the map.

⛔ **Never a fabricated number.** A dash where the value is unknown. A wrong
number on a report is worse than no number, because a blank gets checked and a
number gets used.

**What it costs.** The documents are less confident-sounding than they could
be. That is the intended trade.

---

## 7. Prefer the boring shape a check can assert

⚠ **A document that cannot be checked is a document that drifts.**

So: recipes are TOML with a schema rather than YAML with conventions; version
strings match a grammar rather than "whatever the upstream prints"; the
`[artifact]` map is explicit paths rather than a glob that silently matches
nothing; and every path this tree cites is checked to exist by
`tools/check-links.sh`.

**Why this specifically.** Era 2's update bot edited YAML with `sed -i`, and
extracted a package description with roughly fifty lines of `grep` and `sed`
reimplementing a YAML parser badly, quoted at
`.github/workflows/update-checker.yaml` lines 155 to 205 at commit `dc3bed5`.
A structured format with a real parser removes that entire class of code.

**What it costs.** TOML is less expressive than YAML. Some things that were one
clever line become three explicit ones.
[`decisions/0008-toml.md`](decisions/0008-toml.md) has the comparison.

---

## 8. Automate the work that scales, keep the judgement human

⭐ **Measured from the studied system: 615 of 824 pull requests, 74.6%, were
opened by a bot.** Counted from `references/pkgforge__soarpkgs/api/issues.json`.
Version bumps at that volume are not human work.

But: the bot opens a pull request, it does not merge one. The diff it produces
is small, literal, and reviewable precisely because the recipe is inert.

⚠ **The failure this avoids has a name and a cost.** Era 1 carried 871
hand-written build scripts, of which 385 were disabled. Nobody chose that; it
is what happens when per-package bespoke work grows faster than the people
available to maintain it. Automation is not a convenience here, it is the
difference between a maintained repository and a graveyard.

**What it costs.** Bot infrastructure, and a rate-limit budget
([`ops/rate-limits.md`](ops/rate-limits.md)).

---

## 9. The failure path is a feature, not an afterthought

⛔ **A failed build publishes its log.** A user who cannot install something
gets a URL to the reason, not silence.

**Why.** The most-praised property of era 1 was that a package page linked to
the CI log of the exact build that produced the binary. That linkage survived
into this design as a first-class artefact.
[`ci/build-logs.md`](ci/build-logs.md).

⚠ **This cuts against a common instinct.** The tidy design publishes only
successes. The useful one publishes the failure too, under an `artifactType`
no client will install, so the person who wants to know why `foo` is missing
for aarch64 can find out in one command.

**What it costs.** Storage for logs of builds that produced nothing, and a
retention policy to bound it ([`ops/retention.md`](ops/retention.md)).

---

## 10. Design for the second maintainer

⚠ **The system that needs its author present has already failed.** Every
mechanism here is chosen partly on whether a stranger can operate it:
recipes are readable without running them, the build is one command, the
verification story is a hash and a signature rather than a web of trust, and
every operational task has a runbook in
[`ops/operations.md`](ops/operations.md).

**What it costs.** Some genuinely better mechanisms are rejected for being
harder to hand over.
[`decisions/0010-signing-scheme.md`](decisions/0010-signing-scheme.md) records
one: keyless Sigstore signing is stronger in several respects and is offered as
an option rather than as the only scheme, because a project that cannot explain
its trust root in a paragraph will be forked by someone who can.

---

## 11. Do not design a ceiling

⚠ **The question is not "is this big enough for us", it is "does this build a
wall in front of the next requirement".**

Applied: the host triple is a string with a grammar rather than an enum, so a
new architecture needs no format change. Media types carry a version segment,
so a v2 payload can coexist with v1. The index is versioned and the client
states which versions it accepts. Trust policies are named and pluggable rather
than a boolean.

⚠ **The opposite failure is equally real**, and this document is not licence
for it: a knob with no caller is not smaller for being configurable. Every
extension point here has at least one concrete case that needs it, named in
the document that specifies it.
