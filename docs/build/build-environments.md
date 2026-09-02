# build environments

The container images a build runs in, how they are pinned, and what a build can
reach from inside one.

---

## 1. ⛔ Images are pinned by digest

```toml
[build]
image = "docker.io/library/rust@sha256:b4b54b176a74db7e5c68fdfe6029be39a02ccbcfe72b6e5a3e18e2c61b57ae26"
```

**Not a tag. Ever.** A tag is mutable, so `rust:1.83` today and in six months
are different images, and a build against a tag measures a different toolchain
each time with nothing recording that it changed.

**Obtaining a digest:**

```sh
crane digest docker.io/library/rust:1.83-alpine
skopeo inspect docker://docker.io/library/rust:1.83-alpine | jq -r .Digest
podman pull docker.io/library/rust:1.83-alpine && \
  podman inspect --format '{{index .RepoDigests 0}}' docker.io/library/rust:1.83-alpine
```

⚠ **A digest pins the image, not the software in it.** `rust@sha256:...` is
byte-exact, and it may still contain an `apk` database that resolves to
different packages when the build runs `apk add`. That is the gap in
[`reproducibility.md`](reproducibility.md) §4.1.

### 1.1 Refreshing a digest

A pin ages: the toolchain stops receiving security fixes and eventually the
image is garbage-collected upstream.

| trigger | action |
| --- | --- |
| a scheduled quarterly review | a bot opens one pull request per image family with the new digest |
| a toolchain security advisory | ⭐ immediate, out of band |
| an image no longer resolvable | ⛔ urgent: builds are unreproducible from that point |

⛔ **Bumping an image digest bumps the package revision**, because it produces
different bytes. It is a rebuild, not a no-op.

⚠ **A digest that no longer resolves is worse than a stale one**, because the
package can no longer be rebuilt at all and the reproducibility check cannot
run. A mirror of every pinned base image is cheap insurance;
[`../ops/long-term-maintenance.md`](../ops/long-term-maintenance.md) §images.

---

## 2. Recommended base images

⚠ **These are recommendations with reasons, not a closed list.** A recipe may
pin any image.

| family | base | for |
| --- | --- | --- |
| ⭐ `rust:*-alpine` | Alpine, musl | Rust, static by default |
| ⭐ `golang:*-alpine` | Alpine, musl | Go, though Go needs little from the image |
| `alpine:*` plus `build-base` | Alpine, musl | C and C++ targeting musl |
| `debian:*-slim` | Debian, glibc | ⚠ software that genuinely needs glibc |
| `ghcr.io/rust-cross/cargo-zigbuild` | Alpine plus Zig | ⭐ Rust cross-compilation, per [`cross-compilation.md`](cross-compilation.md) §2.1 |
| a project-maintained builder | any | when the dependency set is large and stable |

⭐ **Alpine is the default because musl is the default libc**, and building
against musl on a glibc image means bringing your own musl.

⚠ **A minimal image is not automatically the right choice.** An image missing a
common dependency pushes work into `[build].deps`, which is the unpinned path.
A slightly larger image with the dependencies baked in is more reproducible
than a small one plus `apk add`.

### 2.1 A project-maintained builder image

⭐ **The strongest answer to the `deps` gap**: one image per toolchain family,
built from a pinned Dockerfile, carrying the common dependencies, published by
digest.

```dockerfile
FROM alpine:3.21@sha256:...
RUN apk add --no-cache \
      build-base=0.5-r3 \
      musl-dev=1.2.5-r9 \
      zlib-static=1.3.1-r2
```

⛔ **Pin the package versions too**, or the image is only as reproducible as the
day it was built.

⚠ **This is real ongoing work**, which is why it is a recommendation rather
than a requirement. A project with ten packages does not need it; a project with
a thousand does.

### 2.2 ⛔ The anti-pattern, with the evidence

The studied system's era-1 builder image is 830 lines of:

```dockerfile
RUN <<EOS
  set +e
  apk add acl --latest --upgrade --no-interactive 2>/dev/null
  apk add acl-dev --latest --upgrade --no-interactive 2>/dev/null
  ... 800 more
EOS
```

Three defects, each independently fatal to reproducibility:

| | |
| --- | --- |
| ⛔ `--latest --upgrade` | the image's contents differ every time it is built |
| ⛔ `set +e` with `2>/dev/null` | an install that fails is invisible and the build still succeeds |
| ⛔ no version pins | nothing records what was actually installed |

⭐ **This is why era 1 could not offer reproducible builds**, and the contrast
with the same project's later build repository, which pins by image digest, is
the clearest before-and-after in the whole corpus.

---

## 3. What a build can reach

Per `[build].network`
([`../format/build-manifest.md`](../format/build-manifest.md) §4.2).

### 3.1 `restricted`, the default allowlist

⛔ **Enforced by a proxy in the build network namespace, not by trusting the
recipe.**

| host | for |
| --- | --- |
| `crates.io`, `static.crates.io`, `index.crates.io` | Cargo |
| `proxy.golang.org`, `sum.golang.org` | Go modules |
| `registry.npmjs.org` | npm |
| `pypi.org`, `files.pythonhosted.org` | pip |
| `repo.maven.apache.org` | Maven |
| `dl-cdn.alpinelinux.org` | `apk` |
| `deb.debian.org`, `security.debian.org` | `apt` |

⛔ **Not on the list: arbitrary GitHub, arbitrary HTTP.** A build needing a
file from elsewhere declares it as `[[tool]]` or `[[extra]]`, which the builder
fetches and hashes *outside* the container.

⭐ **That is the mechanism that turns an unpinned download into a pinned
input**, and it is why the allowlist can be short.

⚠ **An allowlisted registry is still a supply-chain input.** Restricting the
network stops a build exfiltrating to an arbitrary host; it does not stop a
malicious crate. That is
[`../security/supply-chain.md`](../security/supply-chain.md).

### 3.2 A local cache

A caching proxy in front of the allowlist is **RECOMMENDED** for a project
building at volume: it reduces upstream load, survives an upstream outage, and
makes builds faster.

⛔ **The cache is keyed by the full request including any version**, and it
never serves a different artefact under the same key. A cache keyed loosely
enough to serve a variant is
[`../ops/failure-modes.md`](../ops/failure-modes.md) F7.

---

## 4. Runtime: podman, docker, and neither

| runtime | status |
| --- | --- |
| ⭐ podman, rootless | preferred; no daemon, no socket, no group membership |
| podman, rootful | works; ⚠ leaves root-owned files, which the builder handles |
| docker | works; ⚠ socket access is equivalent to root on the host |
| ⛔ none | `--no-container`, degraded, per [`build-system.md`](build-system.md) §6 |

**Detection**, in order: rootless podman, rootful podman, docker, then refuse
unless `--no-container` is passed.

⛔ **Probe the daemon, not the binary.** `docker --version` answers happily with
no daemon running and then every real command fails. The probe is `docker info`.
`experiments/10-probe-host.sh` does this and on the probe host reported
`podman_daemon ok 4.9.3 rootless=false` beside `docker_daemon UNAVAILABLE`,
which is exactly the state a `--version` check would have mis-reported.

⚠ **`--privileged` is never used.** The studied system's era-1 recipes run
`docker run --privileged --net=host` in the *recipe body*, which gives every
package's build script full host access. Isolation the recipe can switch off
is not isolation.

---

## 5. Caching build state

| cache | key | safe |
| --- | --- | --- |
| the pinned base image | its digest | ⭐ yes, digests are immutable |
| `[[tool]]` downloads | their sha256 | ⭐ yes |
| the source tree | source URL plus commit | ⭐ yes |
| Cargo registry, Go module cache | a lockfile hash | yes, ecosystems verify checksums |
| ⛔ compiler output, `target/` | | ⚠ see below |

⚠ **Caching compiler output across builds is where reproducibility goes to
die.** A stale object linked into a new build produces an artefact matching
neither. If it is done at all, the cache key must include the toolchain digest,
every compiler flag, and `SOURCE_DATE_EPOCH`, and the reproducibility job
**MUST** run with the cache cold. The default here is no compiler-output cache.
