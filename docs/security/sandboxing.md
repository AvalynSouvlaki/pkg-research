# sandboxing and permissions

Two separate sandboxes: the one a build runs in, and the one an installed
program runs in. They have different threat models and different answers.

---

## 1. The build sandbox

⛔ **Mandatory. A build runs in a container pinned by digest.** The contract is
[`../build/build-system.md`](../build/build-system.md) §2.6; this is the
isolation properties it provides.

| boundary | mechanism | what it stops |
| --- | --- | --- |
| filesystem | only `/build` writable, `/tools` read-only | writing outside the workspace |
| ⛔ credentials | none present | theft |
| network | `none`, allowlist proxy, or `full` with a reason | exfiltration |
| process | a fresh container per build, `--rm` | persistence between builds |
| ⛔ privilege | ⛔ never `--privileged` | host escape through device access |
| resources | `--memory`, `--timeout` | a build exhausting the runner |

⛔ **`--privileged` is never used.** The studied system's era-1 recipes run
`docker run --privileged --net=host` inside the *recipe body*, which means each
package's own build script chose its isolation level. Isolation a recipe can
switch off is not isolation.

⚠ **A container is not a security boundary against a determined kernel
attack**, and this design does not claim it is. What it provides is that a
malicious build cannot reach a credential, cannot persist, and cannot publish
anything the artefact map does not name. A kernel escape from a build container
compromises the runner, and the runner is disposable and holds nothing.

⭐ **Rootless podman is preferred** because a kernel escape then lands in an
unprivileged user namespace rather than as root.

---

## 2. The install-time permission model

⛔ **Installing a package MUST NOT run anything from it.**

| | |
| --- | --- |
| ⛔ no pre-install script | [`../client/hooks.md`](../client/hooks.md) |
| ⛔ no post-install script | same |
| ⛔ no setuid or setgid files | verifier check V8 |
| ⛔ nothing written outside the install prefix | path validation, twice |
| ⭐ no root required | user-scoped install is the default |

⭐ **Installing is: verify, unpack into staging, rename, symlink.** Four
operations, none of which execute package content. That is the whole model, and
it is what makes `opk install` safe to run on software you have not audited.

⚠ **The cost is real**: a package cannot register a systemd unit, create a
user, or compile a schema at install time. Those are conveniences, and each one
is also a way for a package to run as the installing user.
[`../decisions/0012-no-hooks.md`](../decisions/0012-no-hooks.md) has the
argument and what replaces them.

---

## 3. Run-time sandboxing

⚠ **Out of scope as a requirement, supported as a convenience.**

⛔ **Once a user runs an installed program, it has the user's privileges.** That
is true of every package manager, and pretending otherwise would be the more
dangerous position.

What the client offers:

```sh
opk run --sandbox ripgrep .        # run under a restrictive profile
```

| platform | mechanism | status |
| --- | --- | --- |
| Linux with bubblewrap | ⭐ user namespaces, a read-only root, an explicit bind set | ⚠ optional; needs `bwrap` |
| Linux with a seccomp profile | syscall filtering | ⚠ per-package profiles, rarely worth authoring |
| ⭐ WebAssembly packages | ⭐ capability-based by construction | [`../build/languages/wasm.md`](../build/languages/wasm.md) §5 |
| macOS | `sandbox-exec` | ⚠ deprecated by Apple; not relied on |
| Windows | AppContainer | ⚠ specified, not measured |

⭐ **A default profile is possible and useful for the common case of a
command-line tool**: read-only filesystem except the working directory, no
network, no new privileges.

```sh
bwrap --ro-bind / / --bind "$PWD" "$PWD" --chdir "$PWD" \
      --unshare-net --unshare-pid --new-session --die-with-parent \
      --proc /proc --dev /dev \
      -- "$prog" "$@"
```

⚠ **`--unshare-net` breaks any tool that needs the network**, which is why this
is opt-in per invocation rather than a default. A default sandbox that breaks
half of what users run gets disabled globally on day one.

⚠ **A package MAY declare a suggested profile** in `[sandbox]`, and it is a
suggestion the client shows, never something applied automatically. A package
declaring its own sandbox is a package declaring its own security policy, which
is the wrong party to decide it.

---

## 4. User versus system installation

| | user | system |
| --- | --- | --- |
| prefix | ⭐ `$XDG_DATA_HOME/opk` | `/opt/opk` |
| root needed | ⭐ no | yes |
| affects | one user | every user |
| ⭐ default | ⭐ **yes** | opt-in |
| escalation risk | ⛔ none beyond what the user can already do | ⚠ a compromised package affects everyone |

⛔ **The default is user-scoped, and that is a security decision as much as a
convenience one.** A package manager that needs root to install a command-line
tool has made every package a potential system compromise, for no benefit that
a static binary needs.

⛔ **System installation MUST NOT be triggered implicitly.** No automatic
fallback to `sudo`, no prompt that appears mid-install. It is a separate
invocation with an explicit flag.

⚠ **A system install still does not run package content.** The elevated
privilege is used to write files, and nothing else.

---

## 5. What the client itself needs

⛔ **The client requires no special privilege for its default mode.**

| operation | needs |
| --- | --- |
| resolve, download, verify | ⭐ network and a writable cache |
| install, user-scoped | ⭐ a writable data directory |
| install, system-wide | root, ⚠ only for the file operations |
| ⛔ nothing | ⛔ setuid on the client itself |

⛔ **The client is never setuid.** A setuid package manager is a privilege
escalation vector by construction, and there is no operation here that needs
one.

---

## 6. Threats this section does not address

| | |
| --- | --- |
| ⛔ a malicious package the user chooses to run | ⚠ run-time sandboxing is opt-in; the program has the user's rights |
| ⛔ a kernel vulnerability | outside this system's control |
| a supply-chain compromise upstream | [`supply-chain.md`](supply-chain.md) |
| a user installing from an untrusted repository | ⚠ adding a repository is an explicit trust decision, and the client says so when one is added |

⭐ **Adding a repository is the moment a user extends their trust**, and the
client treats it as such: it prints the key fingerprint, the repository URL, and
requires confirmation. After that, packages from it are as trusted as any other,
which is why the moment matters.
