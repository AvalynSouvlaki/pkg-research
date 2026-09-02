# CLI specification

⭐ **Every command, flag, exit code and output format.** An implementation can
build the command surface from this file alone.

Behaviour is [`client-behaviour.md`](client-behaviour.md). This is the
**interface**.

---

## 1. Shape

```
opk [GLOBAL] <command> [ARGS] [FLAGS]
```

⭐ **Design rules, each with a reason.**

| rule | why |
| --- | --- |
| a verb the user would say | `install`, `remove`, `upgrade`, not `add`, `rm`, `up` |
| ⛔ every mutating command has `--dry-run` | a user must be able to see what will happen |
| ⛔ every command has a machine-readable output | ⭐ `--json` on all of them, not some |
| ⛔ no command is destructive without confirmation or a flag | |
| ⭐ an error names the fix | [`../security/trust-and-verification.md`](../security/trust-and-verification.md) §6 |
| the same flag means the same thing everywhere | ⚠ `-y` never means anything but "assume yes" |

---

## 2. Global flags

| flag | default | effect |
| --- | --- | --- |
| `--json` | off | machine-readable output on stdout, ⛔ diagnostics to stderr |
| `--quiet`, `-q` | off | errors only |
| `--verbose`, `-v` | off | repeatable; `-vv` adds request logging |
| `--yes`, `-y` | off | assume yes; ⛔ never implies a trust-policy relaxation |
| `--prefix PATH` | `$XDG_DATA_HOME/opk` | install root |
| `--system` | off | ⛔ system prefix; requires root; never implicit |
| `--trust-policy P` | `default` | [`../security/trust-and-verification.md`](../security/trust-and-verification.md) §3 |
| `--offline` | off | ⛔ fail rather than reach the network |
| `--host TRIPLE` | detected | ⚠ for downloading, not installing, another host's build |
| `--repository NAME` | all | restrict to one |
| `--no-color` | auto | also honours `NO_COLOR` |
| `--config PATH` | `$XDG_CONFIG_HOME/opk/config.toml` | |

⛔ **`--yes` does not weaken verification.** A flag that means "stop asking"
must not also mean "stop checking", and conflating them is how users end up
with verification off.

---

## 3. Commands

### 3.1 Package lifecycle

| command | does |
| --- | --- |
| `opk install NAME[@CONSTRAINT]...` | resolve, verify, install |
| `opk remove NAME...` | remove; `--purge` also removes config |
| `opk upgrade [NAME...]` | upgrade all, or the named |
| `opk downgrade NAME@VERSION` | install and activate an older version |
| `opk rollback NAME` | ⭐ return to the previously active version |
| `opk reinstall NAME` | re-fetch and re-verify at the same version |

**`install` flags**

| flag | effect |
| --- | --- |
| `--dry-run` | print the plan, change nothing |
| `--no-link` | install without linking into `bin/` |
| `--link-as NEW=OLD` | link under a different name |
| `--replace-link NAME` | take a conflicting link from its current owner |
| `--force` | reinstall even if the same version is present |
| `--allow-vulnerable` | ⛔ required when an advisory matches |
| `--allow-downgrade` | permit a lower version |
| `--strict-requires` | ⛔ fail rather than warn on an unmet `[runtime].requires` |

### 3.2 Discovery

| command | does |
| --- | --- |
| `opk search TERM` | search names, provides, aliases; `--description`, `--category`, `--provides` narrow it |
| `opk info NAME` | ⭐ everything known about a package |
| `opk list` | what is installed; `--outdated`, `--orphaned` |
| `opk files NAME` | the files a package installed |
| `opk which PROGRAM` | ⭐ which package owns a program on `PATH` |
| `opk why NAME` | ⭐ why this is installed: explicit, or a dependency of what |
| `opk versions NAME` | every published version for this host |

### 3.3 Verification and evidence

| command | does |
| --- | --- |
| ⭐ `opk verify [NAME]` | re-run the verification chain; `--explain` prints every step |
| `opk log NAME[@VERSION]` | ⭐ fetch and print the build log |
| `opk provenance NAME` | print the provenance attestation |
| `opk sbom NAME` | print the SBOM; `--format spdx\|cyclonedx` |
| `opk audit` | ⭐ list installed packages matched by an advisory |
| `opk trust list\|add\|remove\|show` | manage the trusted key set |

⭐ **`opk log` is the command that makes builds legible to users**, and it is
the direct descendant of the historical system's package pages linking to CI
logs. It works for a package that failed to build too:

```
$ opk log ripgrep --host riscv64-linux
ripgrep 14.1.1-1 riscv64-linux: BUILD FAILED 2026-09-01T10:04:11Z
  error: linking with `cc` failed: exit status: 1
  = note: /usr/bin/ld: cannot find -lz: No such file or directory
full log: ghcr.io/example/opk/ripgrep/ripgrep:14.1.1-1-riscv64-linux
```

### 3.4 Repositories and maintenance

| command | does |
| --- | --- |
| `opk repo add\|remove\|list\|update` | ⚠ `add` prints the key fingerprint and requires confirmation |
| `opk update` | refresh indexes |
| `opk gc` | ⭐ reclaim disk; `--keep N`, `--older-than DUR`, `--dry-run` |
| `opk clean` | clear the download cache |
| `opk fsck` | ⭐ check state against the filesystem; `--repair` |
| `opk doctor` | ⭐ diagnose a broken installation |

### 3.5 Authoring

| command | does |
| --- | --- |
| `opk new NAME --from URL` | scaffold a recipe |
| `opk validate [PATH]` | ⛔ validate without executing anything |
| `opk build NAME --host H` | build locally |
| `opk lint [PATH]` | style and correctness beyond schema validity |
| `opk publish` | push a built artefact |
| `opk resolve [NAME...]` | find newer upstream versions |
| `opk pin [NAME...]` | write release files with hashes |
| `opk inspect FILE` | ⭐ what is this artefact: `elfprobe` plus metadata |

### 3.6 Offline

| command | does |
| --- | --- |
| `opk bundle create NAME... -o FILE` | ⭐ a self-contained transfer bundle |
| `opk bundle install FILE` | install from one, verifying as usual |
| `opk bundle verify FILE` | check without installing |

---

## 4. Exit codes

⛔ **Stable. A script depends on these.**

| code | meaning |
| --- | --- |
| 0 | success |
| 1 | ⚠ a general error not covered below |
| 2 | usage error: bad flag, bad argument |
| 10 | ⭐ **no index available** and one is required |
| 11 | ⛔ **index verification failed**: signature, or freshness |
| 12 | ⛔ **resolution failed**: no such package, or none for this host |
| 13 | ⛔ **integrity failure**: a digest or hash did not match |
| 14 | ⛔ **signature verification failed** under the active policy |
| 15 | ⛔ **install failed**: unpack, path validation, disk |
| 16 | ⛔ **conflict**, and no resolution was given |
| 17 | network error after retries |
| 18 | ⛔ **rate limited**; `Retry-After` was honoured and the budget is spent |
| 19 | lock held by another process |
| 20 | ⛔ **an advisory matches** and `--allow-vulnerable` was not passed |
| 21 | ⚠ **validation failed** (`validate`, `lint`) |
| 22 | ⚠ **build failed** (`build`) |

⭐ **11, 13 and 14 are distinct on purpose.** "The index is not trustworthy",
"these bytes are wrong" and "nobody I trust approved this" are three different
situations for a user and for a script.

---

## 5. Output

### 5.1 Human

```
$ opk install ripgrep
  resolve   ripgrep 14.1.1-1 x86_64-linux            official
  verify    index ✅  digest ✅  hash ✅  signature ✅
  download  5.0 MiB ━━━━━━━━━━━━━━━━━━━━ 100%
  install   /home/u/.local/share/opk/pkg/ripgrep/14.1.1-1
  link      rg -> ripgrep 14.1.1-1

installed ripgrep 14.1.1-1
  ⚠ /home/u/.local/share/opk/bin is not on your PATH
    add it:  export PATH="$HOME/.local/share/opk/bin:$PATH"
```

⛔ **The PATH warning is not optional.** A first install that succeeds and
leaves the user unable to run the program is the most common possible
first-use failure, and it is entirely preventable.

⛔ **Progress goes to stderr.** A user piping stdout gets data, not spinners.

### 5.2 `--json`

⛔ **One JSON object on stdout. Nothing else on stdout, ever.**

```json
{
  "schemaVersion": 1,
  "command": "install",
  "status": "ok",
  "results": [
    { "name": "ripgrep", "version": "14.1.1", "revision": 1,
      "host": "x86_64-linux", "repository": "official",
      "digest": "sha256:d4311144...",
      "verified": { "index": true, "digest": true, "hash": true,
                    "signature": true, "provenance": true },
      "trust_policy": "default",
      "installed_to": "/home/u/.local/share/opk/pkg/ripgrep/14.1.1-1",
      "links": [ { "name": "rg", "path": "/home/u/.local/share/opk/bin/rg" } ] }
  ],
  "warnings": [
    { "code": "path_not_configured",
      "message": "/home/u/.local/share/opk/bin is not on PATH" }
  ]
}
```

⛔ **`verified` is an object, not a boolean.** "It was verified" is not one
fact, and a consumer under a strict policy needs to know which checks ran.

⛔ **Warnings carry a stable `code`.** A consumer matching on English message
text breaks the first time the wording improves.

---

## 6. Configuration

```toml
# $XDG_CONFIG_HOME/opk/config.toml
prefix       = "~/.local/share/opk"
trust-policy = "default"
channel      = "stable"
parallel     = 4
max-index-age = "14d"

[[repository]]
name     = "official"
url      = "ghcr.io/example/opk"
priority = 100

[mirror]
urls = ["https://mirror.example.net/opk"]
```

**Precedence**, lowest to highest: built-in defaults, system config, user
config, environment (`OPK_*`), command-line flags.

⛔ **A config file cannot set a trust policy weaker than the built-in default
without an explicit `allow-weak-trust = true` beside it.** Weakening security in
a file that is easy to copy from a forum post should require saying so twice.

---

## 7. Shell integration

```sh
opk completions bash > /etc/bash_completion.d/opk
opk completions zsh  > "${fpath[1]}/_opk"
opk completions fish > ~/.config/fish/completions/opk.fish
```

⭐ **Completions are generated from the same command table the parser uses**, so
they cannot drift.

```sh
eval "$(opk env)"        # emits PATH, MANPATH, and nothing else
```

⛔ **`opk env` emits only export lines and exits 0.** Anything that
`eval`s must be trivially auditable, and a user should be able to read its
entire output in one screen.

---

## 8. Environment variables

| variable | effect |
| --- | --- |
| `OPK_PREFIX`, `OPK_CONFIG`, `OPK_CACHE`, `OPK_STATE` | paths |
| `OPK_TRUST_POLICY` | ⚠ same restriction as the config file |
| `OPK_OFFLINE` | `1` implies `--offline` |
| `OPK_LOG` | `error`, `warn`, `info`, `debug`, `trace` |
| `NO_COLOR`, `TERM` | honoured |
| `SSL_CERT_FILE`, `SSL_CERT_DIR` | ⭐ honoured for the client's own TLS |
| `HTTPS_PROXY`, `NO_PROXY` | honoured |

⛔ **No environment variable disables hash verification.** There is no such
switch anywhere in the interface.
