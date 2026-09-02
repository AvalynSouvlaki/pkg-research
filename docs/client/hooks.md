# hooks and lifecycle scripts

⛔ **A package cannot run code at install time.** This document is why, what
that costs, and what replaces the cases people reach for hooks to solve.

The decision record is
[`../decisions/0012-no-hooks.md`](../decisions/0012-no-hooks.md).

---

## 1. The rule

⛔ **There is no `pre-install`, `post-install`, `pre-remove` or `post-remove`
script, and no field in which to put one.**

Installing is: verify, unpack into staging, rename, symlink. Four operations,
none of which execute package content.

⭐ **That is what makes `opk install` safe to run on software you have not
audited.** The binary is still arbitrary code, and the user chooses when to run
it. A hook runs at install time, on every machine, without the user choosing
anything.

---

## 2. Why

| | |
| --- | --- |
| ⛔ a hook is arbitrary code executed by installing | the user's decision to *install* becomes a decision to *execute* |
| ⛔ under `--system`, that code runs as root | a package compromise becomes a system compromise |
| ⚠ hooks are where package managers accumulate their worst behaviour | ⭐ removing them removes the category |
| ⚠ a hook that fails leaves a half-installed state | atomic install is impossible with a hook in the middle |
| ⛔ a hook cannot be verified | a signature covers bytes, not what they do |

⭐ **The last row is the one that settles it.** Everything else in this design
is built on the idea that verification tells you something useful. A hook makes
"this artefact is authentic" and "installing this is safe" different claims, and
only the first is checkable.

---

## 3. What people use hooks for, and what replaces each

⛔ **This is the substantive half.** A rule that forbids something without
answering the real need gets worked around.

| the need | the replacement |
| --- | --- |
| put the binary on `PATH` | ⭐ the symlink farm does it |
| ⭐ generate shell completions | ⭐ ship them as files; the client links them. §4. |
| register a man page | ⭐ shipped under `share/man/`, linked, `MANPATH` set by `opk env` |
| ⭐ create a config file | ⭐ ship defaults under `etc/`; the client copies on first install |
| update a desktop or icon database | ⚠ `--desktop` links the files; ⛔ the client prints the host command rather than running it |
| create a system user | ⛔ ⚠ out of scope; §5 |
| install a systemd unit | ⛔ ⚠ out of scope; §5 |
| compile a schema or build a cache | ⭐ do it at build time and ship the result |
| download extra data | ⛔ ⚠ see §6 |
| migrate a config between versions | ⭐ the program does it on first run, where it can report errors to the user |
| ⛔ set a capability or setuid bit | ⛔ refused outright; §5 |

⭐ **"Do it at build time and ship the result" covers more cases than it
looks.** A hook that runs a code generator, builds an index, or compiles a
schema is doing work that has one correct answer, and doing it once in the
build is better than on every machine.

---

## 4. Shell completions, worked through

⭐ **The most common legitimate hook, and it needs none.**

A package ships:

```
share/completions/bash/rg
share/completions/zsh/_rg
share/completions/fish/rg.fish
```

declared in the recipe:

```toml
[artifact]
"complete/rg.bash" = "share/completions/bash/rg"
"complete/_rg"     = "share/completions/zsh/_rg"
"complete/rg.fish" = "share/completions/fish/rg.fish"
```

The client links them into `<prefix>/share/completions/<shell>/`, and
`opk env` emits the lines that put those directories on the shell's search
path.

⛔ **The client does not edit the user's shell configuration**, per
[`installation-layout.md`](installation-layout.md) §3. It prints one line to
add.

⚠ **Some programs only emit completions by running themselves**
(`prog completions bash`). ⭐ That is a build-time step: the build runs it and
ships the output. It is exactly the case where doing the work once beats doing
it on every machine.

---

## 5. What is genuinely out of scope

⛔ **Some things a hook could do are not replaced, because they should not be
done by a package manager at all.**

| | why |
| --- | --- |
| ⛔ creating system users or groups | a host administration decision |
| ⛔ installing and enabling a service | same, and it makes install a privileged action |
| ⛔ setting file capabilities or setuid | ⛔ a privilege escalation surface; refused at build and at unpack |
| ⛔ modifying files outside the prefix | ⛔ the containment property |
| ⛔ starting a daemon | not a package manager's job |

⭐ **Software needing those is packaged for a system package manager, or it
ships instructions.** A package **MAY** carry a `note` telling the user what to
run, and the client prints notes after install:

```
installed caddy 2.8.4-1

note: to run as a service, see
      https://caddyserver.com/docs/running#linux-service
      opk does not install or manage services.
```

⚠ **This is a real limitation and it narrows what this system is for.** It is a
distribution mechanism for self-contained programs, not a replacement for a
system package manager, and pretending otherwise would be the more harmful
position.

---

## 6. Downloading extra data

⛔ **A package that downloads data at install time is running code at install
time**, whatever it is written in.

| case | answer |
| --- | --- |
| the data is small and stable | ⭐ ship it in the artefact |
| the data is large and stable | ⭐ a separate package, installed explicitly |
| the data is per-user or changes often | ⭐ the program fetches it on first run |
| the data cannot be redistributed | ⭐ the program fetches it, and a `note` says so before install |

⭐ **"The program fetches it on first run" is the right answer more often than
it seems.** The program can report a network failure to a user who is present
and can retry, which an install-time hook cannot.

---

## 7. The one exception, and its shape

⚠ **User-configured hooks are supported. Package-supplied hooks are not.**

```toml
# ~/.config/opk/config.toml
[hooks]
post-install = "~/.local/bin/opk-post-install"
```

| property | |
| --- | --- |
| ⭐ written by the user, for their own machine | not shipped by a package |
| ⭐ receives the operation as JSON on stdin | name, version, paths, what was verified |
| ⛔ a failure does not roll back the install | ⭐ the install already completed |
| ⛔ never runs under `--system` unless configured in the system config by root | |

⭐ **The distinction is who decided.** A user adding a hook to run
`update-desktop-database` has made a choice about their machine. A package
carrying one has made that choice for everyone who installs it.
