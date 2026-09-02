# static compilation, by ecosystem

One file per ecosystem. Each answers the same questions, so two can be
compared without reading both in full.

The general theory and the measured cross-language results are
[`../static-linking.md`](../static-linking.md). These files are the
**per-ecosystem recipes and traps**.

---

## The files

| ecosystem | file | fully static | default libc | verdict |
| --- | --- | --- | --- | --- |
| C, C++ | [`c-cpp.md`](c-cpp.md) | ⭐ yes | musl | ⭐ excellent with musl |
| Rust | [`rust.md`](rust.md) | ⭐ yes | musl | ⭐ excellent |
| Go | [`go.md`](go.md) | ⭐ yes | none needed | ⭐ excellent, one trap |
| Zig | [`zig.md`](zig.md) | ⭐ yes | musl | ⭐ excellent, smallest measured |
| D | [`d.md`](d.md) | yes with LDC | musl | good with LDC, ⛔ not with gdc+glibc |
| Nim | [`nim.md`](nim.md) | ⭐ yes | musl | ⭐ good, compiles via C |
| Crystal | [`crystal.md`](crystal.md) | yes | musl | ⚠ workable, some friction |
| Swift | [`swift.md`](swift.md) | yes since 6.0 | musl | ⚠ newly viable, large |
| Ada | [`ada.md`](ada.md) | ⭐ yes | glibc, musl with work | good |
| Fortran | [`fortran.md`](fortran.md) | ⭐ yes | glibc, musl with work | good |
| JVM | [`jvm.md`](jvm.md) | ⭐ yes via GraalVM | musl | ⚠ heavy, real limits |
| .NET | [`dotnet.md`](dotnet.md) | ⭐ yes via NativeAOT | musl | ⚠ good, no reflection-heavy code |
| Python | [`python.md`](python.md) | ⚠ not really | glibc or musl | ⚠ bundle, do not claim static |
| Node.js | [`nodejs.md`](nodejs.md) | ⚠ not really | glibc or musl | ⚠ bundle a runtime |
| shell, scripts | [`shell.md`](shell.md) | ⚠ n/a | n/a | ⭐ ship the interpreter too |
| WebAssembly | [`wasm.md`](wasm.md) | ⭐ yes, differently | n/a | ⚠ a different portability model |
| everything else | [`other.md`](other.md) | varies | varies | Haskell, OCaml, Lua, Ruby, Perl, PHP, Erlang, Julia, Objective-C |

---

## What each file answers

⛔ **The same fourteen questions, in the same order**, so a maintainer can jump
to one section across files.

| # | question | why it matters |
| --- | --- | --- |
| 1 | is fully static linking possible | the base question |
| 2 | which libc, and which is recommended | decides portability and size |
| 3 | compiler and linker choices | what to pin |
| 4 | cross-compilation and target triples | can it reach architectures with no runner |
| 5 | CPU feature controls | does it silently target the build machine |
| 6 | external system libraries | what breaks static linking in practice |
| 7 | TLS and the certificate store | the most common run-time failure |
| 8 | DNS and name resolution | the second most common |
| 9 | locale | quiet behavioural differences |
| 10 | plugins and dynamic loading | whether static is possible at all |
| 11 | kernel floor | where "runs anywhere" stops |
| 12 | reproducibility | what varies per build |
| 13 | debugging and size | what stripping costs |
| 14 | ⭐ production defaults, failure modes, when not to | the actionable summary |

---

## Reading the evidence labels

⛔ **Every claim carries one**, so a reader knows which would survive contact
with a different machine.

| label | means |
| --- | --- |
| ⭐ **measured** | produced by `experiments/20-static-matrix.sh` on the host in `experiments/out/10-probe-host.txt` |
| **documented** | from the toolchain's own documentation or source; not run here |
| ⚠ **inferred** | a conclusion drawn from the two above, and labelled as a conclusion |

⭐ **Seven of the seventeen files carry measured results**, produced on the
probe host: `c-cpp`, `rust`, `go`, `zig`, `fortran`, `ada`, and `d`, whose
result is a measured link failure. The remaining ten are documented, and each
says so at the top rather than letting a reader assume otherwise.

⚠ **A measured row is one machine on one day.** It is stronger than a
documented one and it is not a guarantee about your machine.

---

## The two rules that apply to every ecosystem

⛔ **1. The gate is `PT_INTERP`, checked by reading the artefact.** Not the
compiler's flags, not `file`'s prose, not `ldd`. `tools/elfprobe.py`.

⛔ **2. Compiling is not evidence that it works.** Every artefact is run,
under emulation when it was cross-built. The Go row in
[`../static-linking.md`](../static-linking.md) §2 is a binary that compiled,
ran on the builder, and would have failed on a user's machine with a different
glibc.
