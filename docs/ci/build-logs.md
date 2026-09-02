# build logs

⭐ **Storing, publishing, retrieving and reading the log of the build that
produced the binary a user is about to run.**

This is the capability the studied system's first era had and its third lost,
and recovering it is one of the reasons this design exists.

---

## 1. ⛔ Why logs are first-class

⭐ **The most-praised property of the historical system was that a package page
linked to the CI log of the exact build that produced the binary.** A user
could go from "what is this file" to "here is every command that made it" in
two clicks.

| a log answers | for |
| --- | --- |
| ⭐ why is there no build for my architecture | a user |
| what version of what toolchain compiled this | an auditor |
| ⭐ what did the build actually do | a reviewer |
| what changed between two revisions | a maintainer |
| ⭐ what failed | everyone |

⛔ **Logs are published for successes and failures alike.** Invariant I11,
[`../architecture.md`](../architecture.md).

---

## 2. Where a log lives

| kind | published as | retention |
| --- | --- | --- |
| ⭐ a successful build | a **referrer** of the package, `application/vnd.opk.buildlog.v1` | ⭐ indefinite |
| a failed build | a layer of a `buildfailure` manifest at the coordinate the package would have had | 90 days |

⭐ **A referrer, not a layer of the package**, for three reasons: a log is often
larger than the payload, it is almost never fetched, and attaching it must not
change the package's digest.

⚠ **CI platform log retention is not a substitute.** GitHub Actions logs expire,
and they are behind an authenticated API a user may not be able to reach. The
log in the registry is the durable copy.

```
ghcr.io/example/opk/ripgrep/ripgrep
  :14.1.1-1-x86_64-linux                    the package
  :sha256-d4311144...                       the referrers index, containing
                                              the log's manifest
```

---

## 3. What a log contains

⛔ **A header, then the trace, then a footer. Machine-parseable at the edges,
human-readable in the middle.**

```
=== opk build log v1 =========================================
package        ripgrep 14.1.1-1
host           x86_64-linux
target         x86_64-unknown-linux-musl
recipe         https://github.com/example/opk-packages/blob/4d5e6f/packages/ripgrep/opk.toml
recipe_sha256  sha256:7c8d9e...
image          docker.io/library/rust@sha256:b4b54b17...
source         git+https://github.com/BurntSushi/ripgrep@4649aa97...
epoch          1714435200
profile        release
network        restricted
runner         ubuntu-latest, Linux 6.11.0-1018-azure x86_64
started        2026-09-01T10:00:00Z
==============================================================

[00:00:00.000] phase: fetch source
[00:00:02.113]   commit verified 4649aa9700d4dbaad0c85b0ac8b2c66e2b649b6c
[00:00:02.115] phase: run
[00:00:02.190]   + rustup target add x86_64-unknown-linux-musl
...
[00:03:41.882] phase: verify
[00:03:41.900]   bin/rg  x86_64  static  no PT_INTERP  5238784 bytes
[00:03:42.104]   bin/rg --version -> ripgrep 14.1.1
[00:03:42.110] phase: assemble

=== result ===================================================
status         success
finished       2026-09-01T10:04:11Z
duration       251s
artifact       sha256:afb42bf28b19048d...
size           5242880
==============================================================
```

⭐ **The header is the provenance a human reads.** It carries the same facts the
attestation carries, in a form nobody needs a tool for, which is why both exist.

⚠ **Timestamps are relative in the body and absolute in the header.** Relative
timestamps make a log diffable between runs; absolute ones in the header say
when it happened.

---

## 4. ⛔ Before publishing

| step | |
| --- | --- |
| 1 | ⛔ scrub credentials. [`../security/secrets.md`](../security/secrets.md) §3. |
| 2 | ⛔ report the redaction count; a non-zero count is an incident |
| 3 | ⚠ truncate above 16 MiB, keeping the head and the tail, marking the cut |
| 4 | compress above 1 MiB with zstd |
| 5 | attach as a referrer |

⚠ **Truncating the middle rather than the tail is deliberate.** The interesting
part of a failed build is the end; the interesting part of a successful one is
the header. A log truncated from the end loses the error.

```
... 41,203 lines omitted by the 16 MiB log limit ...
```

---

## 5. Retrieval

```sh
opk log ripgrep                                  # the installed version
opk log ripgrep@14.1.1-1 --host aarch64-linux
opk log ripgrep --failed --host riscv64-linux    # ⭐ why is there no build
```

```sh
oras discover --format json ghcr.io/example/opk/ripgrep/ripgrep:14.1.1-1-x86_64-linux
oras pull ghcr.io/example/opk/ripgrep/ripgrep@sha256:<log manifest digest>
```

⛔ **On GHCR, `oras discover` will find nothing**, because there is no referrers
API. The client falls back to the tag `sha256-<subject hex>` per
[`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) §5.3, and `opk log` does
this transparently.

⭐ **`opk log --failed` is the command that answers the most common user
question about a missing package**, and it works without an account, a browser,
or knowing what CI is.

---

## 6. ⛔ Rendering a log safely

**A build log contains whatever the compiler and the upstream source printed.
It is untrusted.**

| threat | control |
| --- | --- |
| ⛔ terminal escape sequences rewriting the terminal | ⛔ strip all C0 and C1 control bytes except newline and tab |
| ⚠ output impersonating the client's own | ⭐ prefix every log line, or print a clear delimiter |
| ⛔ a very long line | wrap or truncate |
| ⛔ invalid UTF-8 | replace, do not pass through |
| ⛔ in a web view | escape as text; ⛔ never render as markup |

⚠ **This is easy to forget because a log looks like output rather than like
data.** A `description` field is obviously attacker-influenced; a compiler's
stderr is too, because the compiler was compiling somebody's source.

---

## 7. Web visibility

⭐ **A package page carries the same links the historical system's did**, which
is the user-facing half of this capability.

| link | to |
| --- | --- |
| ⭐ build log | the referrer, fetched through a gateway |
| ⭐ CI run | `metadata.build.run_url` |
| ⭐ recipe | ⭐ `metadata.build.recipe_url`, ⛔ pinned to the commit |
| provenance | the attestation |
| SBOM | the SBOM |

⛔ **The recipe link is pinned to a commit, not to a branch.** Era 1's
`build_script` field pointed at `refs/heads/main`, so following it later showed
the current recipe rather than the one that built the artefact.
`recipe_sha256` makes the drift detectable as well as prevented.

⚠ **A gateway serving registry content over plain HTTP is a convenience, not
part of the trust chain.** The historical system's `api.ghcr.pkgforge.dev`
turned an OCI registry into per-file downloads and that is genuinely useful; a
client must still verify through the registry, because a gateway is one more
party who could serve something else.

---

## 8. Storage

| | |
| --- | --- |
| a typical successful log | ⚠ 10 KiB to 500 KiB compressed |
| a large build | ⚠ up to the 16 MiB cap |
| ⛔ the dominant cost | ⚠ **count, not size**: one log per package per host per revision |

⚠ **At a thousand packages, two hosts and monthly revisions, that is 24,000
log objects a year.** Each is a manifest plus a blob, so 48,000 registry
objects. That is the number to check a registry's limits against, not the
bytes.

⭐ **Failure logs expire at 90 days precisely because they are the fastest
growing category**: a broken package can fail every day.
[`../registry/retention.md`](../registry/retention.md) §2.
