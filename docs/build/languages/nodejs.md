# Node.js

**documented**, not measured as a packaged artefact.

---

## 1. Fully static: ⚠ no, in the same sense as Python

⛔ **There is no way to compile a JavaScript program to a single static native
binary.** Every approach ships a JavaScript engine. The honest framing is a
self-contained bundle.

## 2. The approaches

| approach | produces | verdict |
| --- | --- | --- |
| ⭐ Node SEA (Single Executable Application) | the official Node binary with the script injected | ⭐ **the supported path since Node 20** |
| ⭐ `bun build --compile` | a Bun binary with the script embedded | ⭐ practical, and it is Bun not Node |
| Deno `deno compile` | a Deno binary with the script embedded | ⭐ practical, and it is Deno not Node |
| ⚠ `vercel/pkg` | a patched Node with a virtual filesystem | ⛔ archived; do not adopt |
| `nexe` | similar | ⚠ less maintained |
| ⚠ a bundled `node_modules` tree plus a Node binary | a directory | ⭐ simplest and largest |

### 2.1 Node SEA

```sh
node --experimental-sea-config sea-config.json
cp "$(command -v node)" out/app
npx postject out/app NODE_SEA_BLOB sea-prep.blob \
  --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2
```

⚠ **The base `node` binary is what determines linkage.** Official Node builds
for Linux are dynamically linked against glibc. ⭐ Unofficial musl builds exist
and are what a static artefact needs.

⭐ **Node SEA requires bundling to a single file first**, with esbuild or
similar, because it injects one script rather than a `node_modules` tree.

### 2.2 Bun and Deno

```sh
bun build --compile --minify --sourcemap --target=bun-linux-x64-musl \
  ./src/index.ts --outfile out/app
```

```sh
deno compile --allow-net --allow-read --target x86_64-unknown-linux-musl \
  -o out/app src/main.ts
```

⭐ **Both have a `-musl` target and produce a binary with no `PT_INTERP`.**
⚠ **Both are a different runtime from Node**, and a program using Node-specific
APIs may not run under either. That is a compatibility question to settle
before choosing this path, not after.

⭐ **`deno compile --allow-*` bakes a permission set into the binary**, which is
a genuinely useful property for a distributed tool and has no equivalent
elsewhere in this document.

## 3. Runtime and libc

| runtime | musl build | note |
| --- | --- | --- |
| Node official | ⚠ unofficial builds only | glibc by default |
| ⭐ Bun | ⭐ yes, `-musl` targets | |
| ⭐ Deno | ⭐ yes, `*-linux-musl` targets | |

## 4. Cross-compilation

⭐ **Bun and Deno cross-compile by target flag**, which is unusually good for
this ecosystem.

⚠ **Node SEA does not**: it injects into a `node` binary for one platform, so
the correct `node` for the target must be obtained separately.

⛔ **Native addons (`.node` files) do not cross-compile.** A dependency with
one must be built per target.

## 5. CPU features

⚠ Not controlled by the packager. The runtime's JIT dispatches at run time,
which ⭐ removes the `SIGILL` class of problem entirely.

## 6. External libraries

⛔ **Native addons are the blocker.** A `.node` file is a shared object loaded
with `dlopen`; a statically linked runtime cannot load one.

| dependency kind | works in a compiled binary |
| --- | --- |
| ⭐ pure JavaScript or TypeScript | ⭐ yes |
| a WebAssembly module | ⭐ yes, and this is the best answer |
| ⛔ a native addon | ⚠ Bun and Deno have partial support; Node SEA needs it beside the binary |

⭐ **Preferring a WebAssembly build of a native dependency turns a hard problem
into a solved one**, and increasingly the ecosystem provides them.

## 7. TLS and certificates

⚠ **Node bundles its own CA store, compiled into the binary.** It honours
`NODE_EXTRA_CA_CERTS`, and since Node 22 `--use-system-ca` reads the host
store.

⛔ **The bundled store is frozen at the runtime's build time**, so a package
shipping an old Node ships an old root set. ⭐ Set `--use-system-ca` where the
runtime supports it.

## 8. DNS

⚠ **Node uses c-ares for `dns.resolve*` and libc `getaddrinfo` for
`dns.lookup`**, and they behave differently. `dns.lookup`, which
`http.request` uses by default, goes through libc, so musl's resolver applies.

## 9. Locale

⛔ **`Intl` needs ICU.** Node builds come in `full-icu` and `small-icu`
variants; a small-icu build formats everything as English.

⚠ **A program using `Intl.DateTimeFormat` with a locale and running on a
small-icu build silently produces English output.** Check which variant is
bundled.

## 10. Plugins

⭐ **Dynamic `import()` of a bundled module works.** ⛔ Importing something the
user installed afterwards does not, because the bundle carries its own module
graph.

## 11. Kernel

**documented**: inherits the libc floor.

## 12. Reproducibility

| control | |
| --- | --- |
| ⭐ dependencies | ⛔ `npm ci` against a committed `package-lock.json`, or `pnpm install --frozen-lockfile` |
| ⛔ `postinstall` scripts | ⚠ arbitrary code at install time; `--ignore-scripts` where possible |
| bundler output | ⚠ esbuild and rollup are deterministic given the same input; ⛔ check, do not assume |
| ⚠ the runtime binary | pinned by its download's sha256 |
| timestamps | ⚠ some bundlers embed a build time in a banner; disable it |

⛔ **`npm install` is not `npm ci`.** The first may update the lockfile.

⚠ **`postinstall` scripts are the largest supply-chain surface in this
ecosystem.** They run arbitrary code from any transitive dependency at build
time, inside the build container. `--ignore-scripts` is safer and breaks
packages that genuinely need it.

## 13. Debugging and size

⚠ **Bundles are large**: a Node SEA binary is the whole Node runtime, typically
80 MB to 110 MB. Bun and Deno binaries are 50 MB to 100 MB. Minification of the
script is noise against that.

⭐ **A source map shipped as a separate referrer** keeps stack traces readable
without inflating the artefact.

## 14. ⭐ Production defaults, failure modes, when not to

**Defaults**

```toml
[package]
portable        = false
portable-reason = "ships a JavaScript runtime; only the musl builds are fully static"

[build]
image = "docker.io/oven/bun@sha256:..."

[build.script]
run = """
bun install --frozen-lockfile --ignore-scripts
bun build --compile --minify --target=bun-linux-x64-musl \
  ./src/index.ts --outfile out/app
"""

[verify]
run = ["--version"]
```

**Failure modes**

| symptom | cause |
| --- | --- |
| ⛔ a native addon fails to load | it is a shared object; use a WebAssembly build or ship it beside the binary |
| dates format in English regardless of locale | ⚠ a small-icu runtime |
| TLS fails against a newer certificate authority | ⛔ the runtime's bundled CA store is old; use `--use-system-ca` |
| a rebuild differs | `npm install` instead of `npm ci`, or a bundler banner with a timestamp |
| the binary is 100 MB | ⚠ expected |
| a build step ran unexpected code | ⛔ a `postinstall` script |

**⛔ When not to**: the program depends on a native addon with no WebAssembly
alternative; it uses Node-specific APIs and Bun or Deno are the only static
paths available; size is a hard constraint.
