# reproducibility

⭐ **A build is reproducible when an independent rebuild produces byte-identical
output.** That is what turns the builder from a party you trust into a party
you can check.

---

## 1. Why it is load-bearing here

A built artefact has no external referent. Nobody else publishes those exact
bytes, so a hash of it attests to *our* build rather than to anything a third
party can verify.

⭐ **Reproducibility converts that back into something checkable.** If anyone
can rebuild and get the same hash, the builder stops being a single point of
failure, and a compromised builder is detectable rather than merely
regrettable.

This argument is taken directly from the studied system's build repository,
which states it in its README and implements it in 311 lines of Python. It is
the single most directly adopted piece of prior art in this design.

⚠ **Reproducibility is not the same as hermeticity.** Hermeticity is a property
of the *inputs*: fully declared, nothing undeclared reachable. Reproducibility
is a property of the *outputs*: same bytes twice. Hermeticity is the usual way
to get reproducibility and it is neither necessary nor sufficient.

---

## 2. What makes builds differ

⛔ Each row is controlled by the builder. A build that does not control all of
them is not reproducible, and the metadata says so.

| # | source of difference | control |
| --- | --- | --- |
| D1 | the current time | `SOURCE_DATE_EPOCH` from the source commit |
| D2 | the build directory path | ⛔ a fixed `/build` inside the container |
| D3 | the toolchain version | ⛔ the image pinned by digest |
| D4 | the source | ⛔ pinned by commit, verified after fetch |
| D5 | locale | `LC_ALL=C`, `LANG=C` |
| D6 | timezone | `TZ=UTC` |
| D7 | hostname, username, uid | not inherited; the container's are fixed |
| D8 | filesystem readdir order | ⛔ every archive is byte-sorted |
| D9 | archive metadata: mtime, uid, gid, uname, gname | normalised |
| D10 | compressor headers | ⛔ gzip's own mtime pinned to 0; zstd carries none |
| D11 | build-id | derived from content, so stable; or `--build-id=none` |
| D12 | parallelism affecting link order | ⚠ toolchain-specific; see §5 |
| D13 | ASLR affecting a pointer that reaches the output | ⚠ rare and real; see §5 |
| D14 | ⛔ distribution packages installed at build time | **not controlled**; §4 |
| D15 | ⛔ language dependencies fetched at build time | controlled only where the ecosystem has a lockfile |

### 2.1 `SOURCE_DATE_EPOCH`

```sh
git -C src show -s --format=%ct HEAD     # committer timestamp, seconds
```

⛔ **From the source, never from the clock.** A URL source has no commit, so
`[source].epoch` is required for it; that is why the field exists.

Honoured by gcc and clang (`__DATE__`, `__TIME__`), Go, most archive tools,
and many documentation generators. ⚠ **It is a convention, not a guarantee.**
A build system that stamps its own timestamp ignores it, and the only way to
find out is to rebuild and compare.

### 2.2 Path normalisation

⛔ Absolute paths reach an artefact through debug info, assertion messages,
`__FILE__`, and panic handlers.

| toolchain | flag |
| --- | --- |
| gcc, clang | `-ffile-prefix-map=/build=/opk` |
| Rust | `--remap-path-prefix=/build=/opk`, and `-Ztrim-paths` on nightly |
| Go | ⭐ `-trimpath` |
| Zig | paths are relative by default |

⭐ **Building at a fixed path is the belt to that braces.** Even a toolchain
with no remapping flag produces the same bytes on two machines when both build
at `/build`.

---

## 3. Verifying it

⛔ **Rebuild on a different machine at a different time. Not twice in one job.**

⚠ **Rebuilding twice in one job, minutes apart on one runner, only ever catches
timestamps and paths.** It cannot catch a toolchain difference, a
distribution-package drift, or anything that varies per host, because none of
those varies. The studied system's build repository says exactly this in the
comment on its reproducibility workflow, and it is right.

**The job:**

```
weekly:
  for each published package and host:
    rebuild from the recipe at the commit that produced it
    compare sha256 against the published artefact
    equal    -> record, no output
    different-> ⛔ mark SUSPECT, alert, diff the two
```

| property | value | why |
| --- | --- | --- |
| schedule | weekly | |
| runner | ⭐ a different one from the publish | otherwise it tests almost nothing |
| ⛔ position | **off the publish path** | §3.1 |
| on mismatch | mark `SUSPECT`, alert, do not unpublish | [`../architecture.md`](../architecture.md) §6.1 |

### 3.1 Why it is off the publish path

⭐ **A build that fails to reproduce is something to investigate, not a reason
to block a release nobody has pinned yet.** Putting the check on the publish
path means a transient CI difference delays a package, and it doubles the work
and the number of ways a release can fail to happen.

⚠ **The cost is a window.** A package that never reproduced is published and
stays published until the weekly job runs. That is accepted, and the compromise
is that the *first* build of a *new* package does run a same-runner double
build, which is cheap and catches the gross errors.

### 3.2 Diffing a mismatch

⛔ **"It did not reproduce" is not a finding. What differs is.**

```sh
diffoscope published.tar.zst rebuilt.tar.zst
```

Where `diffoscope` is unavailable, the fallback in order: compare `CHECKSUMS`
to find which file differs; compare section sizes; compare the output of
`tools/elfprobe.py --json`; then `cmp -l` for the byte offsets.

⚠ **Interpreting the diff is where the skill is.** A single differing byte
early in an ELF is usually a build-id; a differing block in `.rodata` is
usually an embedded path or timestamp; a wholly different section layout is
usually a toolchain difference.

---

## 4. ⛔ The gaps, stated

⭐ **These are the honest limits. A page claiming full reproducibility without
this section is lying by omission.**

### 4.1 Distribution packages are not version-pinned

`[build].deps` installs through `apk` or `apt`, which install whatever the
distribution currently has. A build in January and one in March can get
different `musl-dev`.

⛔ **Consequence: reproducibility holds within a window, not indefinitely.**

Two ways to close it, both real work:

| # | approach | cost |
| --- | --- | --- |
| 1 | ⭐ build a base image containing every dependency, pin it by digest, use `deps = []` | one image to maintain per toolchain family |
| 2 | pin each package to an exact version and a snapshot of the repository index | ⚠ Alpine has no long-term snapshot service; Debian has snapshot.debian.org |

⚠ **This is the same gap the studied system's build repository documents**, in
the same terms, having reached the same conclusion. That two independent
efforts land here is evidence it is a genuine property of the problem rather
than an implementation shortcut.

**What the design does about it now:** the metadata records `deps` and the
image digest, so a failed reproduction can be attributed. A package that must be
reproducible indefinitely uses approach 1 and sets `deps = []`.

### 4.2 Language dependency resolution

| ecosystem | pinned | note |
| --- | --- | --- |
| Cargo `--locked` | ⭐ yes, per-crate checksums in `Cargo.lock` | |
| Go modules | ⭐ yes, `go.sum` plus the checksum database | |
| npm `ci` | yes, integrity hashes in `package-lock.json` | ⚠ postinstall scripts still run arbitrary code |
| pip `--require-hashes` | yes | ⛔ without it, nothing |
| CMake `FetchContent` | ⚠ only if pinned to a commit | commonly pinned to a tag |
| a `Makefile` that curls a tarball | ⛔ nothing | |

⛔ **A recipe whose build fetches unpinned code SHOULD vendor and set
`network = "none"`.** Where it cannot, `hermetic` is false in the metadata.

### 4.3 Non-determinism inside a toolchain

⚠ Real, occasional, and toolchain-specific.

- **Parallel link order.** Some build systems link objects in completion
  order. `make -j1` for the link step, or a toolchain that sorts.
- **Hash-ordered iteration.** A code generator iterating a hash map emits
  declarations in a per-run order. `PYTHONHASHSEED=0` helps for Python
  generators; others need an upstream fix.
- **ASLR-derived values.** A pointer address reaching a generated file.
- **Embedded build hosts.** Autotools' `config.status` records the build
  triple, which is fine, and some projects also record the hostname.

⛔ **The response is per-package, and the finding is recorded in the recipe as a
`note`**, so the next person does not rediscover it.

### 4.4 Timestamps a build system controls

Some archive and documentation tools write the current time regardless of
`SOURCE_DATE_EPOCH`. The archive normalisation in
[`../format/artifact-layout.md`](../format/artifact-layout.md) §6 fixes this
for the outer artefact. ⚠ A nested archive *inside* the artefact is not
normalised by that, and is a per-package problem.

---

## 5. Levels

⛔ **The metadata states which level a build reached, so a consumer knows what
the hash means.**

| level | means | how it is established |
| --- | --- | --- |
| `unverified` | built once, never rechecked | default for a new package |
| `same-host` | reproduced twice on one runner | the first-build double check |
| ⭐ `cross-host` | reproduced on a different runner, a different day | the weekly job |
| `independent` | reproduced by a third party | ⚠ requires someone outside to try; see below |
| `hermetic` | additionally built with `network = "none"` | orthogonal, and recorded separately |

⭐ **`independent` is the level that actually matters and this design cannot
grant it to itself.** It requires a third party to rebuild. What the design can
do is make that cheap: the recipe, the image digest, the source commit and the
epoch are all in the published metadata, so a rebuild is one command.
[`../workflows/maintainer.md`](../workflows/maintainer.md) §independent-rebuild
has that command.

---

## 6. Proven here

`experiments/30-oci-pipeline.sh` builds a static binary, publishes it, then
rebuilds it and compares. On the probe host the rebuild was byte-identical:
`sha256:afb42bf28b19048d...`, asserted rather than printed.

⚠ **That demonstrates D1, D2, D5, D6, D9, D10 and D11 on one machine.** It does
**not** demonstrate D3, D14 or D15, because the same host with the same
toolchain built both. Cross-host reproduction needs two runners, which this
repository did not have.
[`../open-questions.md`](../open-questions.md) records it with the exact CI
job that would close it.
