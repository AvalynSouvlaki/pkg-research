# cross-compilation

Building for an architecture the builder is not, and proving the result works
without owning that hardware.

---

## 1. Why it is unavoidable

⛔ **GitHub-hosted runners provide Linux on x86-64 and aarch64. Nothing else.**
Limit L3 in [`../architecture.md`](../architecture.md). Every other
architecture is cross-compiled or not supported.

| host triple | how it is built |
| --- | --- |
| `x86_64-linux` | ⭐ natively |
| `aarch64-linux` | ⭐ natively, on GitHub's arm runners |
| `riscv64-linux` | cross-compiled, verified under emulation |
| `loongarch64-linux` | cross-compiled, verified under emulation |
| `armv7-linux` | cross-compiled, verified under emulation |
| non-Linux targets | [`../compatibility.md`](../compatibility.md) |

⚠ **Native is preferred wherever a runner exists**, because it removes the
whole class of "it compiled but does not run".

---

## 2. Three approaches

| approach | works for | cost |
| --- | --- | --- |
| ⭐ a language with a built-in cross-compiler | Go, Zig, Rust for pure targets | free |
| ⭐ Zig as a C cross toolchain | anything C or C++ | one tool |
| a GNU cross toolchain | anything | ⚠ one toolchain per target |
| emulation under QEMU | anything | ⛔ 10x to 50x slower |

### 2.1 Language-native

**Go.** ⭐ The best case. Nothing to install.

```sh
CGO_ENABLED=0 GOOS=linux GOARCH=riscv64 \
  go build -trimpath -ldflags="-s -w -buildid=" -o out/prog .
```

⛔ **`CGO_ENABLED=0` is what makes it free.** With cgo enabled, Go needs a C
cross toolchain and the result is dynamically linked.

**Rust.** The Rust part cross-compiles after `rustup target add`. ⚠ **Any crate
with C in it needs a C cross toolchain**, which `rustup` does not provide, and
that is most non-trivial dependency trees: `ring`, `openssl-sys`, `libz-sys`,
anything with a `build.rs` invoking `cc`.

```sh
rustup target add riscv64gc-unknown-linux-musl
cargo build --release --locked --target riscv64gc-unknown-linux-musl
```

⭐ **`cargo-zigbuild` closes that gap** by supplying Zig as the C compiler:

```sh
cargo zigbuild --release --locked --target riscv64gc-unknown-linux-musl
```

⚠ **This is exactly what the studied system does for riscv64**, for the reason
its README states: "zig supplies a C cross toolchain for every target, which
plain `rustup target add` does not, and which any crate carrying C needs."

**Zig.** ⭐ Cross-compiles to every supported target with no extra install, and
ships musl and glibc headers for many targets.

```sh
zig build-exe main.zig -O ReleaseSafe -target riscv64-linux-musl
```

### 2.2 Zig as a C cross toolchain

⭐ **The single highest-leverage tool for this problem.** One 47 MB download
replaces a matrix of GNU cross toolchains.

```sh
zig cc  -target riscv64-linux-musl -O2 -static hello.c -o hello
zig c++ -target aarch64-linux-musl -O2 -static hello.cpp -o hello
```

Measured here: `zig cc -target x86_64-linux-musl` produced a 204,192-byte
static binary with no `PT_INTERP`, from `experiments/20-static-matrix.sh`.

⚠ **Known friction**, so it is not oversold:

- Zig pins the glibc version per target; a target needing a newer one than Zig
  ships needs a Zig upgrade.
- Some autotools projects reject `zig cc` because it does not accept every gcc
  flag. `CC="zig cc"` plus a wrapper script that filters unknown flags is the
  usual workaround.
- ⚠ Zig's C ABI support for less common targets is less exercised than GCC's.

### 2.3 GNU cross toolchains

For projects that need a conventional `gcc`.

```sh
apt-get install -y gcc-riscv64-linux-gnu
export CC=riscv64-linux-gnu-gcc AR=riscv64-linux-gnu-ar
./configure --host=riscv64-linux-gnu --build=x86_64-linux-gnu
make
```

⚠ **`--host` is what you are building FOR and `--build` is what you are
building ON.** Getting them the wrong way round produces a native binary and a
confusing failure much later.

⚠ **A GNU cross toolchain targets glibc.** Producing a static musl binary this
way needs a musl cross toolchain, from `musl.cc` or built with `musl-cross-make`.

### 2.4 Emulation

⛔ **Not for building. For verifying.** Compiling under `qemu-user` is 10x to
50x slower and turns a five-minute build into hours.

```sh
qemu-riscv64-static ./out/prog --version
```

⭐ **Static binaries are the easy case for `qemu-user`**: no loader, no library
paths, nothing to configure.

---

## 3. ⛔ Verifying a cross-built artefact

**Compiling is not evidence that the result works, and cross-compiling is
exactly when a broken artefact goes unnoticed**, because nobody on the build
path can run it.

Three checks, in order of cost:

| # | check | catches |
| --- | --- | --- |
| 1 | ⭐ `e_machine` matches the target | a build that silently produced the builder's architecture |
| 2 | ⭐ no `PT_INTERP` | a cross-build that fell back to dynamic linking |
| 3 | it runs under `qemu-user` | everything the first two cannot see |

Checks 1 and 2 are `tools/elfprobe.py` and are mandatory. Check 3 is
`[verify].run` and is opt-in per package.

⚠ **Check 1 is not paranoia.** A `configure` script that fails to detect the
cross setup falls back to the native compiler and the build succeeds. The
artefact is the wrong architecture and every other check passes.

⚠ **`qemu-user` is not the target machine.** It emulates user-space
instructions against the host kernel, so it does not exercise the target's
kernel, its page size, or its actual CPU features. A binary passing under
emulation can still fail on real hardware. ⭐ Where real hardware is available,
a periodic smoke test on it is worth more than any amount of emulation, and
[`../open-questions.md`](../open-questions.md) records that this repository had
none.

### 3.1 Registering emulation

⚠ **Do not rely on `binfmt_misc` being registered on the runner.** Invoking
`qemu-<arch>-static` explicitly works with no kernel configuration, no
privileged setup, and no dependence on a service having succeeded.

⛔ **`systemd-binfmt.service` has been observed to report success with zero
handlers registered**, because the path it writes to was unusable. Every green
signal was present and cross-architecture execution had never worked. Invoking
the emulator directly removes that whole failure mode.

---

## 4. Byte order and word size

⚠ Every target this system lists is 64-bit little-endian except `armv7-linux`,
which is 32-bit little-endian. Big-endian targets exist and are not in the
supported set.

**A package MUST NOT assume**:

- pointer size, or that `long` is 64 bits;
- that unaligned access is free;
- that `char` is signed. ⛔ It is unsigned on ARM and signed on x86, and this
  causes real, subtle bugs in code that stores a byte in a `char` and compares
  it against a negative value.

⚠ **These are upstream correctness problems, not packaging problems.** The
packaging system's job is to catch them with check 3 and report them upstream,
not to patch around them.

---

## 5. CI shape

```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - host: x86_64-linux      runner: ubuntu-latest
      - host: aarch64-linux     runner: ubuntu-24.04-arm
      - host: riscv64-linux     runner: ubuntu-latest    # cross
      - host: loongarch64-linux runner: ubuntu-latest    # cross
```

⛔ **`fail-fast: false`.** One architecture failing must not cancel the others;
a package available on three of four architectures is better than none, and the
failure record for the fourth tells a user why.

⚠ **Cross jobs are cheap and native arm jobs are not always available.** Where
an arm runner is unavailable, aarch64 is cross-compiled by the same path as
riscv64, and the metadata records that it was cross-built so the reproducibility
job compares like with like.
