# artifact layout

What is inside a published artefact, where, and what the client does with each
part.

The registry-side shape (manifests, layers, referrers) is
[`../registry/oci-ghcr.md`](../registry/oci-ghcr.md). This document is the
*contents*.

---

## 1. The layout

An artefact unpacks to a self-contained tree with a fixed shape:

```
<artifact root>/
  bin/                    executables that reach the user's PATH
  libexec/<name>/         helper executables that do NOT reach PATH
  lib/<name>/             data the program loads at run time
  share/
    man/man{1..8}/        manual pages
    doc/<name>/           README and similar
    licenses/<name>/      licence texts
    applications/         .desktop entries
    icons/hicolor/.../    icons
  etc/<name>/             default configuration, never overwritten on upgrade
  .opk/
    metadata.json         the document in metadata-schema.md
    CHECKSUMS             one line per shipped file
```

⛔ **`.opk/` is reserved.** A recipe mapping an artefact into `.opk/` is
rejected by the validator: it is the client's namespace, and letting a package
write there lets a package forge its own metadata.

⚠ **The layout is a subset of the Filesystem Hierarchy Standard, deliberately.**
It is recognisable to anyone who has seen `/usr`, and it is not identical:
there is no `sbin`, no `var`, and `lib` is namespaced per package because two
packages shipping `lib/libfoo.so` must not collide.

---

## 2. What goes where

| path | reaches `PATH` | packaged by | notes |
| --- | --- | --- | --- |
| `bin/*` | ⭐ yes | `[artifact]` mapping to `bin/` | every file here is linked into the user's bin directory |
| `libexec/<name>/*` | no | explicit mapping | for helpers a program invokes itself |
| `lib/<name>/*` | no | explicit mapping | ⚠ a program needing these must find them relocatably; §4 |
| `share/man/*` | no | explicit mapping | the client adds the prefix to `MANPATH` |
| `share/licenses/<name>/*` | no | ⭐ **SHOULD** always be present | see §3 |
| `etc/<name>/*` | no | explicit mapping | ⛔ copied on first install only, never on upgrade |
| `.opk/*` | no | the builder | reserved |

⛔ **Only `bin/` reaches `PATH`.** A package wanting a helper on `PATH` puts it
in `bin/` and says so in `provides`. There is no second mechanism, because two
mechanisms means a program appears on `PATH` without being declared, and the
conflict detector in
[`../client/client-behaviour.md`](../client/client-behaviour.md) would not see
it.

---

## 3. Licences

**SHOULD**: every artefact ships its licence under `share/licenses/<name>/`.

| case | how |
| --- | --- |
| the source tree contains it | map it in `[artifact]`. ⭐ Preferred: the commit pin already covers it. |
| the source tree does not | `[[extra]]` with a `sha256`, per [`build-manifest.md`](build-manifest.md) §7 |
| the licence requires a verbatim shared text, for example the GPL family | reference `licenses/GPL-3.0.txt` from the repository root |
| proprietary software with only web terms | ⛔ do not fetch a web page and save it as `LICENSE`. Put the URL in `note`. |

⚠ **The GPL exception does not extend to MIT or BSD.** Their texts carry a
per-project copyright line, so a shared copy would attribute the work to the
wrong people. This distinction is taken from the studied system's third era,
which states it correctly.

---

## 4. Relocatability

⛔ **An artefact MUST work wherever it is unpacked.** The client chooses the
prefix; a path compiled into a binary makes that choice a lie.

| technique | when |
| --- | --- |
| ⭐ no paths at all | the common case for a single static binary |
| resolve relative to `/proc/self/exe` | a program that must find its own data |
| an environment variable the client sets | a program with no way to self-locate |
| `$ORIGIN` in `RUNPATH` | only for the rare dynamically linked artefact |

⛔ **`PREFIX` is `/opk` at build time and is not where the artefact lands.**
It is a fixed placeholder so that a path which does leak into a binary is
*constant across machines*, which keeps the build reproducible, and is
*obviously wrong* if it is ever used, which makes the defect loud instead of
quiet.

⚠ **The failure this prevents is a quiet one.** A build that bakes in
`/home/runner/work/...` produces a binary that works on the runner and fails
for every user, with a message about a missing file rather than about a bad
build.

**How it is checked.** The verifier scans every shipped file for the literal
build-tree path and for `PREFIX`; a hit outside an allowlisted set fails the
build. [`../build/build-system.md`](../build/build-system.md) §verify.

---

## 5. `CHECKSUMS`

One line per shipped file, sorted by path:

```
b3:0e5f0c9d3a6b2e4f7c1d8a5b3e9f2c6d0a4b8e1f5c9d3a7b2e6f04a1e0a0a0b8  bin/rg
b3:9f8e7d6c5b4a39281706f5e4d3c2b1a09f8e7d6c5b4a39281706f5e4d3c2b1a0  share/licenses/ripgrep/LICENSE-MIT
```

⛔ **Every shipped file appears exactly once.** The order is byte-sorted by
path so the file itself is reproducible.

⛔ **`CHECKSUMS` covers everything, including the log and the icon if they
ship.** The historical system's equivalent covered four of its fifteen files
and listed one of them twice; observed at
`ghcr.io/pkgforge/bincache/b3sum/official/b3sum` on 2026-09-02 and recorded in
[`../history/references/README.md`](../history/references/README.md). A
checksum manifest with holes gives a false sense of coverage, which is worse
than none.

⚠ **`CHECKSUMS` is not the security boundary.** It is inside the artefact, so
an attacker who can change the artefact can change it. The security boundary is
the signature over the *manifest digest*, which covers every layer's digest
including this one. `CHECKSUMS` exists so a user who unpacked a tree a year ago
can check it against local corruption without a network.

---

## 6. Archive format and normalisation

An artefact is published as layers in the registry, and is also exportable as a
single archive for offline transfer
([`../client/offline-and-airgap.md`](../client/offline-and-airgap.md)).

⛔ **When an archive is produced it MUST be normalised**, or two identical
builds produce different bytes:

| property | value | why |
| --- | --- | --- |
| format | POSIX `ustar`, or GNU where a path exceeds ustar's limit | |
| entry order | byte-sorted by path | ⛔ directory iteration order varies by filesystem |
| `mtime` | `SOURCE_DATE_EPOCH` | |
| `uid`, `gid` | `0` | |
| `uname`, `gname` | empty | ⚠ some tools default to the building user's name |
| mode | `0755` for ELF, `0644` otherwise, per §2 | |
| no extended attributes, no ACLs, no device nodes | | |
| compression | zstd, level 19, with no embedded timestamp | |

⚠ **A compressor's own header timestamp is the trap.** gzip stores an mtime in
its header, so two byte-identical tar streams compress to different bytes
unless it is pinned to zero. Anyone reproducing this must set it explicitly;
`experiments/30-oci-pipeline.sh` demonstrates the property end to end and
`build.py` in the studied system's build repository documents the same trap.

---

## 7. Size

⚠ **No hard ceiling is specified here, and that is deliberate.** Registry
limits vary and are the registry's to state;
[`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) records what was measured
for GHCR.

Two soft rules:

- A single layer **SHOULD NOT** exceed 2 GiB. Above that, resumable upload
  behaviour differs between registries and failures become hard to diagnose.
- A build producing an artefact more than 10 times the size of its previous
  revision **SHOULD** fail, via `[verify].max-size`. That growth almost always
  means a debug tree or a vendored dependency directory was shipped by
  accident.
