# installation layout

Where files land, how user and system installs differ, and what makes the whole
tree relocatable.

---

## 1. The layout

```
<prefix>/
  bin/                        ⭐ symlinks; this is what goes on PATH
    rg -> ../pkg/ripgrep/14.1.1-1/bin/rg
  pkg/
    ripgrep/
      14.1.1-1/               ⭐ the unpacked artefact, immutable
        bin/rg
        share/man/man1/rg.1
        share/licenses/ripgrep/LICENSE-MIT
        .opk/metadata.json
        .opk/CHECKSUMS
      14.1.0-1/               ⭐ the previous version, kept for rollback
  etc/
    ripgrep/                  ⚠ user-editable; never overwritten
  share/
    man -> ../pkg-man/        aggregated symlink farm for MANPATH
    applications/             .desktop entries, linked
    icons/                    icons, linked
  cache/                      downloaded blobs, keyed by digest
  state/
    state.sqlite
    lock
  .staging/                   ⛔ transient; same filesystem as pkg/
```

⛔ **`pkg/<name>/<version>-<revision>/` is immutable after install.** Nothing
writes into it again. That is what makes `opk verify` meaningful and rollback a
symlink change.

⭐ **The version directory is the unit of install and removal.** Two versions
coexist without interacting, which is the property that makes upgrade and
rollback cheap.

---

## 2. User versus system

| | user | system |
| --- | --- | --- |
| prefix | ⭐ `$XDG_DATA_HOME/opk`, default `~/.local/share/opk` | `/opt/opk` |
| config | `$XDG_CONFIG_HOME/opk` | `/etc/opk` |
| cache | `$XDG_CACHE_HOME/opk` | `/var/cache/opk` |
| state | `$XDG_STATE_HOME/opk` | `/var/lib/opk` |
| root | ⭐ **no** | yes |
| ⭐ default | ⭐ **yes** | opt-in with `--system` |

⛔ **The default is user-scoped.** A package manager needing root to install a
command-line tool makes every package a potential system compromise, for no
benefit a static binary needs.

⚠ **`/opt/opk` rather than `/usr/local`.** `/usr/local` is shared with whatever
else the administrator installed, so a collision is possible and a removal could
take someone else's file. A dedicated prefix makes ownership unambiguous.

**Precedence when both exist**: ⭐ the user's `bin/` comes first on `PATH`, so a
user's own version shadows the system's. `opk which` says which is active and
why.

---

## 3. PATH

⛔ **The client does not edit the user's shell configuration.** It prints what
to add:

```
⚠ /home/u/.local/share/opk/bin is not on your PATH
  add to ~/.bashrc:  export PATH="$HOME/.local/share/opk/bin:$PATH"
  or:                eval "$(opk env)"
```

⚠ **Silently editing a dotfile is a change a user did not ask for and cannot
easily find.** Printing the line is slower and it is honest.

⭐ **The warning appears after every install that leaves a program
unreachable**, not only the first, because a user who missed it once will miss
it again.

---

## 4. Relocatability

⛔ **The whole prefix must be movable.** Every internal reference is relative.

| reference | form |
| --- | --- |
| ⭐ `bin/` symlinks | `../pkg/<name>/<ver>/bin/<prog>` |
| a program finding its own data | ⭐ resolved from `/proc/self/exe` |
| man pages | the client adds `<prefix>/share/man` to `MANPATH` |
| ⛔ anything absolute | ⛔ a build defect. [`../format/artifact-layout.md`](../format/artifact-layout.md) §4. |

⭐ **Moving a prefix is `mv` plus `opk fsck --repair`.** The move works
immediately because links are relative; `fsck` updates the recorded paths in
state.

⚠ **The cache is keyed by digest and is prefix-independent**, so it can be
shared between prefixes or moved separately.

---

## 5. Configuration files

⛔ **`etc/<name>/` is never overwritten by an upgrade.**

| case | behaviour |
| --- | --- |
| first install | defaults copied to `etc/<name>/` |
| upgrade, user did not modify it | ⭐ update in place, silently |
| ⚠ upgrade, user modified it | ⛔ write `<file>.new` beside it, ⭐ **and say so** |
| removal | ⚠ kept, unless `--purge` |

⚠ **"Say so" is load-bearing.** A `.new` file written with nothing printed is a
configuration change nobody applies, and the historical failure mode of every
package manager that does this quietly.

**Modification is detected** by comparing against the hash recorded at install,
not by mtime.

---

## 6. Desktop integration

⚠ **Optional and off by default for a command-line tool.**

```sh
opk install someapp --desktop        # link .desktop and icons
```

| linked to | from |
| --- | --- |
| `<prefix>/share/applications/` | the artefact's `share/applications/` |
| `<prefix>/share/icons/hicolor/.../` | its icons |

⛔ **The client does not run `update-desktop-database` or
`gtk-update-icon-cache` automatically.** They are host-level operations, they
may need privileges, and running host tooling on the user's behalf is exactly
the class of action `--desktop` should not imply. The client prints the command.

⚠ **`$XDG_DATA_HOME/opk/share` is not on the default `XDG_DATA_DIRS`**, so a
desktop environment will not see the entries until the user adds it. `opk env`
emits it.

---

## 7. Disk

| directory | growth | bounded by |
| --- | --- | --- |
| `pkg/` | one tree per installed version | ⭐ `opk gc`, [`delta-and-gc.md`](delta-and-gc.md) |
| `cache/` | one blob per downloaded layer | `opk clean`, and a size cap |
| `.staging/` | ⛔ transient | removed on success or failure |
| `state/` | small | |

⛔ **A failed install leaves nothing behind.** `.staging/` is removed on every
exit path, including a signal, and `opk fsck` sweeps anything a hard kill left.

⚠ **The cache is not automatically bounded by default**, and it should be. A
`cache.max-size` in the config, evicting least-recently-used blobs, is the
mechanism; the default is 5 GiB.

---

## 8. Permissions

| path | mode |
| --- | --- |
| directories | `0755` user, `0755` system |
| ELF files | `0755` |
| everything else | `0644` |
| `state/`, `cache/` | ⭐ `0700`: they record what a user installed |
| ⛔ setuid, setgid | ⛔ never; rejected at build and at unpack |

⛔ **The mode comes from content, not from the name.** A file whose first four
bytes are `\x7fELF` is executable; everything else is not.
[`../format/build-manifest.md`](../format/build-manifest.md) §6.

⚠ **`state/` at `0700` matters more than it looks on a shared machine**: the
list of what someone has installed, and its versions, is useful to an attacker
choosing which vulnerability to try.

---

## 9. Non-Linux

⚠ **Specified, not measured.** [`../compatibility.md`](../compatibility.md)
states what is unverified.

| platform | prefix | notes |
| --- | --- | --- |
| macOS | `~/Library/Application Support/opk` | ⚠ code signing and quarantine; see the compatibility page |
| Windows | `%LOCALAPPDATA%\opk` | ⛔ no symlinks without privilege; ⭐ use shim executables instead |
| FreeBSD | as Linux | |

⛔ **Windows has no usable symlink for unprivileged users**, so `bin/` holds
small shim executables rather than links. That is a real behavioural difference
and it changes what `opk which` reports.
