# static linking

⭐ **Why this system links statically, what that costs, what it measures, and
when it is the wrong answer.**

Per-ecosystem recipes are [`languages/README.md`](languages/README.md). This
document is the theory, the measured results, and the decision rule.

---

## 1. The property that matters

⛔ **Not "is it static". "Does it need a loader the host may not have."**

A binary asks the host for a dynamic loader through the ELF program header
`PT_INTERP`, which names an absolute path. If that path does not exist, or the
loader there cannot satisfy the binary's symbol versions, the program does not
start, and the message the user sees names a library rather than a cause.

So the gate is: **`PT_INTERP` absent**. Not "the compiler was passed
`-static`", and not "`file` printed the word static".

⚠ **`file` is the wrong instrument and this is measured, not asserted.** On the
probe host, `file` 5.45 describes `gcc -static` output as "statically linked"
and `gcc -static-pie` output as "static-pie linked". A check grepping for the
first string rejects the second, which is equally portable. `tools/elfprobe.py`
reports the field instead.

⚠ **`ldd` is worse.** It answers by running the binary's own loader, which
cannot work for a cross-built artefact and is an execution primitive applied to
an untrusted file.

---

## 2. Measured

⭐ **Every row produced by `experiments/20-static-matrix.sh` on the host in
`experiments/out/10-probe-host.txt`.** Trivial "hello world" programs, so sizes
are the floor a toolchain imposes rather than a prediction about real software.

**Conditions.** Linux 6.18.44 x86_64, Ubuntu 24.04.4, gcc 13.3.0, clang 18.1.3,
musl 1.2.4, rustc 1.94.1, go 1.24.7, zig 0.13.0, gfortran and gnatmake and gdc
13.3.0, `SOURCE_DATE_EPOCH=1700000000`, 2026-09-02. The full inventory is
`experiments/out/10-probe-host.txt`.

| language | recipe | bytes | PT_INTERP | build-id | runs |
| --- | --- | ---: | --- | --- | --- |
| C | `gcc -static` (glibc) | 785,360 | none | yes | ✅ |
| C | `gcc -static-pie` (glibc) | 822,552 | none | yes | ✅ |
| C | ⭐ `musl-gcc -static` | 24,744 | none | no | ✅ |
| C | ⭐ `musl-gcc -static`, stripped | **17,816** | none | no | ✅ |
| C | `clang -static` (glibc) | 793,712 | none | yes | ✅ |
| C++ | `g++ -static -static-libstdc++` | 2,330,568 | none | yes | ✅ |
| Rust | ⭐ `--target *-linux-musl`, `crt-static` | 541,832 | none | yes | ✅ |
| Rust | `--target *-linux-gnu`, `crt-static` | 1,393,680 | none | yes | ✅ |
| Go | ⭐ `CGO_ENABLED=0 -trimpath -ldflags="-s -w"` | 1,433,748 | none | no | ✅ |
| Go | ⛔ `CGO_ENABLED=1` + `net` | 3,161,314 | **`/lib64/ld-linux-x86-64.so.2`** | no | ✅ here only |
| Go | `CGO_ENABLED=0` + `net` (the fix) | 2,019,476 | none | no | ✅ |
| Zig | ⭐ `zig build-exe -target x86_64-linux-musl` | **12,952** | none | no | ✅ |
| C via Zig | `zig cc -target x86_64-linux-musl` | 204,192 | none | no | ✅ |
| Fortran | `gfortran -static` | 1,220,024 | none | yes | ✅ |
| Ada | `gnatmake -largs -static` | 1,347,848 | none | yes | ✅ |
| D | ⛔ `gdc -static` against glibc | **does not link** | `undefined __tls_get_addr` | | ❌ |

### 2.1 What the table shows

⭐ **musl against glibc, for C: 17,816 against 785,360 bytes stripped.** A
factor of 44. glibc's static build pulls in locale, NSS and IO machinery a
trivial program never calls, and the linker cannot discard it because it is
reachable through function pointers.

⛔ **The Go row is the trap, demonstrated rather than described.** Nothing in
that source asks for dynamic linking. Importing `net` with cgo enabled makes
the toolchain use glibc's resolver, and the binary acquires a `PT_INTERP`. The
program ran on the build host, which is exactly why this is dangerous: it fails
on a user's machine, not on the builder's. ⭐ `CGO_ENABLED=0` fixes it and costs
1.1 MB.

⭐ **Zig produces the smallest binary at 12,952 bytes** and is a usable C
cross-compiler, `zig cc`, for projects with no Zig in them.

⛔ **D against glibc does not link at all**, and the reason is instructive
rather than incidental: `libgphobos` resolves thread-local storage through
`__tls_get_addr`, which the dynamic loader provides and a static link does not.
The same link warns that `dlopen` and `gethostbyname` need the shared glibc it
was linked against. The recommendation for D is LDC against musl.

⚠ **`musl-gcc` and Zig emit no build-id.** glibc's gcc spec adds
`--build-id` and musl's wrapper does not. A build-id is useful for symbol
servers and crash correlation, so a package wanting one passes
`-Wl,--build-id=sha1` explicitly. ⚠ It is a hash of the output, so it changes
when the output changes, which is fine, and `--build-id=none` is what a
reproducibility-focused build uses when it does not want the field at all.

---

## 3. Choosing a libc

| | musl | glibc |
| --- | --- | --- |
| designed for static linking | ⭐ yes | no |
| static size, measured | ⭐ 17,816 | 785,360 |
| NSS in a static binary | ⭐ built-in resolver | ⛔ ⚠ **worse than unavailable**: host-dependent. See §3.1. |
| `dlopen` in a static binary | ⛔ not supported | ⛔ works badly and is warned about |
| locale support | ⚠ C and C.UTF-8 only | full |
| `iconv` character sets | ⚠ a small set | ⛔ **1 of 12 when statically linked**, or a crash. See §3.1. |
| performance of `malloc` | ⚠ slower under heavy multithreaded churn | faster |
| licence | MIT | LGPL, ⚠ and see §6 |
| compatibility with glibc-only software | ⚠ needs porting sometimes | total |

⭐ **musl is the default.** [`../decisions/0003-static-musl-default.md`](../decisions/0003-static-musl-default.md).

⚠ **musl's known behavioural differences**, so a maintainer recognises them:

- **Locale.** Only `C` and `C.UTF-8`. Software formatting numbers or dates per
  locale behaves as if `LC_ALL=C`. For most command-line tools this is
  desirable; for anything user-facing it is a real difference.
- **`iconv`.** A much smaller set of encodings. Software converting legacy
  encodings can fail at run time.
- **Stack size.** musl's default thread stack has historically been much
  smaller than glibc's. Deeply recursive code can crash on musl and not on
  glibc. Set it explicitly where it matters.
- **`malloc`.** mallocng is smaller and slower under multi-threaded
  allocation churn than glibc's. ⚠ Measured elsewhere, not here; treat as
  documented rather than measured.
- **Backtraces.** No `backtrace()`. Crash handlers that print a stack trace
  produce nothing.

### 3.1 ⛔ Two rows above were corrected, and the correction matters

⛔ **This document said a static glibc binary "silently loses" NSS lookups, and
that glibc offers "very large" iconv coverage.** Both were reasoned from the
specification and neither was measured off this host. `polaris0xff/glibc-research`
measured both across 11 distributions pinned by digest, and both are wrong in
the same direction: the real failure is louder and host-dependent.

| | measured, by them |
| --- | --- |
| ⛔ NSS | a plain `gcc -static` glibc binary **loaded host `libnss_*.so.2` on 5 of 11**, and **died with SIGFPE on 2 of 11** (Arch, openSUSE Leap 15.6). ⚠ One of the five is a musl distribution. |
| ⛔ iconv | **1 of 12 encodings opened** on 8 distributions; the process **died on Debian 11, Debian 12 and Ubuntu 20.04** |

⭐ **The consequence is a supply-chain statement, not a compatibility note.** A
host shared object carrying `DT_NEEDED libc.so.6` enters a process built to have
no libc but its own, and which host decides whether that happens.

⭐ **It makes [`../decisions/0003-static-musl-default.md`](../decisions/0003-static-musl-default.md)
more right, not less.** ⭐ There is a third option, and
[`../interop/glibc-research.md`](../interop/glibc-research.md) is the whole
account: the evidence, what transfers each way, and what neither project has
shown.

---

## 4. Position independence

⛔ **A plain `-static` binary is `ET_EXEC` and is loaded at a fixed address, so
it does not get ASLR.** This is the most commonly missed security consequence
of static linking.

Measured: `gcc -static` produced `ET_EXEC` at 785,360 bytes; `gcc -static-pie`
produced `ET_DYN` at 822,552 bytes. Both have no `PT_INTERP`. **4.7% for ASLR.**

| toolchain | static-pie | note |
| --- | --- | --- |
| gcc, glibc | ⭐ `-static-pie` | measured working here |
| clang, glibc | `-static-pie` | needs a matching `libc.a` built with PIC |
| musl-gcc | ⚠ depends on the distribution's musl build | not measured here |
| Rust | `-C relocation-model=pic` with a static-pie target | ⚠ target-dependent |
| Go | ⭐ `-buildmode=pie` with `CGO_ENABLED=0` | internal linking supports it |
| Zig | `-fPIE` | |

⛔ **A package that cannot produce static-pie records `pie = false` in its
metadata** rather than shipping a fixed-address binary silently. The `hardened`
profile in
[`../format/variants-and-features.md`](../format/variants-and-features.md)
requires it.

---

## 5. What static linking breaks

⭐ **The complete list. Everything else is a detail.**

### 5.1 `dlopen`

⛔ **A static binary has no dynamic loader, so it cannot load a plugin at run
time.** Affected: anything with a plugin architecture, GPU drivers, PAM,
GTK/Qt theme engines, database client plugins.

⚠ **glibc's static `dlopen` is worse than an outright failure.** It links, and
at run time it requires the *exact* shared glibc it was linked against to be
present at the same path. It usually is not, and the failure is a mysterious
symbol error. The linker warns; the warning is one of hundreds in a normal
build.

**If a package needs `dlopen`, it is not a static package.** §7.

### 5.2 NSS

Covered in [`../format/dependencies.md`](../format/dependencies.md) §5.2, which
owns it. Summary: glibc's name-service switch uses `dlopen`, so a static glibc
binary reaches for the host's `libnss_*.so.2` at run time. ⛔ **It does not fail
quietly**: measured across 11 distributions it loaded host NSS modules on 5 and
crashed on 2. §3.1, and
[`../interop/glibc-research.md`](../interop/glibc-research.md) §2.1. musl and
pure-Go resolvers do not have the problem.

### 5.3 Certificates

Also [`../format/dependencies.md`](../format/dependencies.md) §5.1. A static
binary has no certificate store and must find the host's or embed one.

### 5.4 Security updates

⛔ **The cost that never goes away.** A dynamically linked system patches
`libfoo.so.1` once and every program is fixed. Here, forty packages containing
that library need forty rebuilds.

⭐ **This is not an argument against static linking; it is an argument for
automating the rebuild.** The mechanism is in
[`../security/supply-chain.md`](../security/supply-chain.md) §fan-out, and a
system that links statically without it is worse than a distribution.

### 5.5 Licensing

⚠ **Static linking can change your obligations, and this document is not legal
advice.**

| licence | dynamic | static |
| --- | --- | --- |
| MIT, BSD, Apache-2.0 | attribution | attribution |
| LGPL | ⭐ generally satisfied by dynamic linking | ⚠ typically requires shipping relinkable objects or the source |
| GPL | the whole work is GPL either way | same |
| MPL-2.0 | file-level copyleft | file-level copyleft |

⛔ **glibc is LGPL.** Statically linking it into a proprietary binary raises the
LGPL question directly. ⭐ musl is MIT, and this is a real secondary reason it
is the default.

**MUST**: `license` in the recipe lists every licence in the artefact,
including the libc.

---

## 6. Size

| technique | effect | cost |
| --- | --- | --- |
| ⭐ musl instead of glibc | 44x on the measured C case | musl's differences, §3 |
| ⭐ `strip --strip-all` | 24,744 to 17,816: 28% | ⛔ no symbols for debugging. §8. |
| `-Os` or `opt-level="z"` | 5% to 20% typically | slower code |
| link-time optimisation | 5% to 30% | much slower builds |
| `--gc-sections` with `-ffunction-sections -fdata-sections` | 5% to 20% | ⚠ can drop sections reached only by a linker script |
| `-C panic=abort` (Rust) | 10% to 15% | no unwinding, no `catch_unwind` |
| UPX compression | ⛔ 50% to 70% | ⛔ see below |

⛔ **UPX is not used by this system.** It is popular and the reasons against it
are concrete:

- it makes the binary self-modifying at start-up, which several sandboxes and
  hardened kernels refuse;
- ⛔ **antivirus products flag UPX-packed binaries as suspicious**, which turns
  into user support load;
- it defeats page-cache sharing: every process decompresses its own copy into
  private memory;
- it breaks `elfprobe`-style inspection, SBOM tooling and debug symbols;
- ⚠ it makes reproducibility harder to verify because the packed form obscures
  what changed.

⚠ **The studied system used UPX in 29 recipes at era 1**, counted at commit
`6f1cbb9` with `grep -rl '\bupx\b' binaries packages | wc -l`. The size win is
real. The trade is judged wrong here, and it is a judgement rather than a
measurement.

⚠ **That number was published as 133 in a draft of this page and it was
wrong.** 133 was the count of `upx` *tokens* across the tree, not of files
using it; the same recipe naming the tool four times counted four times. The
withdrawn claim is recorded in
[`../history/README.md`](../history/README.md).

---

## 7. ⛔ When NOT to link statically

**A package MUST NOT be forced static when any of these hold.** It sets
`portable = false` with a `portable-reason` instead.

| case | why | example |
| --- | --- | --- |
| it must `dlopen` a host-provided library | ⛔ impossible in a static binary | anything using a GPU driver |
| it is a plugin or a library other programs load | it is not a program | a shared library package |
| it needs full locale or `iconv` | musl does not have them, glibc-static barely | a text-processing tool for legacy encodings |
| it needs glibc's NSS integration | ⛔ unavailable | a tool that must resolve names through LDAP |
| the licence makes static linking impractical | §5.5 | proprietary software linking LGPL parts |
| it is very large and updated often | ⚠ the rebuild fan-out is worse than the portability gain | a browser |
| it needs system-integrated GUI toolkits | theme engines are `dlopen`ed | a GTK application |

⚠ **The honest position is that a static-binary distribution system is a good
fit for command-line and self-contained tools, and a poor fit for desktop
applications and anything plugin-based.** Systems that pretend otherwise end up
with the 92% disabled rate that
[`../history/references/README.md`](../history/references/README.md) records for
hand-written C build recipes.

⭐ **The alternative for the poor-fit cases is a self-contained bundle format**
that carries its own libraries and a loader: AppImage, or a Nix closure. This
specification does not build one, and
[`../open-questions.md`](../open-questions.md) records whether it should.

---

## 8. Debug symbols

⛔ **The default is stripped.** ⭐ **The symbols are not thrown away.**

```
build  ->  artifact (stripped)          published as the package
       ->  <name>.debug                 published as a referrer
```

| step | command |
| --- | --- |
| separate | `objcopy --only-keep-debug bin/rg rg.debug` |
| link | `objcopy --add-gnu-debuglink=rg.debug bin/rg` |
| strip | `strip --strip-all bin/rg` |

The `.debug` file is attached as a referrer with `artifactType`
`application/vnd.opk.debuginfo.v1`, fetched by `opk debug NAME`
([`../client/cli.md`](../client/cli.md) §3.3).

⚠ **`--add-gnu-debuglink` records a filename and a CRC, not a path.** A
debugger finds the file through its own search path, so the client places
fetched debug files where `gdb` looks.

⚠ **A `--strip-all` binary with no debug-link and no build-id is very hard to
symbolise after the fact.** Keeping the build-id is the cheapest way to keep
that option open, which is why §2.1 flags the toolchains that omit it.
