# build system

⭐ **The builder's contract.** What it reads, what it guarantees about the
environment it creates, what it does with the recipe's script, and what it
checks before anything can be published.

The recipe's fields are [`../format/build-manifest.md`](../format/build-manifest.md).
Determinism is [`reproducibility.md`](reproducibility.md). Base images are
[`build-environments.md`](build-environments.md). This document is the
**execution contract**.

---

## 1. Position

⛔ **The builder is the only component that executes recipe content.**
Invariant I1, [`../architecture.md`](../architecture.md). Everything else in
the system reads recipes as data.

```
opk build <package> --host <host> [--profile release] [--out dist/]
```

Inputs: a validated recipe, a host triple, a profile, a container runtime.
Output: an artefact tree, a build log, and a provenance record. ⛔ Or a failure
with a log and no artefact.

---

## 2. The nine phases

⛔ **In this order. A phase failing stops the build.**

| # | phase | on failure |
| --- | --- | --- |
| 1 | validate the recipe | ⛔ no container is started |
| 2 | prepare the workspace | fail |
| 3 | fetch and verify source | fail, naming what mismatched |
| 4 | apply patches | fail, naming the patch |
| 5 | fetch and verify tools | fail, naming the tool |
| 6 | run the script in the container | fail, keeping the log |
| 7 | collect declared artefacts | ⛔ fail if any declared path is missing |
| 8 | verify the artefacts | ⛔ fail; this is the gate that catches a lying build |
| 9 | assemble and record | fail |

⭐ **Phase 8 is the one that makes the escape hatch tolerable.** The script may
do anything; phase 8 decides whether what it produced is publishable, and it
does not consult the script.

### 2.1 Validate

Full validation per [`../format/build-manifest.md`](../format/build-manifest.md),
plus:

- the requested host is in `[build].hosts`;
- `[build.target]` has an entry for it, if the table exists;
- the container runtime is available and can pull the pinned image.

⛔ **No network fetch and no container start happens before validation
completes.** A malformed recipe must not be able to cause a download.

### 2.2 Workspace

```
<workspace>/
  src/        the source tree; mounted at /build in the container
  tools/      pinned tools; mounted at /tools
  stage/      collected artefacts; ⛔ never mounted into the container
  logs/
```

⛔ **`stage/` is outside the container.** Collection happens on the host after
the container exits, so the script cannot write directly into what gets
published.

⚠ **A previous run's workspace is removed before a new one starts, and this is
harder than it looks.** The container runs as root, so under a rootful runtime
it leaves files the calling user cannot delete. The builder retries the removal
inside the image as root. This is not a hypothetical; the studied system's
`build.py` carries the same workaround with the same comment.

### 2.3 Fetch and verify source

**Git:**

```sh
git init -q src
git -C src remote add origin "$URL"
git -C src fetch -q --depth 1 origin "$COMMIT"
git -C src checkout -q FETCH_HEAD
test "$(git -C src rev-parse HEAD)" = "$COMMIT"   # ⛔ the check
```

⛔ **The equality check after fetch is not redundant.** Fetching a commit by
its object name is normally safe, and the check is what makes that a verified
property rather than an assumption about the server, the transport and the
local git. It costs one command.

⚠ **`--depth 1` on a commit requires the server to allow fetching arbitrary
objects.** Where it refuses, the builder falls back to a shallow fetch of the
default branch and deepens until the commit is present, and it logs that it
did, because the fallback is slower and the log is where that shows up.

**URL:** download, hash with SHA-256, compare against `[source].sha256`, then
extract. ⛔ Extraction refuses entries with absolute paths, `..` components,
symlinks pointing outside the tree, or device nodes.

⚠ **Archive extraction is a classic vulnerability surface** and the defence is
the extractor's, not the recipe's. Python's `tarfile` has a `data` filter for
exactly this; anything hand-rolled reimplements a checklist that has been got
wrong many times.

### 2.4 Patches

Applied in array order with `patch -p<strip>`, each verified against its
`sha256` first. ⛔ A patch that does not apply cleanly fails the build; there
is no fuzz and no `--forward`.

### 2.5 Tools

Each `[[tool]]` downloaded, SHA-256 verified, `chmod 0755`, placed in
`tools/`. ⛔ `PATH` inside the container puts `/tools` first, so a tool
shadows a same-named one from the image, which is the point of declaring it.

### 2.6 Run

```sh
podman run --rm \
  --network "$NETWORK_MODE" \
  -v "$WORKSPACE/src:/build:z" \
  -v "$WORKSPACE/tools:/tools:ro,z" \
  -w /build \
  --memory "$MEMORY" \
  --env-file "$ENVFILE" \
  "$IMAGE_DIGEST" \
  sh -euc "$SCRIPT"
```

| flag | why |
| --- | --- |
| `--rm` | the container is disposable |
| `--network` | per `[build].network`, §4 |
| `-w /build` | ⛔ a fixed working directory, or absolute paths leak into artefacts and differ per machine |
| `-v .../tools:ro` | ⭐ read-only: a script cannot rewrite its own verified tools |
| `--env-file` | ⚠ not `-e` per variable: an environment value containing a newline or a shell metacharacter is a command-line injection into the runtime's own argument handling |
| `sh -euc` | `-e` stops at the first failure, `-u` catches an unset variable |

⛔ **`-e` on the shell is not a substitute for phase 8.** A script can exit 0
having produced nothing. The verifier does not consult the exit code alone.

⚠ **`sh`, not `bash`.** The recipe's script runs under POSIX `sh` because the
pinned image is not guaranteed to have bash, and a recipe needing bash installs
it through `[build].deps` and invokes it explicitly. A recipe silently relying
on a bashism works on one image and fails on another.

### 2.7 Collect

For each `[artifact]` entry, after substitution and path validation
([`../format/build-manifest.md`](../format/build-manifest.md) §9):

1. resolve the source path **without following a symlink for the final
   component**;
2. verify the resolved real path is inside `src/`;
3. ⛔ fail if it is missing or is not a regular file, naming the key;
4. copy to `stage/<destination>`;
5. set the mode from content: `0755` if the first four bytes are `\x7fELF`,
   else `0644`.

⛔ **Step 2 is a security check, not a tidiness one.** A build script replacing
a declared output with a symlink to `/etc/shadow` is caught here, and only
here.

### 2.8 Verify

⭐ **The gate.** Every check runs against the staged bytes.

| # | check | fails when |
| --- | --- | --- |
| V1 | every declared artefact exists and is non-empty | a script exited 0 having done nothing |
| V2 | ELF `e_machine` matches the host's architecture | a cross-build silently produced the builder's architecture |
| V3 | ⭐ no ELF has a `PT_INTERP`, unless permitted by `[verify].allow-dynamic` | a build linked dynamically without saying so |
| V4 | no shipped file contains the workspace path or `PREFIX` outside an allowlist | a path leaked in and the artefact is not relocatable |
| V5 | `[verify].run`, if set, exits 0, under emulation when cross-built | it compiled and does not start |
| V6 | `[verify].expect-output`, if set, matches | it starts and is the wrong program |
| V7 | sizes within `[verify].min-size` and `max-size` | a debug tree shipped |
| V8 | no file mode grants setuid or setgid | ⛔ a setuid binary in a user-installed package is an escalation |
| V9 | no shipped file is a symlink pointing outside the artefact | |

⛔ **V2 and V3 use `tools/elfprobe.py`, which reads the bytes.** Not `file`,
whose output is prose that differs between the static and static-pie cases; not
`ldd`, which runs the binary's loader and cannot work on a foreign
architecture. [`../principles.md`](../principles.md) §4.

⚠ **V5 is opt-in** because not every binary has a harmless flag to invoke. A
tool whose only argument-free behaviour is to modify the filesystem must not be
run by a build gate.

### 2.9 Assemble

Normalise the archive per
[`../format/artifact-layout.md`](../format/artifact-layout.md) §6, write
`CHECKSUMS` and `metadata.json`, emit provenance, and finish the log.

---

## 3. The environment

⛔ **Enumerated. Nothing else is inherited from the host.**

| variable | value |
| --- | --- |
| `TARGET`, `HOST`, `PREFIX` | from the recipe and the request |
| `SOURCE_DATE_EPOCH` | the source commit's committer timestamp, or `[source].epoch` |
| `LC_ALL`, `LANG` | `C` |
| `TZ` | `UTC` |
| `TMPDIR` | `/build/.tmp` |
| `HOME` | `/build/.home` |
| `PATH` | `/tools:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` |
| `OPK_NAME`, `OPK_VERSION`, `OPK_REVISION`, `OPK_PROFILE` | identity |
| `SOURCE_DATE_EPOCH`-derived: `CARGO_HOME`, `GOPATH`, `GOCACHE`, `npm_config_cache` | fixed paths under `/build` |
| `[build.env]` entries | last, and ⛔ they cannot override any name above |

⛔ **No host variable is inherited. Not `USER`, not `HOSTNAME`, not the
runner's `GITHUB_*`.** Each of those has been observed in some ecosystem to end
up in a build artefact, and each differs per machine.

⚠ **`HOME` inside the workspace matters more than it looks.** Left at `/root`,
tool caches land outside `/build` and outside the fixed prefix, and any path
that leaks in is `/root/...` on one machine and something else on another.

### 3.1 Credentials

⛔ **No credential is passed into the build container. Ever.**

The container has no `GITHUB_TOKEN`, no registry credential, no signing key.
Fetching is done by the builder on the host, before the container starts.

⚠ **The studied system's era 1 did the opposite**, passing `GITHUB_TOKEN`,
`GITLAB_TOKEN` and `HF_TOKEN` into the recipe's shell, documented as available
in `x_exec.run`. Every package's script could read them. This design fetches
outside and passes nothing, which is why `[source]` and `[[tool]]` exist as
declarative fields rather than as things a script does.

⚠ **A private source is therefore not supported by this path**, and that is a
stated limit rather than an oversight.
[`../open-questions.md`](../open-questions.md) carries the question of whether
a narrowly scoped fetch credential should be added.

---

## 4. Network

Per `[build].network`.

| mode | implementation |
| --- | --- |
| `none` | ⭐ `--network none`. Nothing reaches out. |
| `restricted` | a network namespace with a filtering proxy; only the allowlist in [`build-environments.md`](build-environments.md) resolves |
| `full` | ⛔ unrestricted. Requires `network-reason`, and marks the artefact `hermetic: false`. |

⚠ **`restricted` is enforced by a proxy, not by the recipe.** A recipe cannot
grant itself more access, and a build that tries to reach elsewhere fails with
a connection error that names the blocked host, so the failure is diagnosable.

⚠ **`restricted` is not hermetic and the metadata never claims it is.** Only
`none` sets `hermetic: true`.

---

## 5. Failure

⛔ **A failed build produces a log and no artefact.**

| step | |
| --- | --- |
| 1 | the log is finalised, including the failing phase and the exit status |
| 2 | ⛔ the log is scrubbed per [`../security/secrets.md`](../security/secrets.md) |
| 3 | a failure record is published: `artifactType` `application/vnd.opk.buildfailure.v1+json`, log layer only, no payload |
| 4 | `stage/` is discarded |
| 5 | the builder exits non-zero with the phase in the message |

⭐ **Publishing the failure is what lets a user find out why a package is
missing for their architecture**, in one command instead of a support thread.

---

## 6. Running without a container runtime

⚠ **A degraded mode, and the degradation is named.**

`--no-container` runs the script directly on the host with the environment
still normalised and the workspace still fixed.

| lost | consequence |
| --- | --- |
| toolchain pinning | ⛔ the result is not reproducible against anyone else's build |
| filesystem isolation | ⛔ the script can read and write the whole user account |
| network control | `[build].network` is unenforceable |

⛔ **Artefacts built this way are marked `unsandboxed: true` and MUST NOT be
published to a public repository.** The mode exists for a developer iterating on
a recipe, and the marking is what stops a local convenience becoming a published
artefact.

⭐ **Rootless podman is the better answer where a daemon is unavailable**, and
the builder prefers it over `--no-container` automatically when it is present.
The probe host for this repository had no Docker daemon and podman 4.9.3
worked; `experiments/10-probe-host.sh` records the detection.

---

## 7. Concurrency and resources

| property | value |
| --- | --- |
| builds of different packages | ⭐ independent, run in parallel |
| builds of one package for different hosts | independent |
| ⛔ two builds of the same package, host and revision | serialised; the second sees the first's result |
| default timeout | 3600 s, `[build].timeout` up to 43200 |
| default memory | 4 GiB, `[build].memory` |
| ⚠ on timeout | the container is killed, the log is kept and published, and the failure says it was a timeout rather than a build error |

⚠ **A timeout reported as a generic failure sends a maintainer looking for a
compilation error that does not exist.** The distinction costs one line in the
failure record and saves an afternoon.
