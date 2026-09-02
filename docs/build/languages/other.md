# Other ecosystems

**documented**, none measured here. Shorter entries for ecosystems that appear
in real package sets without warranting a file each. Each answers the same
question: can this produce a portable artefact, and what is the trap.

⚠ **Shorter does not mean easier.** Several of these are among the hardest.

---

## Haskell (GHC)

| | |
| --- | --- |
| fully static | ⭐ yes |
| libc | ⭐ musl on Alpine; ⚠ glibc static is fragile |
| recipe | `cabal build --enable-executable-static`, or `stack --docker` with a musl image |
| ⚠ trap | GHC's own libraries must be built against musl. ⭐ Alpine's `ghc` package is; a GHCup-installed GHC on Alpine is not. |
| cross-compilation | ⛔ poor; build in a container per architecture |
| reproducibility | ⚠ `cabal.project.freeze` pins; ⛔ GHC embeds the build path in some cases; `-fno-...` flags do not fully remove it |
| size | ⚠ large: 5 MB to 30 MB, the runtime and lazily-evaluated machinery |
| ⛔ when not to | it needs Template Haskell against a native library that cannot be statically linked |

⭐ **Haskell static binaries are a well-trodden path on Alpine** and the usual
failure is mixing a glibc GHC with a musl target.

---

## OCaml

| | |
| --- | --- |
| fully static | ⭐ yes |
| libc | ⭐ musl; `-ccopt -static` |
| recipe | `dune build --profile release`, with `(link_flags (-ccopt -static))` |
| ⚠ trap | ⭐ **`Unix.getpwnam` and friends go through libc NSS**, so a static glibc build loses them; musl is fine |
| cross-compilation | ⚠ awkward; `ocaml-cross` exists and is not mainstream. Build per architecture. |
| reproducibility | ⭐ good; `opam` lock files pin; ⚠ `dune` embeds paths unless `--root` is fixed |
| size | ⚠ moderate: 2 MB to 10 MB |
| ⛔ when not to | it uses `Dynlink` |

---

## Lua

| | |
| --- | --- |
| fully static | ⭐ yes, and ⭐ **the easiest in this file** |
| libc | ⭐ musl |
| recipe | ⭐ `luastatic main.lua libs/*.lua /usr/lib/liblua.a -I/usr/include/lua5.4` |
| ⚠ trap | C modules loaded with `require` at run time need to be linked in at build time |
| cross-compilation | ⭐ trivial: it is C |
| reproducibility | ⭐ good |
| size | ⭐ small: under 500 KB is ordinary |
| ⛔ when not to | it loads Lua C modules dynamically at run time |

⭐ **`luastatic` embeds Lua sources into a generated C file and links the
interpreter in**, which is the model other scripting languages wish they had.

---

## Ruby

| | |
| --- | --- |
| fully static | ⚠ not practically |
| libc | glibc or musl, dynamic |
| approaches | ⚠ ship a runtime tree; `ruby-packer` is unmaintained; `Tebako` is the current effort |
| ⚠ trap | native gems are shared objects and cannot be loaded by a static interpreter |
| ⛔ verdict | ⚠ ship a self-contained directory and set `portable = false`. Treat as [`python.md`](python.md). |

---

## Perl

| | |
| --- | --- |
| fully static | ⚠ possible, awkward |
| approaches | `staticperl`, `PAR::Packer` |
| ⚠ trap | ⭐ XS modules are C extensions; `staticperl` links them in and needs each one's build to cooperate |
| ⭐ note | a Perl script using only core modules is well served by shipping a static `perl`, per [`shell.md`](shell.md) §2 |
| ⛔ verdict | workable for core-only scripts, hard otherwise |

---

## PHP

| | |
| --- | --- |
| fully static | ⭐ yes |
| recipe | ⭐ `static-php-cli`: `./bin/spc build "curl,openssl,mbstring" --build-cli` |
| libc | ⭐ musl |
| ⚠ trap | extensions must be selected at build time; ⛔ `dl()` does not work |
| reproducibility | ⚠ the build compiles many C dependencies; pin the tool and its sources |
| size | ⚠ 10 MB to 30 MB depending on extensions |
| ⭐ verdict | ⭐ genuinely good for CLI tools, better than Python's or Ruby's story |

---

## Erlang and Elixir

| | |
| --- | --- |
| fully static | ⚠ no in the usual sense |
| approach | ⭐ an OTP **release** with `include_erts: true`: a self-contained directory |
| ⚠ trap | ⛔ the ERTS binaries in a release are dynamically linked; the release is portable across machines with the same libc, not across libcs |
| Burrito, Bakeware | ⭐ wrap a release into a single self-extracting binary |
| ⛔ verdict | ⚠ `portable = false`. Build a release per target libc. |

---

## Julia

| | |
| --- | --- |
| fully static | ⚠ no |
| approach | `PackageCompiler.jl` produces an app directory with a bundled Julia |
| ⚠ trap | ⛔ large: a bundled Julia app is 150 MB to 500 MB, because it carries LLVM |
| ⛔ verdict | ⚠ `portable = false`, and reconsider whether this belongs in a binary distribution system at all |

---

## Objective-C

| | |
| --- | --- |
| fully static | ⚠ on Linux, with GNUstep |
| ⚠ trap | ⛔ the Objective-C runtime and Foundation must be static too, and GNUstep's build does not make that easy |
| ⭐ note | on macOS this is a system framework question, not a static linking one; [`../../compatibility.md`](../../compatibility.md) |
| ⛔ verdict | ⚠ rare; treat per package |

---

## The pattern across all of these

⭐ **Ecosystems with a native compiler and no run-time dynamic loading link
statically. Ecosystems built around a run-time loader do not.**

That is the same split the historical corpus measured: `go` and `cargo` at 4%
and 7% disabled, hand-written C build systems at 92% and Python at 91.7%.
[`../../history/references/README.md`](../../history/references/README.md).

⛔ **For the second group, the honest answer is a self-contained bundle marked
`portable = false`**, not a claim of static linking that does not hold.
