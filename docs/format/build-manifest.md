# build manifest

⭐ **The complete specification of `opk.toml`.** Every table, every field, its
type, whether it is required, its default, its validation rule, and what a
non-conformant value does.

An implementation can write the validator from this document alone. The tree
layout around the file is [`package-format.md`](package-format.md); identity
grammars are [`package-identity.md`](package-identity.md).

---

## 0. How to read this

Each field carries a **strength** and a **validation rule**.

| strength | meaning |
| --- | --- |
| **required** | absent means the recipe is invalid |
| **conditional** | required when the stated condition holds |
| **optional** | absent means the default applies |

⛔ **Validation is total and it happens before anything else.** A recipe that
fails any rule below is rejected whole. There is no partial acceptance, no
"warn and continue", and no field whose invalid value is silently replaced by
a default. The exit code and message format are in
[`../client/cli.md`](../client/cli.md).

⚠ **Unknown keys are an error, not a warning.** A typo'd key that is ignored is
a setting the author believes is in effect and is not. The studied system's
era 1 tree contains a package with the key `licensen`, observed at commit
`6f1cbb9`; it was silently ignored for the life of that package.

---

## 1. `[package]`

Identity and human-facing metadata.

| field | type | strength | default | validation |
| --- | --- | --- | --- | --- |
| `name` | string | **required** | | matches `^[a-z0-9][a-z0-9._+-]{0,63}$`. ⛔ Lowercase only: registry repository paths are case-insensitive on some registries and case-sensitive on others, so a mixed-case name is not portable. |
| `description` | string | **required** | | 1 to 200 characters, no newline. A description that is empty or equals the name is rejected. |
| `homepage` | array of string | optional | `[]` | each an absolute `http` or `https` URL |
| `license` | array of string | **required** | | each a valid SPDX identifier or expression, or the literal `"NOASSERTION"`. ⚠ `NOASSERTION` is accepted and surfaces a warning at install; it is not a way to skip the field. |
| `maintainer` | array of string | **required** | | at least one, each `Name <contact>` where contact is an email or URL |
| `provides` | array of string | optional | `[name]` | each matching the provides grammar in [`package-identity.md`](package-identity.md) |
| `category` | array of string | optional | `[]` | each a freedesktop main or additional category |
| `tag` | array of string | optional | `[]` | free-form search keywords, each 1 to 32 characters |
| `family` | string | optional | `name` | the directory name, when it differs from `name` |
| `channel` | string | optional | `"stable"` | one of `stable`, `beta`, `nightly`, `unstable` |
| `repology` | array of string | optional | `[]` | project names on repology.org, used only for cross-referencing |
| `note` | array of string | optional | `[]` | shown to the user at install |
| `portable` | bool | optional | `true` | ⛔ `false` requires `portable-reason` |
| `portable-reason` | string | conditional | | **required** when `portable = false`. Free text, shown at install. |
| `disabled` | bool | optional | `false` | ⛔ `true` requires `disabled-reason` |
| `disabled-reason` | string | conditional | | **required** when `disabled = true` |
| `src` | string | optional | derived | the true upstream, when `[update]` tracks a different repository |

⭐ **`portable = false` is how a package that cannot be statically linked
declares it**, rather than failing the build gate silently. The criteria for
when this is legitimate are in
[`../build/static-linking.md`](../build/static-linking.md) §when-not-to.

⚠ **`disabled` is a tombstone, not a delete.** A disabled package stays in the
tree with its reason, so the next person to propose it finds out why it is not
there. Era 1 carried 385 disabled files out of 871 with almost no reasons
recorded, and the information about why each was disabled is simply gone.

---

## 2. `[source]`

Where the code comes from. **MUST** contain exactly one of `git` or `url`.

### 2.1 Git source

| field | type | strength | validation |
| --- | --- | --- | --- |
| `git` | string | **required** | absolute `https` URL. ⛔ `git://` and `http://` are rejected: neither authenticates the server. |
| `commit` | string | **required** | exactly 40 or 64 lowercase hex characters. ⛔ A tag or branch name is rejected. |
| `submodules` | bool | optional, default `false` | when true, submodules are fetched at their recorded commits |
| `version` | string | optional | the human version this commit corresponds to. When absent, the release file supplies it. |

⛔ **The commit is verified after fetch.** The builder runs `git rev-parse HEAD`
and compares. A remote that serves different content for a ref is caught here,
not at install. [`../build/build-system.md`](../build/build-system.md) §fetch.

⚠ **A tag is not a pin.** A git tag can be moved and force-pushed. This is not
a hypothetical: it is why the field is named `commit` and why nothing accepts a
tag.

### 2.2 URL source

For repackaging an already-published artefact rather than compiling.

| field | type | strength | validation |
| --- | --- | --- | --- |
| `url` | string | **required** | absolute `https` URL. May contain `${version}`. |
| `sha256` | string | **required** | 64 lowercase hex characters |
| `version` | string | **required** | matches the version grammar |
| `epoch` | integer | **required** | Unix seconds, used as `SOURCE_DATE_EPOCH`. ⛔ Required here because there is no commit to take a date from, and taking it from the clock destroys reproducibility. |
| `strip-components` | integer | optional, default `0` | for archive extraction |

### 2.3 `[[patch]]`

Zero or more, applied in array order after fetch, before the script runs.

| field | type | strength | validation |
| --- | --- | --- | --- |
| `file` | string | **required** | path relative to the family directory, inside `patches/`. Validated by §9. |
| `sha256` | string | **required** | of the patch file, so a patch cannot be edited without the recipe changing |
| `strip` | integer | optional, default `1` | the `-p` level |

---

## 3. `[update]`

How to discover a newer upstream version. ⛔ **Read only by the update bot,
never by a client.**

| field | type | strength | validation |
| --- | --- | --- | --- |
| `strategy` | string | **required** | one of the strategies below |
| `repo` | string | conditional | `owner/name`, required for forge strategies |
| `tag-prefix` | string | optional, default `""` | for a repository publishing releases for several packages |
| `strip-prefix` | string | optional, default `""` | removed from the discovered version, commonly `"v"` |
| `pattern` | string | conditional | a regular expression with exactly one capture group, required for `html-regex` |
| `url` | string | conditional | required for `html-regex` |
| `include-prerelease` | bool | optional, default `false` | |
| `ignore` | array of string | optional, default `[]` | versions never to propose, each a literal or a `^`-anchored regular expression |

**Strategies.** ⛔ A closed set. Adding one is a change to the update bot, not
to a recipe.

| strategy | reads |
| --- | --- |
| `github-releases` | the releases API of `repo` |
| `github-tags` | the tags API of `repo` |
| `gitlab-tags` | the tags API of `repo` on gitlab.com |
| `git-tags` | `git ls-remote --tags` against `[source].git` |
| `html-regex` | `url`, matching `pattern` |
| `static` | never proposes an update. For a package pinned deliberately. |

⚠ **`html-regex` is the escape hatch and it is the one that breaks.** The
pattern runs against a page whose author owes you nothing. A recipe using it
**SHOULD** carry a `note` naming what to check when it stops working. Regular
expressions are matched with a total time limit and a bounded input size;
[`../ci/update-automation.md`](../ci/update-automation.md) states both.

⛔ **A discovered version is validated against the version grammar before it is
used anywhere.** This is the direct countermeasure to the `445.3p3` corruption
described in [`../principles.md`](../principles.md) §1. A version that fails the
grammar produces a build failure and an alert, never a published package.

---

## 4. `[build]`

| field | type | strength | default | validation |
| --- | --- | --- | --- | --- |
| `image` | string | **required** | | ⛔ **MUST** be digest-pinned: `<ref>@sha256:<64 hex>`. A tag is rejected. |
| `hosts` | array of string | **required** | | each a valid host triple, at least one, no duplicates |
| `deps` | array of string | optional | `[]` | package names installed in the container before the script |
| `deps_via` | string | optional | `"apk"` | one of `apk`, `apt`, `dnf`, `none` |
| `network` | string | optional | `"restricted"` | one of `none`, `restricted`, `full`. See §4.2. |
| `timeout` | integer | optional | `3600` | seconds, 60 to 43200 |
| `memory` | string | optional | `"4G"` | a size the runtime accepts |

⛔ **The image digest pin is the load-bearing one.** A build against
`rust:latest` measures a different toolchain every week and says so nowhere.
[`../build/build-environments.md`](../build/build-environments.md) explains
how to obtain and refresh a digest.

⚠ **`deps` is the known reproducibility gap and it is documented, not hidden.**
Packages installed by `apk` or `apt` at build time are not version-pinned by
those tools, so a distribution update can change the output.
[`../build/reproducibility.md`](../build/reproducibility.md) §gaps states the
consequence and the two ways to close it.

### 4.1 `[build.target]`, `[build.env]`, `[build.script]`

| table | shape | notes |
| --- | --- | --- |
| `[build.target]` | host triple → target triple | **required** when the toolchain needs one. Every host in `hosts` **MUST** have an entry, or none may. |
| `[build.env]` | name → value | extra environment. ⛔ A name colliding with a reserved variable (§4.3) is rejected. |
| `[build.script].run` | string | **required**. The shell script, run with `sh -euc`. |
| `[build.script].<host>` | string | optional. Replaces `run` entirely for that host. |

⚠ **A per-host script replaces, it does not append.** Naming a host and
expecting the common script to run first is the mistake this note exists to
prevent.

### 4.2 Network policy

| value | the build container gets |
| --- | --- |
| `none` | ⭐ no network at all. The strongest guarantee, and correct when every input is vendored. |
| `restricted` | **default.** Access to an allowlist of package and module registries, stated in [`../build/build-environments.md`](../build/build-environments.md). |
| `full` | unrestricted egress. ⛔ Requires `network-reason`, and the resulting artefact is marked `hermetic = false` in its provenance. |

⚠ **`restricted` is not hermetic and the design does not claim it is.** A crate
or module fetched through it is pinned by the ecosystem's own lockfile if the
ecosystem has one, and not at all if it does not.
[`../build/reproducibility.md`](../build/reproducibility.md) is explicit about
which ecosystems fall on which side.

### 4.3 Reserved environment variables

⛔ Set by the builder. A `[build.env]` entry using one of these names is
rejected, because silently losing to the builder is worse than failing.

| variable | value |
| --- | --- |
| `TARGET` | the target triple for this host |
| `HOST` | the host triple |
| `PREFIX` | the install prefix the artefact is built for, always `/opk` |
| `SOURCE_DATE_EPOCH` | the source commit's timestamp, or `[source].epoch` |
| `LC_ALL`, `LANG` | `C` |
| `TZ` | `UTC` |
| `TMPDIR` | a fixed path inside the container |
| `OPK_VERSION`, `OPK_REVISION`, `OPK_NAME` | from identity |

---

## 5. `[verify]`

Checks run on the produced artefact before it can be published. All are in
addition to the mandatory ones in
[`../build/build-system.md`](../build/build-system.md) §verify.

| field | type | strength | default | meaning |
| --- | --- | --- | --- | --- |
| `run` | array of string | optional | none | arguments to invoke each produced executable with. Non-zero exit fails the build. |
| `expect-output` | string | optional | none | a regular expression the invocation's combined output must match |
| `allow-dynamic` | array of string | optional | `[]` | artefact paths permitted to have a `PT_INTERP`. ⛔ Non-empty requires `[package].portable = false`. |
| `min-size` | integer | optional | `1` | bytes; catches a build that produced an empty file |
| `max-size` | integer | optional | none | bytes; catches a build that accidentally shipped a debug tree |

⭐ **`run` is opt-in because not every binary has a harmless flag.** A tool
whose only argument-free behaviour is to modify the filesystem must not be
invoked, and forcing a smoke test on every package would make that the default.

---

## 6. `[artifact]`

⛔ **The map from paths in the build tree to paths in the published artefact.
This, and nothing else, decides what is published.**

```toml
[artifact]
"target/${target}/release/rg" = "bin/rg"
"LICENSE-MIT"                 = "share/licenses/ripgrep/LICENSE-MIT"
```

| rule | |
| --- | --- |
| **required** | at least one entry |
| key | a path relative to the build tree root. May contain `${target}`, `${version}`, `${revision}`, `${arch}`. |
| value | a path relative to the artefact root. Same substitutions. |
| **MUST** | every key resolve to a regular file that exists after the script runs. A missing key fails the build, naming the key. |
| **MUST NOT** | any value escape the artefact root. §9. |
| **MUST NOT** | two keys map to the same value |

**Per-host override.** `[artifact.<host>]` replaces the shared map for that
host entirely, for the case where one architecture is laid out differently.

⭐ **File mode is decided by content, not by name.** A file whose first four
bytes are `\x7fELF` is published mode `0755`; everything else `0644`. A build
producing a binary under an unexpected name is still executable, and a
data file named `bin/something` is still not.

⚠ **The `bin/` convention matters to the client.** Anything published under
`bin/` is linked into the user's `PATH`;
[`../client/installation-layout.md`](../client/installation-layout.md) states
the full mapping. A file placed there that is not meant to be run is a
usability defect the validator cannot catch.

---

## 7. `[[tool]]` and `[[extra]]`

Additional pinned inputs. Both are build inputs and both are hashed.

```toml
[[tool]]
name   = "some-linker"
url    = "https://example.org/releases/1.2.3/some-linker-x86_64"
sha256 = "..."

[[extra]]
url    = "https://raw.githubusercontent.com/example/proj/v1.2.3/LICENSE"
sha256 = "..."
to     = "share/licenses/proj/LICENSE"
```

| | `[[tool]]` | `[[extra]]` |
| --- | --- | --- |
| purpose | an executable the script needs | a file the artefact must ship |
| placed | on `PATH` inside the container | into the artefact at `to` |
| required fields | `name`, `url`, `sha256` | `url`, `sha256`, `to` |

⚠ **`[[extra]]` is for the URL-source case.** A git source already contains its
licence at the pinned commit, and fetching it separately adds a fetch that can
fail for no benefit.

⚠ **A hash on a licence file is about determinism, not secrecy.** Most licence
URLs point at a branch, so their content can change with no release. Unpinned
bytes would change the artefact's hash and break the reproducibility check for
a reason nobody could see in the recipe.

---

## 8. Substitution

⛔ **Textual, four variables, no expressions, no functions, no nesting.**

| variable | expands to | available in |
| --- | --- | --- |
| `${version}` | the version being built | `[source].url`, `[artifact]`, `[[extra]].url` |
| `${revision}` | the revision | `[artifact]` |
| `${arch}` | the architecture part of the host triple, after `[arch]` mapping if present | `[source].url`, `[artifact]`, `[[extra]].url` |
| `${target}` | the target triple for this host | `[artifact]`, `[build.env]` values |

An optional `[arch]` table maps this system's architecture names to whatever
upstream calls them:

```toml
[arch]
x86_64  = "amd64"
aarch64 = "arm64"
```

⛔ **An unknown `${...}` is an error, not a literal.** Passing `${verison}`
through unchanged produces a URL that 404s at build time and a filename with a
brace in it, and the author sees neither until much later.

---

## 9. Path validation

⛔ **Every path in a recipe is validated before it is used as a filesystem or
shell operand.** A path failing any rule rejects the recipe.

A valid path:

1. is relative. A leading `/` is rejected.
2. contains no `..` component, before or after substitution.
3. contains no NUL byte, newline, or byte below 0x20.
4. is not absolute after symlink resolution during collection.
5. is at most 255 bytes per component and 4096 bytes total.
6. does not begin with `-`, which some tools read as an option.

⚠ **Rule 2 is checked after substitution as well as before.** A key of
`out/${target}/bin` with a `[build.target]` entry of `../../etc` passes a
pre-substitution check and escapes.

⚠ **Rule 4 needs an implementation note.** The builder collects declared
artefacts by opening each path with symlinks not followed for the final
component, then verifying the resolved real path is inside the build tree. A
build script that replaces `target/release/rg` with a symlink to `/etc/shadow`
is caught here.

---

## 10. Complete field reference

Every table, so an implementation can check it has covered them all.

| table | required | repeats | section |
| --- | --- | --- | --- |
| `[package]` | yes | no | §1 |
| `[source]` | yes | no | §2 |
| `[[patch]]` | no | yes | §2.3 |
| `[update]` | yes | no | §3 |
| `[build]` | yes | no | §4 |
| `[build.target]` | conditional | no | §4.1 |
| `[build.env]` | no | no | §4.1 |
| `[build.script]` | yes | no | §4.1 |
| `[verify]` | no | no | §5 |
| `[artifact]` | yes | no | §6 |
| `[artifact.<host>]` | no | per host | §6 |
| `[[tool]]` | no | yes | §7 |
| `[[extra]]` | no | yes | §7 |
| `[arch]` | no | no | §8 |

---

## 11. Validation error format

⛔ **An error names the file, the line, the key, what was expected and what was
found.** In that order, on one line, so it is greppable.

```
packages/ripgrep/opk.toml:14: [build].image: expected a digest-pinned
  reference matching <ref>@sha256:<64 hex>, found "rust:latest"
```

⚠ **Never report only the first error.** An author fixing one field at a time
across five CI runs is a workflow nobody tolerates. The validator collects all
errors and reports them together, and
[`../client/cli.md`](../client/cli.md) specifies the exit code.
