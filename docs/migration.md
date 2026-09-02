# migration

Moving an existing package set onto this system, and moving off it.

---

## 1. From a shell-recipe system

⭐ **The concrete case this design was built from**: a tree of recipes carrying
build scripts, of the shape era 1 and era 2 of the studied system used.

### 1.1 Assess first

```sh
# How many recipes, and how many are already disabled?
find packages binaries -name '*.yaml' | wc -l
find packages binaries -name '*.disabled' | wc -l

# ⭐ Which build strategies, and which of them survive?
grep -rl 'cargo build'   packages binaries | wc -l
grep -rl 'go build'      packages binaries | wc -l
grep -rl 'nix-build'     packages binaries | wc -l
grep -rl './configure'   packages binaries | wc -l
```

⭐ **Do this before planning anything.** In the studied system's era 1 the
answer was 871 recipes with 385 disabled, and the disabled rate by strategy ran
from 3.1% for nix to 92% for hand-written C build systems. That distribution
decides the whole migration, because it says which packages will convert
mechanically and which will not.

### 1.2 The three groups

⛔ **Sort every package into one before converting anything.**

| group | test | how it converts |
| --- | --- | --- |
| ⭐ **A: pin it** | ⭐ upstream already publishes a static binary | ⭐ mechanical: a URL and a hash. No build. |
| **B: build it** | it needs building, and its build is one of the uniform strategies | ⭐ mostly mechanical; §1.3 |
| ⚠ **C: decide** | ⚠ a bespoke build, or already disabled | ⭐ **do not convert automatically** |

⭐ **Group A first, always.** It is the largest group in most sets, it is the
cheapest, and it produces a working system before any build infrastructure
exists.

⛔ **Group C is not a migration problem.** A recipe that was disabled with no
reason recorded should be re-proposed on its merits, not carried forward. Era 1
carried 385 of them and the reasons are gone.

### 1.3 Converting a group B recipe

| from | to |
| --- | --- |
| `pkg`, `description`, `license` | `[package]` |
| ⛔ `x_exec.pkgver` shell | ⭐ `[update].strategy`, one of the fixed set |
| `src_url` | `[source].git` plus a **commit**, not a tag |
| a `docker run` inside the script | ⭐ `[build].image`, digest-pinned |
| the rest of `x_exec.run` | `[build.script].run` |
| ⚠ implicit outputs | ⛔ ⭐ an explicit `[artifact]` map |
| `provides` | `[package].provides`, same operators |

⛔ **The two that are real work:**

**`x_exec.pkgver` to `[update]`.** An arbitrary shell pipeline becomes one of
six strategies. ⚠ Most convert directly; a few genuinely do not, and those
packages either get a new strategy added or pin their version manually with
`strategy = "static"`.

**Implicit outputs to an explicit map.** The old scripts copied whatever looked
like an executable out of a build tree, usually with `find ... file -i | grep
executable`. ⭐ The new form names each path. ⚠ Finding out what a build actually
produces means running it once with `--keep`.

### 1.4 Order

```
1. ⭐ convert group A, publish, get a working client and index
2. ⭐ stand up the builder; convert the ten most-used group B packages
3. convert the rest of group B, in dependency-free batches
4. ⚠ triage group C one at a time, on merit
5. ⛔ leave the old system serving until the new index has everything
```

⭐ **Step 1 produces a usable system in days rather than months**, and it is
the step that de-risks the rest: if the client, index and verification work for
pinned packages, the only remaining variable is the builder.

---

## 2. From a declarative pinning system

⚠ **The easier direction**: a tree of URL and hash pins, of the shape era 3
uses.

| from | to |
| --- | --- |
| `pkg.toml` identity | `[package]` |
| `[update]` | ⭐ `[update]`, nearly unchanged |
| `[source]` URL templating | `[source].url` plus `[arch]` |
| a version file's `[url]`, `[blake3]`, `[sha256]` per host | ⭐ the release file, same shape |
| `[source.install]` | `[artifact]` |
| ⛔ nothing | ⭐ **the build capability, which is what you came for** |

⭐ **The pins convert almost one to one.** What has to be added is the build
side, and only for packages that currently cannot exist.

⚠ **The trap is converting everything to built packages because you now can.**
A package upstream already publishes should stay pinned; building it is work
taken on forever for no gain. The studied system's build repository requires a
`reason` field for exactly this, and it is worth copying.

---

## 3. Registry migration

⭐ **Because the layout uses no registry-specific feature.**

```sh
oras cp --recursive \
  ghcr.io/old/opk/ripgrep/ripgrep:14.1.1-1-x86_64-linux \
  registry.new/opk/ripgrep/ripgrep:14.1.1-1-x86_64-linux
```

```
1. copy every manifest and blob, preserving digests
2. ⛔ copy the sha256-* fallback tags: a tool copying by tag does not see them
3. re-point the index's `registry` field
4. re-sign the index (⭐ package signatures are unaffected: they cover digests)
5. publish; clients pick it up on their next refresh
6. ⚠ keep the old registry serving through a deprecation window
```

⛔ **Step 2 is the one that gets missed**, and its symptom is that every package
appears unsigned on the new registry.

⭐ **Package signatures survive a move** because they cover manifest digests and
digests are preserved by the copy. That is the payoff for not signing tags.

⚠ **What does not survive**: download counts, GitHub Packages visibility
settings, and anything reading a hardcoded `ghcr.io`.

---

## 4. Client migration

⚠ **Users have the old system installed. Do not break them.**

| approach | trade |
| --- | --- |
| ⭐ install alongside, different prefix | ⭐ safe; the user chooses when to switch |
| ⚠ import the old installed set | convenient; ⛔ needs a mapping and it can be wrong |
| ⛔ replace in place | ⛔ do not |

```sh
opk migrate --from soar --dry-run     # ⭐ report only
```

⭐ **A migration command reports and does not act by default.** It lists what it
found, what it can map, and what it cannot, and the user runs it again to apply.

⚠ **Names will not all map.** A package called `foo` in one system may be
`foo-cli` here, or not exist. ⛔ The migration reports the unmapped set rather
than guessing, because a wrong guess installs different software under a name
the user trusts.

---

## 5. Migrating away

⭐ **Stated because a system you cannot leave is a system nobody should
adopt.**

| what you have | how to leave with it |
| --- | --- |
| ⭐ the package tree | ⭐ plain TOML in git; it is yours |
| ⭐ published artefacts | ordinary OCI artefacts; `oras cp` them anywhere |
| ⭐ signatures, SBOMs, provenance | standard formats, attached as referrers |
| the index | ⭐ plain JSON; regenerate it in any shape you like |
| ⚠ installed packages on a user's disk | ⭐ ordinary directories; `bin/` is symlinks |

⛔ **Nothing here is in a proprietary format**, and that is deliberate. The
lock-in a packaging system usually has is its index format and its artefact
layout; both are open here, and the artefacts are readable by tooling this
project does not control.

⚠ **The one thing that does not transfer is the trust root.** A user's trust in
your signing key does not carry to a successor project, and it should not.
