# Python

**documented**, not measured as a packaged artefact. ⚠ **Python has 12 of 12
disabled recipes in the historical corpus**, the worst rate of any ecosystem
measured, and this file explains why rather than pretending otherwise.

---

## 1. Fully static: ⚠ not really, and saying otherwise is the mistake

⛔ **There is no way to compile a Python program to a single static native
binary with the same properties as a Go or Rust build.** Every approach ships an
interpreter, and each has a different failure surface.

⭐ **The honest framing: the artefact is a self-contained bundle, and the
package declares `portable = true` only when the bundle genuinely needs nothing
from the host.**

## 2. The approaches

| approach | produces | static | verdict |
| --- | --- | --- | --- |
| ⭐ PyInstaller onefile | a self-extracting binary | ⚠ no; needs a host libc | ⭐ **most practical** |
| PyInstaller onedir | a directory tree | no | ⭐ faster startup, more files |
| ⭐ python-build-standalone + a launcher | a relocatable interpreter tree | ⚠ the interpreter is dynamically linked unless the musl-static build is used | ⭐ **most predictable** |
| Nuitka | compiles to C, then a binary | ⚠ possible to link statically with work | good, slow builds |
| ⛔ StaticX | wraps a dynamic binary with its libc | ⚠ produces something that runs anywhere | ⛔ see §2.1 |
| shiv, pex | a zipapp | ⛔ no; needs a host Python | ⚠ only where Python is guaranteed |
| ⚠ Cython to a binary | a native binary for compiled modules | ⚠ still needs the interpreter | not a packaging strategy on its own |

### 2.1 ⛔ StaticX, and why it is not used here

StaticX takes a dynamically linked binary and bundles its loader and libraries
into a self-extracting wrapper. It works, and the historical corpus used it.

Problems, in order of seriousness:

- ⛔ it extracts to a temporary directory at every start, which fails on a
  `noexec` `/tmp` and leaves debris;
- ⛔ the bundled glibc must match the kernel's expectations; it can break on a
  much newer or older kernel;
- ⚠ it defeats SBOM and provenance tooling: what is inside is a bundled
  filesystem, not declared inputs;
- ⚠ start-up cost on every invocation.

⭐ **The supported answer is python-build-standalone's musl-static
interpreter**, which is a genuine static build rather than a wrapper.

## 3. Interpreter and libc

| | |
| --- | --- |
| ⭐ python-build-standalone | publishes `x86_64-unknown-linux-musl` builds, ⭐ including static ones |
| distribution Python | glibc, dynamic |
| ⛔ pin | by the release tarball's sha256, as a `[[tool]]` |

⚠ **A statically linked CPython cannot load C extension modules that are
shared objects.** Extensions must be built into the interpreter, which
python-build-standalone's static builds do for the standard set and not for
arbitrary third-party wheels.

⭐ **That is the central constraint of this ecosystem**: a pure-Python
dependency tree is easy, and one containing `numpy` or `cryptography` is not.

## 4. Cross-compilation

⛔ **Effectively unavailable.** Wheels with native code are built per platform,
and cross-compiling them is not a supported workflow for most projects.

⭐ **Build in a container for the target architecture**, natively where a runner
exists and under emulation otherwise.

## 5. CPU features

⚠ **Not controlled by the packager.** Wheels from PyPI are built by their
maintainers with their own flags. A `manylinux` wheel targets a baseline; a
locally built one may not.

⛔ **`pip install` compiling from source on the build machine can produce
`-march=native` code** if the project's `setup.py` says so. Build with
`CFLAGS` set explicitly.

## 6. External libraries

⚠ **The dependency tree is the artefact.** `pip install` pulls wheels
containing prebuilt shared objects, and a bundle contains all of them.

⛔ **`auditwheel` is the tool that makes this tractable**: it inspects a wheel,
copies in the shared libraries it needs, and rewrites the `RPATH`. A bundle
built without it can depend on host libraries that are not there.

## 7. TLS and certificates

⚠ **Two stores, and they disagree.** `ssl` uses OpenSSL's paths;
`certifi`, which `requests` and `httpx` use by default, ships **its own CA
bundle inside the wheel**.

⛔ **A bundled `certifi` is frozen at build time**, exactly like Rust's
`webpki-roots`. A package shipping it must either update on a schedule or set
`SSL_CERT_FILE` to the host store.

## 8. DNS

Through libc `getaddrinfo`. musl's resolver under a musl interpreter.

## 9. Locale

⚠ **Python 3.7 and up coerce the C locale to UTF-8 by default**
(`PYTHONCOERCECLOCALE`), which mostly removes the classic `UnicodeDecodeError`
on filenames. ⭐ Set `PYTHONUTF8=1` in the launcher to make it explicit.

## 10. Plugins

⭐ **Python's whole model is dynamic import**, so entry points and plugins work
inside a bundle as long as they were bundled. ⛔ A plugin the user installs
afterwards does not, because the bundle has its own site-packages.

## 11. Kernel

**documented**: inherits the libc floor.

## 12. Reproducibility

⚠ **Weak, and it takes deliberate work.**

| control | |
| --- | --- |
| ⭐ dependencies | ⛔ `pip install --require-hashes -r requirements.txt`. Without hashes, nothing is pinned. |
| ⭐ `.pyc` files | ⛔ `PYTHONDONTWRITEBYTECODE=1`, or `SOURCE_DATE_EPOCH` plus `--invalidation-mode checked-hash` |
| ⚠ `PYTHONHASHSEED` | set to `0` for any code generation that iterates a set or dict |
| zip ordering | PyInstaller and zipapps embed archives; ⚠ ordering and timestamps must be normalised |
| ⚠ the interpreter | pinned by its tarball hash |

⛔ **`.pyc` files embed the source's mtime by default**, so a bundle containing
them is not reproducible unless the invalidation mode is changed or they are
excluded.

## 13. Debugging and size

⚠ **Bundles are large**: 15 MB to 50 MB is ordinary once the interpreter and
the standard library are in. `--exclude-module` for unused standard-library
packages, and `strip` for the shipped shared objects.

⚠ **A traceback from a frozen bundle points at paths inside the bundle**, which
is confusing without a note explaining it.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[package]
portable        = false
portable-reason = "ships a Python interpreter; needs a host libc unless the musl-static interpreter is used"

[build]
image = "docker.io/library/alpine@sha256:..."
deps  = ["build-base", "musl-dev"]

[[tool]]
name   = "python-standalone"
url    = "https://github.com/astral-sh/python-build-standalone/releases/download/.../cpython-3.12-x86_64-unknown-linux-musl-install_only.tar.gz"
sha256 = "..."

[build.env]
PYTHONDONTWRITEBYTECODE = "1"
PYTHONHASHSEED = "0"
SOURCE_DATE_EPOCH = "$SOURCE_DATE_EPOCH"

[build.script]
run = """
python -m pip install --require-hashes -r requirements.txt --target vendor/
python -m pip install --require-hashes pyinstaller
pyinstaller --onefile --strip --clean --noconfirm \
  --distpath out -n app src/main.py
"""
```

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ fails on `noexec /tmp` | a self-extracting bundle; use onedir or a static interpreter |
| a wheel's shared object is missing on the user's host | ⛔ `auditwheel` was not used |
| TLS fails after a year | ⚠ a bundled `certifi` frozen at build time |
| a rebuild does not reproduce | ⛔ `.pyc` mtimes, or unhashed requirements |
| the bundle is 40 MB | ⚠ expected |
| ⛔ a C extension cannot load | a statically linked interpreter cannot load shared extension modules |

**⛔ When not to**: the program needs C extensions that a static interpreter
cannot load, and a self-extracting bundle is unacceptable; the user is expected
to install plugins into it.

⭐ **Where the program is a pure-Python command-line tool with few
dependencies, this ecosystem works well.** Where it has a large scientific
stack, distributing it as a static binary is fighting the ecosystem, and that
is what the historical 91.7% disabled rate records.
