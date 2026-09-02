# variants, features and profiles

Three related mechanisms, often confused, with different lifetimes and
different owners.

| mechanism | decided at | by | produces |
| --- | --- | --- | --- |
| **feature** | build time | the recipe author | different bytes |
| **variant** | build time | the recipe author | a separately named package |
| **profile** | build time | the operator of the build system | different bytes, across all packages |

⛔ **None of the three is decided by the user at install time.** A user
installs prebuilt bytes; they do not compile. A system that lets a user pick
features at install is a source-based package manager, which is a different
design with different costs.

---

## 1. Features

A feature is a named build option inside one recipe.

```toml
[features]
default = ["zlib"]

[features.zlib]
description = "compressed archive support"
env         = { WITH_ZLIB = "1" }
deps        = ["zlib-static"]

[features.jemalloc]
description = "use jemalloc as the allocator"
env         = { WITH_JEMALLOC = "1" }
```

| field | type | meaning |
| --- | --- | --- |
| `default` | array of string | features enabled when nothing says otherwise |
| `<name>.description` | string | **required**, shown to a human |
| `<name>.env` | table | environment added for this build |
| `<name>.deps` | array of string | appended to `[build].deps` |
| `<name>.conflicts` | array of string | features that cannot be combined |

⛔ **The feature set used is recorded in the metadata and in the artefact
identity.** Two builds of one version with different features are different
artefacts and **MUST NOT** share a release coordinate.

**How they differ in the tag.** A non-default feature set appends a normalised
suffix:

```
1.2.3-1-x86_64-linux                    default features
1.2.3-1-x86_64-linux+jemalloc           one non-default feature
1.2.3-1-x86_64-linux+jemalloc.nozlib    ⚠ becomes long quickly
```

⚠ **Feature suffixes in tags get out of hand fast.** More than two non-default
combinations for one package is a signal that these should be variants (§2)
with real names, not a combinatorial explosion nobody can read. The validator
warns above two published feature combinations per package and refuses above
eight.

---

## 2. Variants

A variant is a separate package that builds the same upstream software
differently, with a name a human chose.

```
packages/
  ffmpeg/       name = "ffmpeg"       minimal, permissively licensed codecs
  ffmpeg-full/  name = "ffmpeg-full"  everything, including non-free
```

**MUST**: each variant is a separate family directory with a distinct `name`.

**SHOULD**: each variant declares `variant-of` in `[package]`, so the client
can tell a user that the thing they searched for exists in another form.

```toml
[package]
name       = "ffmpeg-full"
variant-of = "ffmpeg"
note       = ["Includes non-free codecs. Check your local licensing position."]
```

### Feature or variant?

| use a **feature** when | use a **variant** when |
| --- | --- |
| the difference is one build flag | the difference is licensing, size class, or intent |
| users would not search for it by name | ⭐ a user would type the variant's name |
| there are at most two combinations | there are several, or they are mutually exclusive |
| the packages are interchangeable | installing both at once is meaningful |

⚠ **Era 1 of the studied system encoded variants in filenames**:
`static.nixpkgs.stable.yaml` beside `static.official.source.yaml` in one
directory, with the precedence rule implicit in the name. Every consumer had to
reimplement that parsing, and the metadata carries a `pkg_id` field
(`nixpkgs.bash` against `github.com.BLAKE3-team.BLAKE3`) whose job is to
disambiguate what the filename made ambiguous. Distinct names remove the
problem rather than encoding it.

---

## 3. Profiles

A profile is a named set of build settings applied across every package by the
build system operator, not by a recipe.

| profile | intent | typical effect |
| --- | --- | --- |
| `release` | ⭐ the default. Optimised, stripped, no debug info. | `-O2`, strip, no `.debug_*` |
| `size` | smallest artefact | `-Os` or `opt-level="z"`, LTO, strip |
| `debug` | diagnosable | `-Og`, symbols kept, ⚠ never published to `stable` |
| `hardened` | maximum mitigations | see §3.1 |

⛔ **A profile never changes what a package *does*, only how it is compiled.**
A profile that enabled a feature would make two artefacts with the same
identity behave differently, which breaks the identity model.

**Recipes MAY read the profile** through `$OPK_PROFILE` and **MUST** work
under `release` with no reference to it at all. A recipe that only builds under
one profile is rejected.

### 3.1 The `hardened` profile

| flag | effect | cost |
| --- | --- | --- |
| `-D_FORTIFY_SOURCE=3` | bounds-checked string and memory functions | small |
| `-fstack-protector-strong` | stack canaries | ~1% |
| `-fstack-clash-protection` | large-allocation probing | small |
| `-fcf-protection=full` | Intel CET indirect-branch tracking | small |
| `-Wl,-z,relro,-z,now` | read-only relocations, eager binding | startup only |
| `-fPIE -pie` or `-static-pie` | address-space layout randomisation | ⚠ see below |

⚠ **A plain `-static` binary is NOT position independent, so it does not get
ASLR.** This is the single most commonly missed security property of static
linking. `-static-pie` restores it. Measured on the probe host: `gcc -static`
produced an `ET_EXEC` binary of 785,360 bytes, `gcc -static-pie` produced an
`ET_DYN` binary of 822,552 bytes, both with no `PT_INTERP`. The 4.7% size cost
buys ASLR back.

⛔ **`-static-pie` support is not universal**, and where it is unavailable the
package **MUST** record `pie = false` in its metadata rather than silently
shipping a fixed-address binary.
[`../build/static-linking.md`](../build/static-linking.md) §pie has the
per-toolchain support table.

---

## 4. How the three compose

```
  profile   (operator, whole repository)
     +
  variant   (author, separate package name)
     +
  features  (author, within one recipe)
     =
  one artefact, one identity, one digest
```

⛔ **All three are recorded in the metadata**, under `build.profile`,
`package.variant-of` and `build.features`. An artefact whose metadata does not
say how it was configured cannot be reproduced, and reproduction is the check
everything else rests on.
