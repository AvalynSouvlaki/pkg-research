# developer workflow

Working on the system itself: the client, the builder, the CI, the tooling.

Adding a *package* is [`package-author.md`](package-author.md).

---

## 1. What you need

| tool | for | required |
| --- | --- | --- |
| a container runtime | ⭐ builds | ⭐ rootless podman preferred |
| ⭐ python3, jq, curl, git | ⭐ tooling and experiments | yes |
| ⭐ a local OCI registry | ⭐ testing publish and discovery | ⭐ zot, fetched by `00-fetch-tools.sh` |
| oras | registry operations | yes |
| minisign, cosign, syft | signing and SBOMs | for those paths |

```sh
bash experiments/00-fetch-tools.sh
export PATH="$PWD/.tmp/bin:$PATH"
bash experiments/10-probe-host.sh
```

⭐ **Run the probe first, always.** It records what this machine can actually
prove, and every measurement in this tree carries its conditions.

⛔ **Probe the daemon, not the binary.** `docker --version` answers happily with
no daemon and then every real command fails. `10-probe-host.sh` does this
correctly and reported `docker_daemon UNAVAILABLE` beside a working podman on
the host this repository was written on.

---

## 2. The layers, and where to start

| layer | start at | first thing to build |
| --- | --- | --- |
| recipe format | [`../format/build-manifest.md`](../format/build-manifest.md) | ⭐ the validator |
| builder | [`../build/build-system.md`](../build/build-system.md) | the nine phases |
| registry | [`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) | push with correct media types |
| index | [`../registry/index-and-search.md`](../registry/index-and-search.md) | the generator |
| client | [`../client/client-behaviour.md`](../client/client-behaviour.md) | resolve, verify, install |

⭐ **The order is a dependency order**, and
[`../decisions/0009-implementation-order.md`](../decisions/0009-implementation-order.md)
says why signing is item 6 and not item 1.

---

## 3. The local loop

⭐ **`experiments/30-oci-pipeline.sh` is the whole system in one script.** Read
it before writing anything: it starts a registry, builds, publishes, attaches
evidence, signs, discovers, verifies, installs, rebuilds and publishes a
failure, in 400 lines.

```sh
bash experiments/30-oci-pipeline.sh
```

**Running a registry by hand:**

```sh
cat > /tmp/zot.json <<'EOF'
{ "distSpecVersion": "1.1.0",
  "storage": { "rootDirectory": "/tmp/zot-data" },
  "http": { "address": "127.0.0.1", "port": "15000" },
  "log": { "level": "info" } }
EOF
.tmp/bin/zot serve /tmp/zot.json &
curl -sS http://127.0.0.1:15000/v2/     # ⭐ 200 means ready
```

⛔ **Use `--plain-http` with oras against it**, and keep that flag in one
variable rather than at every call site, so a real deployment flips it once.

⚠ **zot implements the referrers API and GHCR does not**, so a feature that
works locally can fail against GHCR. ⭐ Test the fallback path explicitly:
`experiments/41-referrers-fallback.sh` runs discovery with the API disabled for
exactly this reason.

---

## 4. Testing

Full strategy: [`../testing.md`](../testing.md).

```sh
bash tools/check-links.sh          # ⭐ the docs' own mechanical checks
bash experiments/20-static-matrix.sh
bash experiments/30-oci-pipeline.sh
bash experiments/41-referrers-fallback.sh
```

⛔ **Read the exit code from the process that produced it, unpiped.** A check
piped into anything reports the pipeline's status, so a guard that failed reads
as green.

⭐ **Every guard ships with its negative case.** Before believing a new check
works, plant the defect it exists to catch and watch it fail.
[`../principles.md`](../principles.md) §5 has the case where this repository's
own pipeline passed a check while testing nothing.

---

## 5. Adding an experiment

```
experiments/
  NN-what-it-answers.sh
  out/NN-what-it-answers.txt
```

⛔ **What one owes:**

| | |
| --- | --- |
| ⭐ a header saying what QUESTION it answers | ⛔ not what it does |
| every input pinned | a version, a digest, a commit |
| ⭐ the conditions printed on the way out | host, tool versions, date |
| a meaningful exit code | ⭐ 0 ran, 1 ran and failed, 2 could not run |
| no dependence on the caller's directory | resolve paths from its own location |
| ⛔ it does not clean up its own output | ⭐ the evidence is the point |

⛔ **Numbered in the order written, and a number is never reused.** A citation
of `30-` in a document has to keep meaning what it meant, so a replaced
experiment gets the next number and the old one stays.

⛔ **A negative result is committed.** "We tried this and it did not work" is
one of the most valuable things this directory produces, and it is what sessions
quietly drop because it does not look like progress. The `gdc` link failure in
`20-static-matrix.sh` is one.

---

## 6. Changing the documentation

⛔ **The rules are [`../conventions.md`](../conventions.md).** The four that
matter:

- ⛔ **one fact, one home.** Link, do not repeat.
- ⛔ **never a fabricated number.** A dash where the value is unknown, and a
  measurement carries its conditions.
- ⛔ **observed, inferred and recommended are labelled**, every time.
- ⚠ **a page nothing links to is a finding.**

```sh
bash tools/check-links.sh
```

⛔ **When a rule changes, rewrite the rule.** Do not stack a dated box under the
old text saying the text above is retired. The superseded wording moves to
[`../history/README.md`](../history/README.md), and the live page says one
thing.

---

## 7. Debugging the client

```sh
OPK_LOG=trace opk install ripgrep -vv
opk install ripgrep --dry-run --json | jq
opk doctor
```

| symptom | look at |
| --- | --- |
| ⛔ resolution picks the wrong version | ⭐ `--dry-run --json`: the candidate list and the priorities |
| ⛔ verification fails against a local registry | ⚠ `--plain-http`, and whether referrers came back |
| a referrer is not found | ⭐ try the fallback tag by hand; §3 |
| install leaves a partial tree | ⛔ that is a bug: staging should be atomic |
| state disagrees with disk | `opk fsck` |

---

## 8. Before you push

- [ ] `bash tools/check-links.sh` exits 0
- [ ] every experiment you touched still exits 0
- [ ] ⭐ any new guard has been seen to fail on a planted defect
- [ ] ⛔ documentation changed in the same commit as the behaviour it describes
- [ ] ⛔ no number without its conditions
- [ ] ⛔ no secret, not expired, not redacted-looking, not in an example

⛔ **Documentation drifting from code is a forbidden pattern here.** The moment
code changes a documented behaviour, the document changes with it, in the same
commit.
