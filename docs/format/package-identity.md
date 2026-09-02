# package identity

Names, versions, revisions, epochs, host triples, and the rules that decide
whether two things are the same package.

[`../architecture.md`](../architecture.md) §4 owns the coordinate *shape*. This
document owns the *grammars* and the *comparison rules*.

---

## 1. Names

```
name      ::= [a-z0-9] [a-z0-9._+-]{0,63}
```

⛔ **Lowercase only.** A registry repository path is case-insensitive on some
implementations and case-sensitive on others, so `Foo` and `foo` are the same
repository on one registry and two on another. Rejecting uppercase at the
source removes an entire class of migration failure.

⛔ **Reserved names.** These are refused because they collide with paths this
system uses: `index`, `keys`, `sig`, `sbom`, `provenance`, `log`, `all`,
`none`, `latest`, `self`, `opk`.

⚠ **A name is not unique across repositories.** Two package sets may both
contain `ripgrep`. The full identity includes the repository, and resolution
across repositories is decided by priority;
[`../client/client-behaviour.md`](../client/client-behaviour.md) §priority.

### 1.1 `provides`, and its three operators

`provides` declares the programs a package installs. Beyond a bare name, three
operators express relationships that real packages need. The syntax is adopted
from the studied system, whose specification for it is the clearest part of
that format.

| form | meaning | affects |
| --- | --- | --- |
| `rg` | installs a program called `rg` | install and search |
| `rg:ripgrep-cli` | `rg`, also findable as `ripgrep-cli` | ⭐ search only |
| `busybox==sh` | installs `busybox`, and a symlink `sh` beside it | install |
| `ripgrep=>rg` | installs the program, and only `rg` appears on `PATH` | install |

```
provides  ::= program alias* symlink*
program   ::= name
alias     ::= ":" name
symlink   ::= ("==" | "=>") name
```

**MUST**: the program comes first. **MUST**: every name in a `provides` entry
matches the `name` grammar. **MUST NOT**: a package declare two entries whose
program parts are equal.

⭐ **The distinction between `:` and `==` is the one that gets confused.** An
alias is metadata: it makes the package findable under another word and creates
nothing on disk. A symlink is an install action: a file appears.

⚠ **`=>` is the sharp one.** It renames what reaches `PATH`. A package
declaring `ripgrep=>rg` puts only `rg` on the user's `PATH`, so a user who
types `ripgrep` gets nothing. It is correct when upstream's binary name differs
from the project name and users only ever type the short one, and it is a
usability defect otherwise.

---

## 2. Versions

⛔ **A version is validated against this grammar before it is used anywhere.**
This is the countermeasure to the corruption described in
[`../principles.md`](../principles.md) §1.

```
version   ::= release ( "-" pre )? ( "+" build )?
release   ::= num ( "." num )*
num       ::= "0" | [1-9][0-9]*
pre       ::= ident ( "." ident )*
build     ::= ident ( "." ident )*
ident     ::= [0-9A-Za-z-]+
```

Additional rules a grammar cannot express:

| # | rule | catches |
| --- | --- | --- |
| V1 | total length 1 to 64 characters | a pipeline that concatenated its whole output |
| V2 | at most 6 `release` components | the same, in a subtler form |
| V3 | no component exceeds 9 digits | `445.3p3` style corruption where a prefix was glued on |
| V4 | ⭐ if the previous version is known, the new one **MUST** compare greater, unless `--allow-downgrade` is passed with a reason | a resolver that returned an older release, or a corrupted string that happens to parse |
| V5 | matches `[ignore]` in `[update]` never proposed | known-bad upstream releases |

⭐ **V4 is the check that would have caught the observed defect.** The live
index records `bash` at `445.3p3` where the previous entry was `35.3p3` and
upstream is `5.3p3`. Each individually parses; the sequence does not make
sense, and a comparison against the previous accepted version is what notices.

⚠ **V4 has a real exception, which is why it is not absolute.** Upstream
projects do occasionally renumber downwards. That is what `epoch` is for, §4,
and the exception requires a human writing a reason rather than a flag a bot
can pass.

### 2.1 Comparison

Comparison is by, in order: **epoch**, then **release** components
numerically, then **pre-release** presence and content, then **revision**.
Build metadata after `+` is ignored entirely.

| rule | example |
| --- | --- |
| release components compare numerically, left to right | `1.10.0` > `1.9.0` |
| a missing component is zero | `1.2` == `1.2.0` |
| ⭐ a version with a pre-release is LESS than the same version without | `1.0.0-rc.1` < `1.0.0` |
| pre-release identifiers: numeric compare numerically, others lexically, numeric sorts before non-numeric | `1.0.0-1` < `1.0.0-alpha` |
| a longer pre-release is greater when all prior identifiers are equal | `1.0.0-a` < `1.0.0-a.1` |
| build metadata is ignored | `1.0.0+x` == `1.0.0+y` |
| revision breaks a tie only when everything above is equal | `1.0.0-1` < `1.0.0-2` |

⚠ **This is semver's ordering, deliberately, and upstream projects do not all
use semver.** A project versioning as `2026.09` orders correctly under these
rules by accident rather than by agreement. Where a project's own ordering
differs, the recipe **SHOULD** carry a `note`, and V4 catches the case where
the difference actually matters.

---

## 3. Revisions

```
revision ::= [1-9][0-9]{0,3}
```

Starts at `1`. Incremented when the package is rebuilt without the upstream
version changing: a build fix, a patch, a toolchain bump, a dependency
rebuild.

⛔ **Reset to `1` when the version changes.** A revision is scoped to its
version.

⛔ **Never decremented, never reused.** A given `version-revision` maps to one
set of bytes forever. Invariant I10 in
[`../architecture.md`](../architecture.md).

⭐ **The revision is what makes the fan-out rebuild in
[`../security/supply-chain.md`](../security/supply-chain.md) expressible.**
When a statically linked dependency has a vulnerability, every package
containing it is rebuilt at the same upstream version with a bumped revision,
and clients see an upgrade.

---

## 4. Epoch

```
epoch ::= [0-9]{1,3}
```

Optional, default `0`, written as a prefix: `1:2.0.0-1`.

⛔ **An epoch dominates all other comparison.** `1:1.0.0` > `0:99.0.0`.

⚠ **Adding an epoch is irreversible and it is a maintainer decision, never a
bot's.** Once added it can never be removed, because removing it makes every
future version compare lower than what users have installed. The one legitimate
cause is upstream renumbering downwards.

---

## 5. Host triples

```
host    ::= arch "-" os
arch    ::= [a-z0-9_]+
os      ::= [a-z0-9]+
```

⛔ **A closed set in practice, and an open grammar on purpose.** The grammar
does not enumerate architectures, so adding one is a table entry rather than a
format change. The recognised set today:

| host triple | notes |
| --- | --- |
| `x86_64-linux` | native runner available |
| `aarch64-linux` | native runner available |
| `riscv64-linux` | cross-compiled, verified under emulation |
| `loongarch64-linux` | cross-compiled, verified under emulation |
| `armv7-linux` | cross-compiled |
| `x86_64-darwin` | ⚠ specified, not measured in this repository |
| `aarch64-darwin` | ⚠ specified, not measured in this repository |
| `x86_64-windows` | ⚠ specified, not measured in this repository |
| `x86_64-freebsd` | ⚠ specified, not measured in this repository |

[`../compatibility.md`](../compatibility.md) states precisely what is
unverified for each non-Linux target.

### 5.1 Microarchitecture

A host triple **MAY** carry a microarchitecture suffix: `x86_64-v3-linux`.

| level | requires |
| --- | --- |
| `x86_64` (no suffix) | the base x86-64 instruction set |
| `x86_64-v2` | SSE3, SSSE3, SSE4.1, SSE4.2, POPCNT |
| `x86_64-v3` | AVX, AVX2, BMI1, BMI2, FMA, MOVBE |
| `x86_64-v4` | AVX-512F and friends |

⛔ **The default is the base level.** A binary built for `v3` fails on a `v2`
CPU with `SIGILL`, which presents to a user as an unexplained crash rather than
as a clear message.

⚠ **A package publishing a raised level MUST also publish the base level.** The
client prefers the highest level the CPU supports and falls back;
[`../client/client-behaviour.md`](../client/client-behaviour.md) §microarch.
Publishing only `v3` makes the package silently unavailable to older hardware.

### 5.2 Kernel floor

⚠ **A static binary still calls the kernel**, so "runs anywhere" has a floor.

**MUST**: a package whose artefact requires a kernel newer than the baseline
declares `min-kernel` in `[package]`.

The baseline is **Linux 3.2** for glibc-targeted builds and **Linux 2.6.39**
for musl-targeted builds, which are those libc projects' own stated minimums.
⚠ **Marked as documented, not measured**: this repository did not test on such
a kernel. The probe host ran 6.18.44.

Common causes of a raised floor: `statx` (4.11), `io_uring` (5.1),
`close_range` (5.9), `openat2` (5.6). A Go binary using `io_uring` through the
runtime is the usual accidental case.

---

## 6. When two packages are the same

| question | answer |
| --- | --- |
| same package? | equal `repository/family/name` |
| same release? | additionally equal `version`, `revision`, `host` |
| same bytes? | equal digest. ⛔ The only one that is an integrity claim. |
| interchangeable for a user? | same `provides` program set, which is a different question and is why `provides` is indexed separately |

⚠ **Two packages providing the same program conflict, and that is not an
error in the tree.** `vim` and `neovim` may both provide `vi`. Resolution
happens at install, with the user choosing;
[`../client/client-behaviour.md`](../client/client-behaviour.md) §conflicts.

---

## 7. How identity maps to registry coordinates

| identity | registry |
| --- | --- |
| `repository` | the namespace: `ghcr.io/<org>/opk` |
| `family/name` | the repository path: `.../ripgrep/ripgrep` |
| `version-revision-host` | the tag: `:14.1.1-1-x86_64-linux` |
| `version-revision` | an index tag over all hosts |
| `channel` | a mutable tag: `:stable` |

⛔ **Tag characters are constrained by the registry, not by us.** A tag matches
`[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}`. A version containing `+` is therefore
**MUST**-transformed by replacing `+` with `_` in the tag, and the untransformed
version stays in the manifest annotations and the metadata. The transformation
is not reversible in general, which is why the tag is a lookup key and the
metadata is authoritative.
