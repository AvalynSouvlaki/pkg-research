# Shell and scripting languages

**documented**. Covers shell, awk, sed and small interpreted tools, and the
question they all share: what does "install this script" mean when the
interpreter may not be there.

---

## 1. Fully static: the wrong question

⛔ **A script is not compiled, so there is nothing to link.** The portability
question moves to the interpreter and to every external command the script
invokes.

⭐ **A shell script has TWO dependency sets, and the second is the one that
breaks.**

| set | example | how it is handled |
| --- | --- | --- |
| the interpreter | `/bin/sh`, `/usr/bin/env bash` | §2 |
| ⭐ **every command it runs** | `jq`, `curl`, `awk`, `sed`, `grep` | §3 |

⚠ **The second set is invisible in the source.** A script works on the author's
machine and fails on a minimal host with `jq: not found`, and nothing in the
package declared that dependency.

## 2. The interpreter

| approach | verdict |
| --- | --- |
| ⚠ rely on `/bin/sh` | ⭐ acceptable for POSIX `sh`; present on every Unix |
| ⚠ rely on `bash` | ⛔ **not** present everywhere: not on Alpine by default, not on some minimal images |
| ⭐ ship a static interpreter and rewrite the shebang | ⭐ **the supported path for anything beyond POSIX sh** |

⛔ **`#!/usr/bin/env bash` is not a portability fix.** It finds bash on
`PATH` if bash exists. On a host with no bash it fails identically to a
hardcoded path, with a marginally better message.

⭐ **Shipping the interpreter:**

```toml
[package]
name     = "mytool"
provides = ["mytool"]

[build.script]
run = """
install -Dm0755 src/mytool.sh out/libexec/mytool/mytool.sh
install -Dm0755 "$(command -v bash)" out/libexec/mytool/bash
cat > out/bin/mytool <<'LAUNCH'
#!/bin/sh
d="$(cd "$(dirname "$(readlink -f "$0")")/../libexec/mytool" && pwd)"
exec "$d/bash" "$d/mytool.sh" "$@"
LAUNCH
chmod 0755 out/bin/mytool
"""

[artifact]
"out/bin/mytool"                  = "bin/mytool"
"out/libexec/mytool/bash"         = "libexec/mytool/bash"
"out/libexec/mytool/mytool.sh"    = "libexec/mytool/mytool.sh"
```

⭐ **The launcher is POSIX `sh`, which is always present**, and it resolves its
own directory so the artefact stays relocatable.

⚠ **`readlink -f` is not POSIX and is absent on some BSDs.** For Linux-only
packages it is fine; a portable launcher needs a loop resolving symlinks by
hand.

## 3. The commands a script runs

⛔ **A script package MUST declare what it invokes**, and there are three ways
to satisfy it:

| # | approach | trade |
| --- | --- | --- |
| 1 | ⭐ restrict to a POSIX baseline | ⭐ no dependencies; ⚠ limits what the script can do |
| 2 | ⭐ ship the tools it needs in `libexec/` and prepend to `PATH` | self-contained; larger |
| 3 | declare them in `[runtime].requires` and fail loudly if absent | ⚠ smallest; the failure is the user's problem |

⭐ **Approach 2 with `busybox` is unusually effective for shell tooling.** One
static binary provides `awk`, `sed`, `grep`, `find` and dozens more, and the
launcher points `PATH` at a directory of symlinks to it.

⛔ **Whatever the approach, a script SHOULD check its dependencies at start-up
and fail with a message naming what is missing**, not fail three hundred lines
in with `command not found`.

```sh
for c in jq curl; do
  command -v "$c" >/dev/null 2>&1 || {
    printf 'mytool: required command not found: %s\n' "$c" >&2
    exit 127
  }
done
```

## 4. Portability traps in the scripts themselves

⚠ **Each of these works on GNU and fails elsewhere**, which is the usual shape
of a script that was tested on one distribution.

| construct | fails on |
| --- | --- |
| `sed -i` with no suffix | BSD and macOS `sed` |
| `readlink -f` | some BSDs |
| `echo -e` | ⛔ not POSIX; `printf` is |
| `[[ ... ]]`, arrays, `local` | ⛔ not POSIX `sh`; bash and ksh only |
| `grep -P` | BSD grep, and busybox grep |
| `date -d` | BSD `date`, which uses `-v` |
| `sort -V` | busybox sort |
| `mktemp -d` without a template | ⚠ portable in practice, not in the standard |

⭐ **`shellcheck` catches most of these and belongs in the validator**, per
[`../../testing.md`](../../testing.md).

## 5. Other scripting languages

| language | ship the interpreter | note |
| --- | --- | --- |
| ⭐ awk | ⭐ busybox awk, or a static `gawk` | small, portable |
| Perl | ⚠ possible with `staticperl` or PAR::Packer | ⚠ large; module dependencies are the hard part |
| Ruby | ⚠ `ruby-packer` is unmaintained; ship a runtime tree | ⚠ awkward |
| PHP | ⭐ `static-php-cli` builds a static PHP binary | ⭐ works well for CLI tools |
| Lua | ⭐ static by construction; `luastatic` embeds scripts into a binary | ⭐ ⭐ the easiest of these |
| Tcl | ⭐ `tclkit` and starpacks are a mature single-file format | good |

⭐ **Lua deserves a mention as the exception.** `luastatic` compiles a Lua
program plus the interpreter into one C file and then a static binary, and the
result is genuinely small and genuinely static.

## 6. Reproducibility

⭐ **Scripts are the easiest case**: no compilation, so byte-identical output is
a copy.

| control | |
| --- | --- |
| ⭐ the script itself | pinned by the source commit |
| a shipped interpreter | ⛔ pinned by `[[tool]]` sha256 |
| ⚠ a generated launcher | must not embed a timestamp or a path |
| ⚠ `#!` rewriting | must be deterministic |

## 7. Security

⛔ **A script is source, so a user can read what it does. That is a real
advantage and it changes nothing about verification**: it is still hashed and
signed like any other artefact.

⚠ **Shipping an interpreter means shipping its vulnerabilities.** A package
containing bash needs a rebuild when bash has a security fix, exactly as a
static C binary does. [`../../security/supply-chain.md`](../../security/supply-chain.md) §fan-out.

## 8. ⭐ Production defaults, failure modes, when not to

**Defaults**

- POSIX `sh` where the script can be written in it, with no shipped
  interpreter.
- Otherwise ship the interpreter and a POSIX `sh` launcher.
- ⭐ Ship `busybox` for the external commands, or restrict to a POSIX baseline.
- `shellcheck` clean, as a validation gate.
- A start-up dependency check with a clear message.

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ `bash: not found` | assumed bash; Alpine has none by default |
| `jq: not found` deep in a run | ⛔ an undeclared command dependency |
| works on Ubuntu, fails on Alpine | GNU-specific flags; `shellcheck` catches most |
| the launcher cannot find its payload | ⚠ a non-relocatable path in the launcher |

**⛔ When not to ship an interpreter**: the script is POSIX `sh` and uses only
POSIX utilities. Shipping bash for a script that does not need it is 1 MB of
attack surface and rebuild burden for nothing.
