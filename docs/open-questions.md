# open questions

⛔ **What is genuinely unresolved, and what would resolve it.**

⭐ **Every entry carries the command or the experiment that would close it**, so
the next person spends minutes rather than re-deriving the question.

⚠ **This file is expected to shrink.** An entry that stays for a year is either
resolved and unrecorded, or it is a limit and belongs in
[`limits.md`](limits.md).

---

## 1. Measurable now, with credentials this repository lacks

⭐ **These need a GHCR namespace and a token. Each is minutes of work.**

### Q1: GHCR manifest size ceiling

⛔ Blocks: the annotation budget in
[`registry/oci-ghcr.md`](registry/oci-ghcr.md) §6.1 is set conservatively
because the real ceiling is unknown.

```sh
# Push manifests with growing annotation payloads until one is refused.
for kb in 4 8 16 32 64 128; do
  python3 -c "print('x'*$kb*1024)" > big.txt
  oras push ghcr.io/YOUR_ORG/opk-test:probe-$kb \
    --artifact-type application/vnd.opk.test.v1 \
    --annotation "dev.opk.probe=$(cat big.txt)" big.txt \
    && echo "$kb KiB ok" || { echo "$kb KiB REFUSED"; break; }
done
```

### Q2: GHCR rate limits

⛔ Blocks: the budget in [`ops/rate-limits.md`](ops/rate-limits.md) §3 is a
design target, not a measurement.

```sh
# Pull one manifest in a loop, reading the rate headers, until limited.
for i in $(seq 1 500); do
  curl -sS -D - -o /dev/null -H "Authorization: Bearer $TOKEN" \
    "https://ghcr.io/v2/YOUR_ORG/opk/test/test/manifests/1.0.0-1-x86_64-linux" \
    | grep -iE 'ratelimit|retry-after|^HTTP'
done
```

### Q3: does GHCR store a `subject` field

⚠ GHCR has no referrers API. It is not established whether it *stores* a
manifest carrying `subject`, or rejects it.

⭐ **This matters**: if it stores it, a future GHCR that implements the API
would light up existing artefacts. If it rejects it, the publisher must strip
the field and rely on the fallback tag alone.

```sh
oras attach --artifact-type application/vnd.opk.test.v1 \
  ghcr.io/YOUR_ORG/opk-test@sha256:... test.txt
# Then check the response for an OCI-Subject header, and whether the
# manifest comes back with `subject` intact.
```

### Q4: GHCR deletion behaviour

⚠ [`registry/retention.md`](registry/retention.md) §6 is written from GitHub's
documentation. The mapping from a digest to a Packages version ID, and whether
deletion is transactional, are untested.

---

## 2. Needs infrastructure this repository does not have

### Q5: cross-host reproducibility

⛔ **The most consequential open question.**
`experiments/30-oci-pipeline.sh` rebuilds byte-identically on the same host,
which demonstrates the timestamp, path, locale and archive controls and ⛔
nothing about toolchain or dependency drift.

⭐ **What would close it**: the workflow in
[`build/reproducibility.md`](build/reproducibility.md) §3, run on two runners a
week apart, over at least twenty packages across four ecosystems, with the
mismatch rate and the causes recorded.

### Q6: the fan-out cost of a security rebuild

⚠ [`security/supply-chain.md`](security/supply-chain.md) §6 specifies the
mechanism and cannot say what it costs. ⭐ The metric that matters is time from
advisory to every affected package rebuilt and republished.

### Q7: index size at scale

⚠ [`registry/index-and-search.md`](registry/index-and-search.md) §7 quotes one
data point from another project's schema. ⭐ What is needed is this schema's
size at 100, 1,000 and 10,000 packages, and the client's parse time.

### Q8: delta update value

⚠ [`client/delta-and-gc.md`](client/delta-and-gc.md) §2.3 specifies binary
deltas as possible and declines to implement them without a measurement.

```sh
# For adjacent versions of a real static binary:
zstd --patch-from=old/bin/rg -19 new/bin/rg -o delta.zst
ls -l old/bin/rg new/bin/rg delta.zst
```

⭐ **If the delta is 5% of the artefact, it is worth building. If it is 80%, it
is not.** Nobody here measured it.

### Q14: is a `pgb` build reproducible

⛔ **Blocks**: [`interop/glibc-research.md`](interop/glibc-research.md) §5, which
otherwise recommends a toolchain whose determinism nobody has tested.

`pgb`'s `--embed-locale` and `--wrap-dlopen` both **generate code at build
time**, the latter from a symbol table produced by `nm` over the build's own
objects. ⚠ Symbol order out of `nm` is not guaranteed stable across toolchain
versions, and generated code is where non-determinism hides.

⭐ **What would close it**: build one `pgb` artefact twice, on two hosts, and
compare bytes. ⚠ Neither project has attempted it.

### Q15: does a static glibc binary load host NSS modules on hosts nobody tested

⛔ **Blocks**: nothing, and it is listed because W8 and W9 in
[`history/README.md`](history/README.md) were exactly this shape.

`polaris0xff/glibc-research` measured 11 distributions. ⚠ **11 is not all of
them**, and the failure was host-dependent on every axis they varied, so the
honest reading of their table is a lower bound on the problem rather than its
extent.

⭐ **What would close it**: run their experiment 20 on this tree's probe host and
on distributions outside their set. ⚠ It needs root and `CAP_SYS_ADMIN`, because
their test bed is `unshare --mount` plus `chroot`.

---

## 3. Design questions with no measurement to settle them

### Q9: index freshness without an online key

⚠ [`registry/index-and-search.md`](registry/index-and-search.md) §4: a signed
index is still replayable within the staleness window. Closing it fully needs
an online signing key with a short expiry, which is a different operational
model.

⭐ **The question**: is a TUF-style timestamp role worth the operational cost
for a project of this size, or is the staleness warning sufficient?

### Q10: deprecation windows without telemetry

⚠ [`ops/long-term-maintenance.md`](ops/long-term-maintenance.md) §3.2 says to
measure whether old clients still fetch an old schema. ⛔ There is no telemetry
and none is proposed, so the window is a guess.

⭐ **The question**: is registry-side request logging by media type an
acceptable substitute, and does it count as telemetry a user should be told
about?

### Q11: a bundle format for software that cannot be static

⚠ [`build/static-linking.md`](build/static-linking.md) §7 concludes this system
fits command-line tools and not desktop or plugin-based applications, and
suggests a self-contained bundle format as the answer for the rest.

⭐ **The question**: should this system grow one, or should it stay narrow and
say so? ⚠ Era 1 tried to cover both and its AppImage side reached 97.9%
disabled.

### Q12: private sources

⛔ [`build/build-system.md`](build/build-system.md) §3.1 passes no credential
into the build container, which means a private source cannot be built.

⭐ **The question**: is a narrowly scoped, fetch-only credential, used by the
builder outside the container, worth adding? ⚠ It reopens a boundary that is
currently absolute.

### Q13: clearing macOS quarantine

⚠ [`compatibility.md`](compatibility.md) §3: the client clearing
`com.apple.quarantine` on files it verified is defensible and is exactly what
the attribute exists to prevent.

⭐ **The question**: does a client that verified a signature and a hash have
standing to clear it, or should the user do it explicitly?

---

## 4. Questions this repository answered and is not fully confident about

⚠ **Listed because a stated confidence level is worth more than silence.**

| question | answer given | confidence |
| --- | --- | --- |
| does GHCR implement referrers | ⛔ no | ⭐ **high**: two controls held |
| is musl the right default libc | ⭐ yes | ⭐ high: measured, and the reasoning is structural |
| is the fallback tag sufficient | ⭐ yes | ⭐ high: measured against a real registry |
| should evidence be referrers rather than layers | ⭐ yes | ⭐ high: the circularity argument is structural |
| is TOML right | ⭐ yes | ⚠ **medium**: observed from one project's experience |
| is one batched update pull request right | ⭐ yes | ⚠ **medium**: era 2 and era 3 differ and neither published a reason |
| is `mold` output reproducible | ⚠ unknown | ⛔ **low**: documented elsewhere, not verified here |
| are GraalVM native images reproducible | ⚠ treated as unverified | ⛔ **low** |
| is the eleven-case hook replacement list complete | ⚠ believed | ⛔ **low**: it is this repository's enumeration, not a survey |

⛔ **The bottom three are where a reader should be most sceptical.**

---

## 5. How to close one

```
1. write the experiment, numbered, in experiments/
2. ⭐ pin every input; print the conditions
3. run it; ⛔ commit the output, including a negative result
4. update the document that carried the question
5. move the entry from this file to history/README.md with the answer
6. ⭐ if the answer contradicts something published, record the withdrawal
```

⛔ **A question removed without a recorded answer is a question that gets asked
again.**
