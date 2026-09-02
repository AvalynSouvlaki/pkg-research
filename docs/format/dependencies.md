# dependencies

Build, runtime and optional dependencies, and why the runtime set is nearly
always empty.

---

## 1. The three kinds

| kind | needed | declared in | resolved by |
| --- | --- | --- | --- |
| **build** | to produce the artefact | `[build].deps`, `[[tool]]`, the base image | the builder, inside the container |
| **runtime** | to run the artefact | `[runtime]` | ⭐ nearly always nothing to resolve |
| **optional** | to enable a feature | `[runtime.optional]` | the user, explicitly |

⭐ **The central consequence of static linking is that the runtime dependency
graph collapses.** There is no solver here, and there is nothing for one to
solve, because the thing a solver exists to compute has been moved into the
build.

⚠ **"Nearly always" is doing real work in that sentence.** §3 is the list of
what genuinely remains, and it is not empty.

---

## 2. Build dependencies

Three mechanisms, in decreasing order of preference.

| # | mechanism | pinned by | use when |
| --- | --- | --- | --- |
| 1 | ⭐ the base image contains it | the image digest | always, if you control the image |
| 2 | `[[tool]]` | `sha256` of the downloaded file | a single executable not in any image |
| 3 | `[build].deps` | ⛔ nothing | a distribution package with no better option |

⛔ **Mechanism 3 is the reproducibility gap and it is stated, not hidden.**
`apk add musl-dev` installs whatever version the distribution currently has.
Two builds a month apart can differ. The consequences and the two ways to close
it are in [`../build/reproducibility.md`](../build/reproducibility.md) §gaps.

⚠ **Language package managers are a fourth mechanism hiding inside `run`.**
`cargo build` fetches crates; `go build` fetches modules; `npm install` fetches
packages. Whether that is pinned depends entirely on the ecosystem:

| ecosystem | pinned by | strength |
| --- | --- | --- |
| Cargo with `--locked` | `Cargo.lock`, which records a checksum per crate | ⭐ strong |
| Go with `GOFLAGS=-mod=readonly` | `go.sum`, checksums, plus the checksum database | ⭐ strong |
| npm with `npm ci` | `package-lock.json`, with integrity hashes | strong |
| pip with a hash-pinned requirements file | `--require-hashes` | strong, if used |
| pip without hashes | ⛔ nothing | none |
| `make` downloading a tarball in a rule | ⛔ nothing | none |

⛔ **A recipe whose build fetches unpinned code SHOULD set
`network = "none"` and vendor instead.** Where that is impractical, it
**MUST** be visible: `hermetic` is false in the metadata and the provenance
records it.

---

## 3. Runtime dependencies

`[runtime]` is optional and usually absent. When present it declares what the
*host* must supply, not other packages.

```toml
[runtime]
kernel   = ">=5.6"
requires = ["fuse3"]
```

| field | meaning |
| --- | --- |
| `kernel` | a minimum kernel version, when the binary uses a newer syscall |
| `requires` | host-provided facilities, from the closed set below |

⛔ **`requires` is a closed set**, because an open one becomes a dependency
language and then a solver.

| token | means | typical cause |
| --- | --- | --- |
| `fuse3` | a FUSE implementation and permission to use it | AppImage-style self-mounting artefacts |
| `glibc` | the host's glibc, at the version in `[runtime].glibc` | ⛔ requires `portable = false` |
| `x11` / `wayland` | a display server | GUI programs |
| `gpu-driver` | a vendor userspace driver loaded with `dlopen` | anything doing hardware acceleration |
| `ca-certificates` | a system trust store at a standard path | ⚠ see §5 |
| `systemd` | a running systemd | service integration |

⚠ **`requires` is advisory to the client, not a gate.** The client warns and
proceeds by default, because a wrong `requires` entry that blocked installation
would be worse than a missing one. `--strict-requires` makes it a gate for
users who want that.

### Why there is no inter-package dependency graph

| a package manager usually needs | here |
| --- | --- |
| shared libraries resolved across packages | statically linked in |
| version constraints between packages | nothing to constrain |
| install ordering | every package is independent |
| a solver, and its failure modes | absent |

⭐ **This is the largest single simplification static linking buys**, and it is
why this system can be understood in an afternoon while a distribution package
manager cannot.

⚠ **It is a trade, not a free win.** [`../architecture.md`](../architecture.md)
§10 limit L6: a vulnerable library statically linked into forty packages
requires forty rebuilds, where a dynamically linked system patches one file.
The mechanism that pays that cost is in
[`../security/supply-chain.md`](../security/supply-chain.md) §fan-out.

---

## 4. Optional dependencies

```toml
[runtime.optional]
ffmpeg = "enables video thumbnailing"
```

A map from a host-provided facility to what it enables. ⛔ **Purely
informational**: the client shows it, never acts on it, and never installs
anything on the user's behalf.

⚠ **Optional dependencies at build time are a different thing entirely** and
are expressed as variants, not as optional dependencies.
[`variants-and-features.md`](variants-and-features.md).

---

## 5. The two host facilities that catch people

### 5.1 Certificates

⛔ **A static binary has no certificate store.** It is not a dependency the
package can satisfy, and it is the single most common reason a working static
binary fails on a user's machine with a TLS error.

Three answers, in order of preference:

| # | approach | trade |
| --- | --- | --- |
| 1 | ⭐ read the host's store at run time, trying the standard paths in order | follows host policy; fails on a host with no store |
| 2 | use the OS-native verifier where one exists | best behaviour, more code |
| 3 | embed a CA bundle at build time | ⛔ frozen at build time. A revoked or newly required root needs a rebuild. |

**MUST**: a package that does TLS states which approach it uses in `note`.

⚠ **Approach 3 is the one that ages badly and it is chosen by default by
several ecosystems.** Rust's `rustls` with `webpki-roots` embeds a bundle.
Go's `crypto/x509` reads the host store. Per-ecosystem detail is in
[`../build/languages/README.md`](../build/languages/README.md).

The standard paths, tried in order:

```
/etc/ssl/certs/ca-certificates.crt          Debian, Ubuntu, Alpine
/etc/pki/tls/certs/ca-bundle.crt            Fedora, RHEL
/etc/ssl/ca-bundle.pem                       openSUSE
/etc/ssl/cert.pem                            Alpine, macOS
/etc/ssl/certs/                              a directory of hashed links
```

⚠ **`SSL_CERT_FILE` and `SSL_CERT_DIR` override all of the above** in most
implementations, and a package **SHOULD** honour them.

### 5.2 Name resolution

⛔ **A statically linked glibc binary reaches for the host's NSS modules, and
what happens next depends on the host.** glibc's name-service switch loads
`libnss_*.so` with `dlopen` at run time, naming whatever
`/etc/nsswitch.conf` names.

⛔ **This page said such a binary "cannot use NSS" and that was wrong in the
comfortable direction.** Measured by `polaris0xff/glibc-research` across 11
distributions pinned by digest: the host's modules **were loaded on 5 of 11**,
including on a musl distribution, and the process **died with SIGFPE on 2 of
11** (Arch, openSUSE Leap 15.6). ⚠ A static binary has no `PT_INTERP`, and it
still opened a host shared object carrying `DT_NEEDED libc.so.6`.

⭐ **The full evidence, and the toolchain that closes it**, are in
[`../interop/glibc-research.md`](../interop/glibc-research.md) §2.1.

| libc or runtime | behaviour when static |
| --- | --- |
| glibc | ⛔ ⚠ **host-dependent**: host modules loaded on 5 of 11, SIGFPE on 2. A link warning is emitted and usually ignored. |
| musl | ⭐ its resolver is built in; reads `/etc/resolv.conf` and `/etc/hosts` directly |
| Go with `CGO_ENABLED=0` | ⭐ pure-Go resolver, reads the same files |
| Go with `CGO_ENABLED=1` | uses glibc's resolver, and the binary is dynamic. Measured in `experiments/20-static-matrix.sh`. |
| Rust with musl | musl's resolver |

⭐ **This is a first-order reason musl is the default libc here**, and it is
recorded in
[`../decisions/0003-static-musl-default.md`](../decisions/0003-static-musl-default.md).

⚠ **musl's resolver is not glibc's, and the differences are observable.**
Historically musl did not support `search` domains with more than a few
entries, sends queries to all configured nameservers in parallel rather than
sequentially, and has a 512-byte UDP buffer that can truncate large responses
where glibc would retry over TCP. For almost all command-line software none of
this matters; for something doing service discovery it can.
