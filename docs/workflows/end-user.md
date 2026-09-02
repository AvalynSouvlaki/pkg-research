# end-user workflow

Installing, upgrading, diagnosing, and getting out of trouble.

⭐ **Written for someone who has never heard of OCI and does not want to.**

---

## 1. First five minutes

```sh
curl -fsSL https://example.org/opk/install.sh | sh
```

⚠ **Piping a script from the internet to a shell is exactly what this system
exists to make unnecessary**, and it is how almost every tool is installed. The
honest position: the installer is small, auditable, published with a checksum,
and ⭐ **the alternative is offered first**:

```sh
curl -fsSLO https://example.org/opk/opk-x86_64-linux
curl -fsSLO https://example.org/opk/opk-x86_64-linux.sha256
sha256sum -c opk-x86_64-linux.sha256
chmod +x opk-x86_64-linux && mv opk-x86_64-linux ~/.local/bin/opk
```

Then:

```sh
eval "$(opk env)"                # ⭐ adds opk's bin to PATH for this shell
echo 'eval "$(opk env)"' >> ~/.bashrc
opk install ripgrep
rg --version
```

⛔ **If `rg` is not found after install, the PATH line is missing.** The client
says so at install time, and this is the first thing to check.

---

## 2. Everyday

```sh
opk search json                  # find something
opk info jq                      # what is it, what versions, is it signed
opk install jq                   # install
opk list                         # what do I have
opk list --outdated              # what is behind
opk upgrade                      # upgrade everything
opk upgrade jq                   # or just one
opk remove jq                    # remove
```

⭐ **`opk install NAME` with no version installs the newest stable build for
your machine, verified.** Nothing else is required to use the system.

---

## 3. When something goes wrong

### 3.1 The command is not found after installing

```sh
opk which rg
eval "$(opk env)"
```

⭐ **The most common first-use problem, and it is a PATH problem, not an install
problem.**

### 3.2 An install was refused

```
opk: refusing to install ripgrep 14.1.1-1
  signature verification failed
```

⛔ **This is the system working.** Do not reach for a flag to make it go away.

```sh
opk verify ripgrep --explain     # ⭐ see exactly which step failed
```

| what `--explain` says | means |
| --- | --- |
| ⛔ index signature failed | ⚠ your key set is wrong, or the index is not genuine |
| ⛔ no signature among the referrers | ⚠ the package is genuinely unsigned; ask why before proceeding |
| ⛔ hash mismatch | ⛔ **stop.** The bytes are not what was published. Report it. |
| index too old | run `opk update` |

⛔ **A hash mismatch is never a client bug to work around.** It is the one
result worth reporting immediately.

### 3.3 There is no build for my machine

```sh
opk log ripgrep --failed --host riscv64-linux
```

⭐ **Tells you why, and usually offers a version that does work.**
[`../ci/error-reporting.md`](../ci/error-reporting.md) §5.

### 3.4 An upgrade broke something

```sh
opk rollback ripgrep             # ⭐ back to the previous version
opk list --versions ripgrep      # what is on disk
opk downgrade ripgrep@14.1.0-1   # a specific older version
```

⭐ **Rollback is instant if the previous version is still on disk**, which it is
unless `opk gc` removed it.

### 3.5 Everything is confused

```sh
opk doctor                       # ⭐ diagnose
opk fsck --repair                # rebuild state from the filesystem
```

⭐ **`opk doctor` checks PATH, prefix permissions, index freshness, the trusted
key set, disk space, and state against disk**, and prints what to do about each
finding.

---

## 4. Disk

```sh
opk gc --dry-run                 # ⭐ what would go
opk gc                           # apply the policy
opk clean                        # just the download cache
```

⚠ **`opk gc` can make a rollback need a download.** It says so and asks.

---

## 5. Trusting less, or more

```sh
opk trust list                   # whose signatures are accepted
opk config set trust-policy strict
```

| you want | policy |
| --- | --- |
| ⭐ the default: signed packages, verified | `default` |
| also require provenance | `strict` |
| ⚠ a mirror with no signing key | `hash-only` |

⛔ **There is no setting that turns off the hash check.** Under every policy,
the bytes are checked against what the index recorded.

---

## 6. Reproducing and inspecting

⭐ **Anyone can check the project's work**, and the commands are short:

```sh
opk provenance ripgrep           # how it was built
opk sbom ripgrep                 # what is in it
opk log ripgrep                  # ⭐ the build's own log
opk inspect ~/.local/share/opk/pkg/ripgrep/14.1.1-1/bin/rg
```

⭐ **`opk log` is unusual and worth knowing about.** It prints the log of the
build that produced the binary you are running, including the toolchain, the
source commit and every command.

---

## 7. Offline

```sh
opk install ripgrep --download-only --pin-cache   # ⭐ before you lose network
opk install ripgrep --offline                     # later
```

Across an air gap:

```sh
opk bundle create ripgrep fd bat -o tools.opkb    # outside
opk bundle verify tools.opkb                      # inside, ⭐ verify first
opk bundle install tools.opkb
```

[`../client/offline-and-airgap.md`](../client/offline-and-airgap.md).

---

## 8. Scripting

```sh
opk install ripgrep --json | jq -r '.results[0].digest'
opk list --json | jq -r '.results[] | select(.outdated) | .name'
```

⛔ **Exit codes are stable and specific.** A script can tell an untrusted index
from wrong bytes from an unsigned package.
[`../client/cli.md`](../client/cli.md) §4.

⭐ **For a reproducible environment, pin by digest:**

```sh
opk install ripgrep@sha256:d4311144c0b4d63b4e2f6e22e3286602a9f8508fe14a02822c9c0ba1e5f60b07
```

⭐ **That form bypasses resolution entirely and is immune to a compromised
index.** It is what a lockfile or a container build should use.

---

## 9. What this system will not do

⛔ **Stated so nobody plans around a capability that is not there.**

| | why |
| --- | --- |
| ⛔ install system services | ⚠ [`../client/hooks.md`](../client/hooks.md) §5 |
| ⛔ create users, set capabilities | same |
| ⛔ replace your distribution's package manager | ⚠ it distributes self-contained programs |
| ⛔ install libraries for other programs to link against | it distributes programs |
| ⛔ run anything at install time | ⭐ that is the point |
| ⛔ manage desktop applications well | ⚠ some work; toolkit-dependent ones do not |

⭐ **What it does do**: give you a current, verified, self-contained build of a
command-line tool, on any Linux, without root, with the build's own log one
command away.

---

## 10. Reporting a problem

| problem | where |
| --- | --- |
| ⛔ a hash mismatch | ⭐ report immediately; include `opk verify --explain` output |
| a package will not build for your architecture | ⭐ the prefilled link in the error message |
| a package is out of date | ⚠ usually the bot is behind; check for an open pull request first |
| the client crashed | ⭐ include `opk doctor` output and `OPK_LOG=debug` |
| ⚠ a package behaves badly | ⭐ that is upstream's tracker, not this one |

⛔ **Never include the output of a command run with a weakened trust policy as
evidence that something is wrong.** It is evidence that verification was off.
