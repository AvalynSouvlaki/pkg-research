# interop: `glibc-research` and `pgb`

⭐ **A sibling project that solves the half this tree assumes away**, and ⛔ **two
claims of ours that its measurements disprove.**

| | |
| --- | --- |
| repository | `polaris0xff/glibc-research` |
| pinned at | commit `d0449a3da25266b81d11d5ac85ae784fc33f145b`, 2026-09-02 |
| licence | 0BSD, ⭐ the same as this tree, so code and text move between them without friction |
| read on | 2026-09-02 |

⛔ **Everything below cited as `measured` was measured by them, not by us.** It
is repeated here because it changes what this tree says, and each row names the
evidence file it came from so a reader can check it at that commit rather than
trust this page.

---

## 1. What it is

⭐ **A toolchain, `pgb`, that makes an ordinary glibc-linked ELF run unchanged
on glibc and musl distributions.** Not a packaging format, not a launcher, not
a bundle: the output is one executable file.

⛔ **The problem it addresses is the one this tree walks past.** We treat
"statically linked" as a property `tools/elfprobe.py` can decide by reading
`PT_INTERP`. That test is necessary and it is not sufficient. A binary with no
`PT_INTERP` can still pull host shared objects into its address space through
four routes, every one of them inside glibc rather than in the application:

| route | what enters the process |
| --- | --- |
| NSS | the host's `libnss_*.so.2`, named by the host's `/etc/nsswitch.conf` |
| gconv | the host's character-set conversion modules |
| locale | host locale data, or no UTF-8 codeset at all |
| `dlopen` | whatever the program asks for |

⚠ **Each of those carries `DT_NEEDED libc.so.6`**, so a second libc arrives in
a process that was built to have none.

⭐ **Four mechanisms answer them**, none of which changes application source
(documented, from their README at the pinned commit):

| | mechanism |
| --- | --- |
| NSS | a constructor calls `__nss_configure_lookup()`, a public `GLIBC_2.2.5` symbol present in `libc.a`, pinning every database to services that glibc implements inside libc. The host's `nsswitch.conf` then names nothing loadable. |
| iconv | `-Wl,--wrap` redirects the three public iconv entry points to a statically linked GNU libiconv, at the final link, so it catches calls from archives built before the tool existed. |
| locale | opt-in `--embed-locale`: C.UTF-8 embedded, written out only when the host cannot answer a UTF-8 `setlocale`. |
| own plugins | opt-in `--wrap-dlopen`: `dlopen`, `dlsym`, `dlclose` and `dlerror` answered from a table generated with `nm` from the build's own objects. Nothing is mapped, so no second libc can enter. ⚠ Host plugins are explicitly not covered. |

---

## 2. ⛔ What it corrects in this tree

⭐ **Read this section before trusting §3 or §5.2 of
[`../build/static-linking.md`](../build/static-linking.md).** Both were written
from the specification and from reasoning about how NSS works. Neither was
measured on a distribution other than the probe host, and both are wrong in the
same direction: ⛔ **they describe a failure that is quiet and bounded, where the
measured failure is loud, host-dependent, and sometimes a crash.**

### 2.1 ⛔ Static glibc NSS does not fail quietly

**What this tree said** (`static-linking.md` §5.2, and the `glibc` column of the
§3 table):

> glibc's name-service switch uses `dlopen`, so a static glibc binary silently
> loses LDAP, mDNS and `myhostname` resolution.

⛔ **Measured, and it is the opposite.** A plain `gcc -static` glibc binary,
across 11 distributions pinned by digest
(`glibc-research evidence/20-static-glibc-nss-dlopen/RESULT.txt`):

| distribution | libc | plain `-static` | host NSS modules it pulled in |
| --- | --- | --- | --- |
| alpine 3.22, 3.20, 3.10 | musl | ok | none |
| ⚠ voidlinux-musl | musl | ok | `libnss_mdns.so.2` |
| debian 11, debian 12, ubuntu 20.04 | glibc | ok | none |
| rockylinux 8 | glibc | ok | `libnss_sss.so.2` |
| ⛔ opensuse leap 15.6 | glibc | **SIGFPE** | `libnss_compat.so.2` |
| fedora 42 | glibc | ok | `libnss_myhostname.so.2`, `libnss_resolve.so.2` |
| ⛔ archlinux latest | glibc | **SIGFPE** | `libnss_mymachines.so.2` |

⛔ **Host NSS modules were loaded on 5 of 11, and the process died on 2 of 11.**
⚠ **One of the five is a musl distribution**, which is the result that most
directly contradicts the intuition behind our sentence: a static glibc binary
loaded a host NSS module on a machine that ships no glibc.

⭐ **Why this matters more than a wording fix.** "Silently loses a feature" is a
functionality note a maintainer weighs against convenience. "Loads an arbitrary
host shared object into your address space, or crashes, depending on which
distribution the user has" is a portability and a supply-chain statement, and it
belongs in [`../security/supply-chain.md`](../security/supply-chain.md)'s
threat surface rather than in a compatibility footnote.

⭐ **It strengthens rather than weakens
[`../decisions/0003-static-musl-default.md`](../decisions/0003-static-musl-default.md).**
The decision was right; the reason recorded under it was too mild.

### 2.2 ⛔ A static glibc binary does not get glibc's character sets

**What this tree said** (`static-linking.md` §3, the `iconv` row):

> `iconv` character sets: musl, a small set; glibc, very large.

⚠ **True of dynamic glibc. Measured false of static glibc**
(`glibc-research evidence/30-gconv-and-locale/RESULT.txt`, 12 encodings, one byte-exact round
trip each):

| plain `-static` on | result |
| --- | --- |
| alpine 3.22, 3.20, 3.10, voidlinux-musl, rockylinux 8, opensuse leap 15.6, fedora 42, archlinux | ⚠ `opened=1 failed=11`, round trip fails |
| ⛔ debian 11, debian 12, ubuntu 20.04 | ⛔ **no output**: the process died |

⭐ **So the honest comparison is 1 of 12 against musl's small-but-present set**,
not "very large against small". glibc's encoding breadth lives in `dlopen`ed
gconv modules and does not survive static linking.

⚠ **The same evidence file corroborates one of our numbers.** Their arm A is
**785,480 bytes**; our measured `gcc -static` glibc row is **785,360**. Two
different trivial programs, the same toolchain family, 120 bytes apart. ⭐ That
agreement is the reason to take the rows above seriously.

### 2.3 A floor we did not know about

⭐ **Measured** (`glibc-research evidence/21-glibc-version-floor/RESULT.txt`): the NSS override
works only when the **build** glibc is 2.34 or newer. Built against glibc 2.31
and run on Debian 11, the binary loaded `libnss_dns.so.2` and
`libnss_files.so.2` even with the override applied, because those services are
not builtin before 2.34. Built against 2.36, with or without the override, it
loaded none.

⛔ **The build environment's glibc version is therefore a correctness input, not
a preference.** For this tree that is a `[build].image` concern: an image whose
glibc predates 2.34 cannot produce a portable glibc artefact by this route, and
the digest pin that
[`../format/build-manifest.md`](../format/build-manifest.md) §4 already requires
is what makes the version knowable.

---

## 3. ⭐ What this tree offers `pgb`

⛔ **`pgb` ends where a binary exists. This tree begins there.** Neither
project duplicates any part of the other, which is what makes this worth
writing down.

| they have | we have | the join |
| --- | --- | --- |
| a portable binary | ⭐ an OCI distribution substrate | [`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) |
| `evidence/` per experiment | ⭐ signed, attested artefacts with provenance | [`../security/signing-and-attestations.md`](../security/signing-and-attestations.md) |
| a build that runs on one machine | ⭐ reproducibility controls and a rebuild check | [`../build/reproducibility.md`](../build/reproducibility.md) |
| `nm` and `strace` as instruments | `tools/elfprobe.py`, which reads ELF bytes and never runs the file | [`../../experiments/README.md`](../../experiments/README.md) |

⭐ **Four things transfer with no adaptation:**

1. ⛔ **GHCR does not implement the referrers API.** Measured here with two
   controls held in the same run, in `experiments/40-registry-conformance.sh`.
   Anyone publishing evidence alongside a binary on GHCR needs the fallback tag,
   or discovery returns nothing and every artefact appears unsigned.
   [`../decisions/0005-referrers-fallback.md`](../decisions/0005-referrers-fallback.md).
2. ⭐ **The reproducibility control list**, `D1` to `D15` in
   [`../build/reproducibility.md`](../build/reproducibility.md) §2. A toolchain
   that pins the build image by digest is most of the way there already; the
   rows that usually remain are archive ordering, the gzip header, and the
   build-id.
3. ⭐ **`SOURCE_DATE_EPOCH` taken from the source commit, never the clock**, and
   a fixed `/build` path so the two braces hold independently.
4. ⚠ **The evidence-file trap we hit and they can hit.** Each experiment here
   `tee`s its own `out/*.txt`; re-running one with a shell redirect to that same
   path gives the file two writers and leaves correct output followed by NUL
   bytes, with every check still passing. Their `evidence/` layout has the same
   shape. `tools/check-consistency.sh` check 7 is the guard.

⭐ **The single most useful thing to take is the `portable` field with a proof
behind it.** [`../format/build-manifest.md`](../format/build-manifest.md) §1
already defines `portable`, defaulting to `true` and requiring
`portable-reason` when false, and
[`../registry/media-types.md`](../registry/media-types.md) §5 already carries it
onto the manifest as `dev.opk.portable`. ⛔ **Today that field is an assertion by
the recipe author.** A `pgb verify` run across 11 environments is what would
turn it into a measurement.

---

## 4. What `pgb` offers this tree

⭐ **A third answer to "which libc", where we had two.**

[`../build/static-linking.md`](../build/static-linking.md) §3 presents musl and
glibc as a choice between portability and capability. `pgb` is a claim that the
trade is not forced:

| | static musl | plain static glibc | `pgb` |
| --- | --- | --- | --- |
| runs on musl and glibc hosts | ⭐ yes | ⛔ **no**, §2.1 | ⭐ yes, ⚠ measured by them on 11 |
| loads host NSS modules | ⭐ never | ⛔ 5 of 11 | ⭐ none |
| iconv encodings | ⚠ a small set | ⛔ 1 of 12, or a crash | ⭐ 12 of 12 |
| ⚠ size | ⭐ 17,816 measured here | 785,360 measured here | ⚠ **1,937,632 for the iconv arm alone**, which is not the full `pgb` output; see below |
| `malloc`, 4 threads | ⚠ 584.71 ns | ⭐ 4.53 ns | ⭐ glibc's, on any host |

⛔ **The size row is not a like-for-like comparison and must not be read as
one.** 1,937,632 bytes is arm B of their gconv experiment, a plain static build
plus static libiconv. A complete `pgb` binary carries the NSS constructor and,
where enabled, an embedded locale and a `dlopen` table, so the real figure is
higher and ⚠ **this tree has not seen it stated anywhere**. The column is kept
because the order of magnitude bears on a packaging decision; the exact number
is not ours to quote.

⚠ **The throughput row is theirs and is the one to treat most carefully.** It is
one machine, one day, one synthetic workload, and it is the kind of number this
tree's [`../conventions.md`](../conventions.md) §4 exists to constrain. It is
reported here because the direction, not the magnitude, is what bears on a
design decision.

⭐ **Two data dependencies they name that this tree under-covers.**
[`../format/dependencies.md`](../format/dependencies.md) §5 treats certificates
and gives NSS a paragraph. ⭐ Their README, at the pinned commit, names **five**
distinct host data dependencies for a static binary: NSS, gconv, locale,
**terminfo** and **CA bundles**, and reports the first three closed and the last
two open. ⚠ We have nothing on terminfo at all, and a terminal program that
static-links ncurses and then finds no terminfo database is a failure mode a
package author will meet.

---

## 5. Using `pgb` output as a package

⭐ **No new specification surface is needed, and that is the finding of this
section.** A `pgb` build is a build image plus a script, which is exactly what
[`../format/build-manifest.md`](../format/build-manifest.md) §4 already
describes.

```toml
# EXAMPLE. The digest is abbreviated as elsewhere in this tree; a real
# recipe carries all 64 hex characters or validation rejects it.
[package]
name        = "nano"
description = "text editor, glibc-linked and host-independent"
license     = ["GPL-3.0-or-later", "LGPL-2.1-or-later"]
maintainer  = ["Example <example@example.org>"]
portable    = true

[build]
image = "docker.io/library/debian@sha256:b4b54b17..."
hosts = ["x86_64-linux"]

[build.script]
run = """
pgb env create
pgb build -- ./configure --prefix=/build/out && make && make install
pgb verify /build/out/bin/nano
"""
```

| this tree's requirement | how a `pgb` build meets it |
| --- | --- |
| ⛔ `[build].image` digest-pinned | the pinned build environment, which §2.3 shows is a correctness input rather than a preference |
| ⛔ the artefact has no `PT_INTERP` | `tools/elfprobe.py --expect-static`, unchanged |
| ⭐ `portable = true` | ⭐ earned by `pgb verify` rather than asserted |
| reproducibility | ⚠ **unproven for `pgb` output.** Neither project has rebuilt a `pgb` binary on a second host and compared bytes. |

⛔ **The last row is an open question, not a detail.** `--embed-locale` and
`--wrap-dlopen` both generate code at build time, `--wrap-dlopen` from a symbol
table produced by `nm` over the build's own objects. ⚠ **Generated code is
exactly where non-determinism hides**, and nothing in either repository has
tested it. Recorded as
[`../open-questions.md`](../open-questions.md) Q14.

### 5.1 ⛔ The obstacle this recipe does not solve

⚠ **`pgb verify` runs a binary on 11 distributions, and this tree's builds run
inside one container.** Their own requirements name root and `CAP_SYS_ADMIN`,
because the test bed is `unshare --mount` plus `chroot`.

⛔ **So `pgb build` fits a recipe and `pgb verify` does not.** Verification is a
fan-out across environments, which is a CI shape rather than a build shape.
⭐ **The place it belongs is [`../ci/ci-system.md`](../ci/ci-system.md)** as a
job that runs after the build and whose result feeds `portable`, not a line in
`[build.script].run`. ⚠ That job is specified nowhere yet, and the recipe above
shows `pgb verify` inside the script only because that is where a reader would
first try to put it.

---

## 6. ⛔ What neither project has shown

⭐ **Stated together, because a reader combining the two designs inherits both
gaps.**

| gap | whose | why it is open |
| --- | --- | --- |
| ⛔ cross-host reproducibility | ⭐ **both** | each measured one machine on one day |
| ⛔ reproducibility of `pgb` output specifically | both | never attempted; §5 |
| ⛔ `dlopen` of a **host** shared object | theirs | ⚠ host-dependent, and they state that success is the worse outcome, since it drags the host loader and libc in |
| terminfo, CA bundles as embedded data | ⚠ theirs open, ours absent | §4 |
| ⛔ anything written to real GHCR | ours | no namespace, no credentials |
| ⛔ non-Linux targets | both | both are Linux x86-64 |

⚠ **`pgb` is not shown to beat an anylinux AppImage**, and their README says so
directly: on the same 11 environments both run everywhere. The difference they
claim is shape, one file with nothing mounted or extracted, rather than reach.
⭐ **Repeating their own qualifier here is the point**, because a page that
imported only the favourable half of a sibling project's evidence would be
worth less than not writing it.

---

## 7. Provenance

| | |
| --- | --- |
| what was read | their `README.md`, and the `RESULT.txt` of their experiments 20, 21, 30 and 40 |
| ⚠ what was not read | the `pgb` implementation, the five proof-of-concept projects, `glibc-research docs/limitations.md` beyond its summary, and every experiment above 40 |
| how it was obtained | ⭐ anonymous public clone, `--depth 1`, at the commit named at the top |
| what was verified here | ⛔ **nothing.** Their experiments were not re-run on our probe host. |

⛔ **That last row is the limit of this page.** Every measurement quoted is
theirs, read out of a committed evidence file, and the corrections in §2 rest on
believing that file. ⭐ **The corroboration in §2.2, where their 785,480 bytes
meets our independently measured 785,360, is the only cross-check that exists**,
and it is one data point rather than a validation.

⭐ **What would settle it**: run their `glibc-research experiments/20-static-glibc-nss-dlopen.sh`
on this tree's probe host. ⚠ It needs root and `CAP_SYS_ADMIN`, because their
test bed is `unshare --mount` plus `chroot`, which is why it was not run here.
