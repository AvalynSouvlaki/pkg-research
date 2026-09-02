# experiments

⭐ **Runnable proofs.** Each answers one question, prints the conditions it ran
under, and ⛔ **exits non-zero when it fails**.

⛔ **These are not illustrations.** A number in the documentation that is marked
`measured` came from one of these scripts, and re-running it is how a reader
checks the claim.

---

## Running them

```sh
bash experiments/00-fetch-tools.sh     # ⭐ pinned tools into .tmp/bin
bash experiments/10-probe-host.sh      # what this machine can prove
bash experiments/20-static-matrix.sh   # static linking, per toolchain
bash experiments/30-oci-pipeline.sh    # ⭐ the whole lifecycle, locally
bash experiments/40-registry-conformance.sh
bash experiments/41-referrers-fallback.sh
bash experiments/50-mirror.sh        # mirror fidelity, and a tamper check
```

⭐ **Run `30-oci-pipeline.sh` if you run one.** It is the whole system in one
script and it needs no credentials, no registry account and no root.

⛔ **Read the exit code from the process that produced it, unpiped.** A check
piped into anything reports the pipeline's status.

---

## What each answers

| # | question | needs | ⭐ what it establishes |
| --- | --- | --- | --- |
| [`00-fetch-tools.sh`](00-fetch-tools.sh) | ⚠ none: a helper | network | pinned oras, zot, cosign, syft, crane, minisign, zig |
| [`10-probe-host.sh`](10-probe-host.sh) | ⭐ what can this machine prove, and which gates can it pass | none | ⭐ the conditions every later number is measured under |
| [`20-static-matrix.sh`](20-static-matrix.sh) | ⭐ does each toolchain's documented static recipe actually produce a binary with no `PT_INTERP` | toolchains | ⭐ the measured table in [`../docs/build/static-linking.md`](../docs/build/static-linking.md) §2 |
| [`30-oci-pipeline.sh`](30-oci-pipeline.sh) | ⭐ does the specified registry layout work end to end on a conformant registry | zot, oras | ⭐ **30 assertions**: build, publish, attach, sign, discover, verify, install, reproduce, fail correctly |
| [`40-registry-conformance.sh`](40-registry-conformance.sh) | ⭐ what does a real registry implement, and does it answer referrers | network | ⛔ **GHCR does not implement the referrers API**, with two controls |
| [`41-referrers-fallback.sh`](41-referrers-fallback.sh) | ⭐ does the fallback tag carry the same job | zot, oras | ⭐ **10 assertions**: discovery with the API disabled finds the same referrers |
| [`50-mirror.sh`](50-mirror.sh) | ⭐ does a mirrored package still verify, and is a mirror that alters something caught | zot, oras | ⭐ **15 assertions**: the original signature verifies against the mirrored artefact; a tampered mirror is refused |

---

## ⛔ What they do NOT establish

| | |
| --- | --- |
| ⛔ **cross-host reproducibility** | ⭐ one machine. `30-` rebuilds on the same host, which demonstrates timestamps, paths, locale and archive normalisation and ⛔ nothing about toolchain or dependency drift. |
| ⛔ **anything that writes to real GHCR** | no namespace, no credentials. GHCR was probed read-only and anonymously. |
| ⛔ **the client, the update bot, the index generator** | ⚠ not implemented; there is nothing to test |
| ⛔ **non-Linux targets** | Linux x86-64 host only |
| ⚠ **ten of the seventeen language ecosystems** | ⭐ absent toolchains; each file says which |
| ⛔ **behaviour at scale** | no deployment |

⭐ **Each has the command that would close it** in
[`../docs/open-questions.md`](../docs/open-questions.md).

---

## What a script here owes

⛔ **Every one of these, or it does not belong in this directory.**

| | |
| --- | --- |
| ⭐ a header saying what **question** it answers | ⛔ not what it does. The question is what tells a later reader whether it still needs asking. |
| every input pinned | a version, a digest, a commit |
| ⭐ the conditions printed on the way out | host, tool versions, date |
| a meaningful exit code | ⭐ 0 it ran, 1 it ran and the thing failed, 2 it could not run |
| no dependence on the caller's directory | paths resolve from the script's own location |
| ⛔ it does not clean up its own output | ⭐ the evidence is the point |

⛔ **Numbered in the order written, and a number is never reused.** A citation
of `30-` in a document has to keep meaning what it meant, so a replaced
experiment gets the next number and the old one stays, labelled superseded.

⛔ **A negative result is committed.** "We tried this and it did not work" is
one of the most valuable things this directory produces. ⭐ The `gdc` link
failure in `20-static-matrix.sh` is one: it is an expected-failure row that does
not fail the experiment, with the undefined symbol that explains it.

---

## Output

```
experiments/out/     ⭐ committed. The evidence.
experiments/.work/   ⚠ gitignored. Working trees, registries, build output.
```

⚠ **`out/` is committed on purpose.** A number quoted in a document with no
output file behind it is a claim.

---

## The instrument

[`../tools/elfprobe.py`](../tools/elfprobe.py) is the oracle these experiments
assert with.

⭐ **It reads the ELF bytes.** It never asks the toolchain that produced the
file and never runs it, so it works on a cross-built artefact and on a hostile
one.

```sh
python3 tools/elfprobe.py --expect-static path/to/binary   # exit 1 if PT_INTERP
python3 tools/elfprobe.py --json path/to/binary
```

⭐ **It passes its own guard-mutation test**: exit 1 on a planted dynamic
binary, exit 0 on genuinely static ones.

[`../tools/check-links.sh`](../tools/check-links.sh) and
[`../tools/count-requirements.sh`](../tools/count-requirements.sh) are the
documentation's own checks, and both have been shown to fail on a planted
defect.
