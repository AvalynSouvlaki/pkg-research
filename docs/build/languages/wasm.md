# WebAssembly

**documented**. ⚠ **A different portability model, not a smaller static
binary**, and confusing the two is the mistake this file exists to prevent.

---

## 1. What WebAssembly changes

⛔ **A `.wasm` module is not a native executable.** It needs a runtime. So it
does not replace a static binary; it replaces the *architecture* dimension of
the problem with a *runtime* dimension.

| | a static native binary | a Wasm module |
| --- | --- | --- |
| runs on | one architecture, any Linux | ⭐ any architecture, given a runtime |
| needs on the host | ⭐ nothing | ⛔ a Wasm runtime |
| artefacts per release | ⚠ one per architecture | ⭐ **one** |
| startup | ⭐ immediate | ⚠ compile or load time |
| speed | ⭐ native | ⚠ typically 10% to 100% slower |
| syscalls | ⭐ everything | ⚠ what WASI exposes |

⭐ **The one-artefact property is the real attraction**, and it is why this is
worth specifying rather than dismissing.

## 2. Two ways to use it here

### 2.1 ⭐ Compile Wasm to a native binary, ahead of time

⭐ **This is the mode that fits this system**, because the published artefact is
an ordinary static native binary and everything else in the specification
applies unchanged.

```sh
# Compile a wasm module to a native object, then link it statically.
wasmtime compile --target x86_64-unknown-linux-musl app.wasm -o app.cwasm
```

⭐ **`wasm2c` plus a C compiler is the most portable route**, because the output
is C and every target this system supports has a C compiler:

```sh
wasm2c app.wasm -o app.c
musl-gcc -O2 -static app.c wasm-rt-impl.c -o out/app
```

⚠ **Both add a layer.** The result is larger and slower than compiling the
original source natively, so this is for cases where the original source cannot
be compiled natively, not as a default.

### 2.2 Ship the module and require a runtime

```toml
[package]
portable        = false
portable-reason = "a WebAssembly module; requires a WASI runtime on the host"

[runtime]
requires = ["wasi-runtime"]
```

⚠ **This makes the package depend on something the host may not have**, which
is exactly what this system exists to avoid. ⭐ It is defensible when the
runtime is itself distributed as a static binary by this system, so
`opk install wasmtime` satisfies it.

## 3. Producing a module

| source | toolchain |
| --- | --- |
| ⭐ Rust | `--target wasm32-wasip1`, ⭐ first-class |
| ⭐ C, C++ | `wasi-sdk`, or `zig cc -target wasm32-wasi` |
| ⭐ Zig | `-target wasm32-wasi` |
| Go | ⭐ `GOOS=wasip1 GOARCH=wasm`, since Go 1.21 |
| TinyGo | ⭐ much smaller output than standard Go |
| ⚠ Python, Ruby | possible through a compiled interpreter; large |
| .NET | ⚠ `wasi-experimental` |

```sh
rustup target add wasm32-wasip1
cargo build --release --locked --target wasm32-wasip1
```

## 4. WASI, and what is missing

⚠ **WASI preview 1 is what most runtimes implement, and it is limited.**

| capability | preview 1 |
| --- | --- |
| ⭐ files, directories | yes, through preopened directories |
| ⭐ stdin, stdout, stderr | yes |
| ⭐ clocks, random | yes |
| environment, arguments | yes |
| ⛔ sockets | ⚠ not in preview 1; runtime-specific extensions exist |
| ⛔ threads | ⚠ experimental |
| ⛔ subprocesses | no |
| ⛔ signals | no |

⛔ **No sockets in preview 1 is the constraint that rules out most network
tools.** WASI preview 2 and `wasi-sockets` address it and are not yet uniformly
implemented.

## 5. Capability security

⭐ **The genuinely novel property.** A Wasm module has no ambient authority: it
can only touch directories that were explicitly preopened.

```sh
wasmtime run --dir=/data::/data app.wasm
```

⭐ **This is stronger than anything a native static binary offers**, and it maps
directly onto the permission model in
[`../../security/sandboxing.md`](../../security/sandboxing.md). A tool
distributed as Wasm can be run with exactly the filesystem access it needs.

## 6. CPU features and architecture

⭐ **The module is architecture-neutral.** SIMD is available as a Wasm feature
(`+simd128`), and the runtime maps it onto the host's instructions. ⚠ A module
built with SIMD needs a runtime that supports it.

## 7. TLS, DNS, locale

⛔ **All three are absent or runtime-specific in preview 1**, following from
§4. A module needing TLS is doing it through a runtime extension, which makes
it runtime-specific and undermines the portability argument.

## 8. Reproducibility

⭐ **Good.** Wasm is a deterministic target: no ASLR, no address-dependent
output, no build path in the module unless a tool put it there.

⚠ **The usual ecosystem controls still apply**: `Cargo.lock`,
`--remap-path-prefix`, `SOURCE_DATE_EPOCH`.

⭐ **A Wasm module is a good candidate for a reproducibility canary**, because
it removes the architecture variable entirely.

## 9. Size and debugging

⚠ **Modules are small**: a Rust hello-world `wasm32-wasip1` module is typically
under 100 KB after `wasm-opt -Oz`, and a TinyGo one smaller still.

⛔ **A native binary produced from a module is not small**, because it carries
the runtime or the generated C plus its support library.

DWARF in Wasm is supported by some runtimes and tooling is thinner than native.

## 10. ⭐ Production defaults, failure modes, when not to

**Defaults**

⭐ **Do not use WebAssembly as the default distribution format.** Use it when:

- a package must reach an architecture with no toolchain and no runner;
- the capability sandbox is wanted for its own sake;
- the program is a pure computation with no network and no subprocesses.

Where it is used, ⭐ **prefer §2.1**: compile to a native static binary so the
rest of this specification applies unchanged.

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ the program cannot open a socket | ⚠ WASI preview 1; expected |
| it cannot read a file it can see | ⭐ the directory was not preopened; expected and correct |
| it is much slower than native | ⚠ expected; measure before choosing this |
| the native binary from a module is huge | the runtime or generated C ships with it |
| threads do not work | ⚠ experimental in preview 1 |

**⛔ When not to**: it needs sockets, subprocesses, signals or threads;
performance matters; the host cannot be relied on to have a runtime and the
ahead-of-time route is too large.
