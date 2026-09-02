# client behaviour

⭐ **What the user's machine does.** Resolution, verification, install, upgrade,
downgrade, rollback, conflicts and removal, with the invariant each holds.

The command surface is [`cli.md`](cli.md). Where files land is
[`installation-layout.md`](installation-layout.md). The verification chain is
[`../security/trust-and-verification.md`](../security/trust-and-verification.md).
This document is the **behaviour**.

---

## 1. Resolution

`opk install NAME[@CONSTRAINT]`

```
1. parse NAME into [repository/]name[@constraint]
2. gather candidates from every configured repository
3. filter by host compatibility
4. filter by constraint
5. filter by channel
6. rank
7. ⛔ if more than one repository supplies a top candidate, REPORT, do not choose
8. resolve to a release coordinate, then to a digest
```

### 1.1 Constraints

| form | means |
| --- | --- |
| `ripgrep` | the newest on the default channel |
| `ripgrep@14.1.1` | that version, newest revision |
| `ripgrep@14.1.1-2` | ⭐ exactly that release |
| `ripgrep@^14.1` | ⚠ `>=14.1.0, <15.0.0` |
| `ripgrep@~14.1.1` | `>=14.1.1, <14.2.0` |
| `ripgrep@sha256:d431...` | ⭐ **that exact digest.** The strongest pin. |
| `official/ripgrep` | from that repository only |

⭐ **Digest pinning is what a lockfile or a reproducible script uses.** It
bypasses resolution entirely and is the only form immune to a compromised
index.

### 1.2 Host compatibility

| check | failure |
| --- | --- |
| architecture matches | exit 12, listing the hosts that do exist |
| ⭐ microarchitecture level is supported by this CPU | falls back to a lower level |
| `min_kernel` satisfied | ⛔ refuse, naming the required version |
| `[runtime].requires` present | ⚠ warn, unless `--strict-requires` |

⭐ **Microarchitecture fallback is automatic and silent on success.** A machine
supporting `x86_64-v3` prefers that build and takes the baseline when there is
none. ⛔ It never selects a level the CPU does not support.

⚠ **Detection reads `/proc/cpuinfo` flags or `CPUID` directly.** It does not
trust an environment variable, and `--host` overrides it only for downloading
without installing.

### 1.3 Priority and ambiguity

```toml
[[repository]]
name     = "official"
url      = "ghcr.io/example/opk"
priority = 100

[[repository]]
name     = "internal"
url      = "registry.corp.example/opk"
priority = 200          # ⭐ higher wins
exclusive = ["corp-*"]  # ⛔ these names resolve ONLY here
```

⛔ **Ambiguity is reported, never resolved by version.** If two repositories of
equal priority both supply `ripgrep`, the client stops and asks:

```
opk: 'ripgrep' is available from more than one repository

  official/ripgrep  14.1.1-1   (priority 100)
  community/ripgrep 14.2.0-1   (priority 100)

  Choose one:  opk install official/ripgrep
  Or set a priority in ~/.config/opk/config.toml
```

⭐ **Preferring the higher version here is exactly the dependency-confusion
attack**, per
[`../security/supply-chain.md`](../security/supply-chain.md) §2. The design
refuses.

---

## 2. Install

The verified sequence is
[`../security/trust-and-verification.md`](../security/trust-and-verification.md)
§2. The filesystem side:

```
1. stage into <prefix>/.staging/<name>-<version>-<revision>.<random>/
   ⛔ on the SAME filesystem as the target, so the rename is atomic
2. unpack, validating every path
3. verify declared provides paths exist
4. verify CHECKSUMS
5. fsync the staged tree
6. atomic rename to <prefix>/pkg/<name>/<version>-<revision>/
7. update the symlink farm
8. fsync the parent directory
```

⛔ **Nothing is executable before step 6.** ⛔ **The staging directory is
removed on any failure**, including a signal.

⚠ **Step 1's "same filesystem" is not pedantry.** `rename(2)` across
filesystems fails with `EXDEV`, and a client that falls back to copy-then-delete
has lost atomicity precisely when it matters.

⚠ **Step 8 is the one that gets skipped.** Without an `fsync` on the parent
directory, a crash after the rename can leave the directory entry absent on some
filesystems, so the package is installed and invisible.

### 2.1 Symlinks

For each `provides` entry, a symlink in `<prefix>/bin/`:

```
bin/rg -> ../pkg/ripgrep/14.1.1-1/bin/rg
```

⛔ **Relative, so the whole prefix relocates.** ⛔ **Created with an atomic
replace**: create at a temporary name, then `rename` over the target. A
`unlink` followed by `symlink` leaves a window where the command does not
exist.

---

## 3. Conflicts

Two packages providing the same program name.

⛔ **Detected before staging, and never resolved silently.**

```
opk: 'neovim' provides 'vi', which is already provided by 'vim'

  keep vim's:      opk install neovim --no-link vi
  take neovim's:   opk install neovim --replace-link vi
  install both:    opk install neovim --link-as nvi=vi
```

| state | meaning |
| --- | --- |
| both installed, one linked | ⭐ the normal resolution |
| both installed, neither linked | possible; the user invokes by full path |
| ⛔ two packages owning one symlink | ⛔ impossible; the client tracks the owner |

⭐ **The link owner is recorded in the client's state**, so removing the owning
package can offer to hand the link to the other package that provides it, rather
than leaving a dangling symlink.

---

## 4. Upgrade

```
opk upgrade [NAME...]
```

```
for each: resolve the newest satisfying the recorded constraint
          ⛔ skip if it is not greater than what is installed
          install the new version alongside the old
          ⭐ atomically repoint the symlinks
          ⛔ the old version stays INSTALLED, for rollback
```

⛔ **An upgrade is not an uninstall followed by an install.** The old version
stays on disk until garbage collection, which is what makes rollback a symlink
change rather than a download.
[`../architecture.md`](../architecture.md) §6.2.

| rule | |
| --- | --- |
| ⛔ never crosses an epoch boundary without `--allow-epoch-change` | an epoch change is a repackaging, and it deserves a human |
| ⛔ never downgrades | `opk downgrade` is a separate verb |
| ⚠ `etc/` is never overwritten | new defaults land as `.new` beside the existing file |
| a failed upgrade leaves the old version active | ⭐ staging means there is no half-upgraded state |

⚠ **The `.new` convention needs the client to tell the user.** A config default
that changed and was written beside the old one, with nothing said, is a change
nobody applies.

---

## 5. Downgrade and rollback

| verb | means |
| --- | --- |
| ⭐ `opk rollback NAME` | return to the previously active version. ⭐ A symlink change if it is still on disk. |
| `opk downgrade NAME@VERSION` | install and activate an older version, downloading if needed |

⛔ **Rollback does not delete the version it rolled back from.** A user who
rolls back and then forward again should not download twice.

⚠ **Rollback fails cleanly when the previous version has been collected**, and
says so, offering the `downgrade` form that will fetch it:

```
opk: cannot roll back ripgrep: 14.1.0-1 is no longer on disk
     it was removed by garbage collection on 2026-08-15
     to fetch it again:  opk downgrade ripgrep@14.1.0-1
```

---

## 6. Removal

```
opk remove NAME [--purge]
```

```
1. remove the symlinks this package owns
   ⭐ offer to hand each to another installed package that provides it
2. remove the version directory
3. ⚠ keep <prefix>/etc/<name>/ unless --purge
4. update state
```

⛔ **Removal never touches another package's files.** The symlink owner map is
what makes that checkable.

---

## 7. State

```
$XDG_STATE_HOME/opk/state.sqlite
```

| table | holds |
| --- | --- |
| `installed` | name, version, revision, host, digest, install time, the requested constraint |
| `links` | link path, owning package, target |
| `repositories` | configured repositories and their last index digest |
| `history` | ⭐ every install, upgrade, rollback and removal, with what was verified |

⛔ **State is a cache of the filesystem, not the source of truth.** The
filesystem is authoritative, and `opk fsck` rebuilds state from it. A client
that trusts a stale database over the disk reports packages that are not there.

⭐ **`history` is what makes `opk rollback` and incident response possible**, and
it records the trust policy in force for each operation, so "was this installed
with verification on" is answerable.

⚠ **Writes are transactional and the database is opened with WAL.** A crash
mid-install must not corrupt state, and the recovery path is
`opk fsck --repair`.

---

## 8. Concurrency

⛔ **One writer.** A lock file in the state directory, held for the duration of
a mutating operation.

| | |
| --- | --- |
| a second mutating command | ⚠ waits, printing what it is waiting for and the holder's pid |
| ⭐ read-only commands | ⭐ never block |
| ⛔ a stale lock from a killed process | detected by liveness of the recorded pid, then broken with a warning |

⚠ **A lock with no liveness check leaves a user stuck after a crash**, and the
usual workaround they find on the internet is to delete the lock file, which is
worse than the client doing it deliberately.

---

## 9. Offline and degraded operation

| condition | behaviour |
| --- | --- |
| no network, package cached | ⭐ install from cache, verifying as usual |
| no network, index cached and fresh enough | ⭐ resolve from cache, warn about staleness |
| no network, index too old | ⚠ warn loudly; ⛔ still verify |
| the registry returns 5xx | retry with backoff, then try mirrors in order |
| a mirror lacks a blob | ⭐ fall back to the primary rather than failing |
| ⛔ rate limited | ⛔ honour `Retry-After`; do not spin. [`../ops/rate-limits.md`](../ops/rate-limits.md) |

⛔ **No degraded mode ever skips hash verification.** Offline changes where
bytes come from, never whether they are checked.
