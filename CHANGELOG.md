# CHANGELOG

⭐ **What changed here, newest first.** Each entry names the record carrying the
evidence and says whether anything deployed.

⛔ **Nothing in this repository deploys.** It is a specification; the "deployed"
line is kept because a future adopter's fork will need it, and a column that
appears later is a column nobody fills in.

---

## 2026-09-02

### The specification, first complete draft

**Deployed**: ⛔ no. Nothing here deploys.

**Record**: the commit history on `main`, and
[`docs/history/README.md`](docs/history/README.md).

⭐ **What shipped**: a documentation tree specifying a package manager and
binary distribution system on OCI registries, with GHCR as the reference host.
Entry point [`README.md`](README.md), map [`docs/README.md`](docs/README.md),
technical reference [`docs/architecture.md`](docs/architecture.md).

⭐ **What is proven rather than asserted**:

| | |
| --- | --- |
| ⭐ GHCR does not implement the referrers API | `experiments/40-registry-conformance.sh`, two controls held |
| ⭐ the fallback tag carries the same job | `experiments/41-referrers-fallback.sh`, 10 assertions |
| ⭐ the full lifecycle works on a conformant registry | `experiments/30-oci-pipeline.sh`, 33 assertions |
| ⭐ static linking, per toolchain | `experiments/20-static-matrix.sh`, 15 rows |

⛔ **What was withdrawn during writing**: five published claims, listed in
[`docs/history/README.md`](docs/history/README.md) §1. Four were counting or
version errors; one was a false statement about `file`'s output whose
underlying argument survived in a corrected form.

⚠ **What is not established**: cross-host reproducibility, anything writing to
real GHCR, the client, the update bot, the index generator, non-Linux targets,
and ten of seventeen language ecosystems.
[`experiments/README.md`](experiments/README.md) states each, and
[`docs/open-questions.md`](docs/open-questions.md) carries the command that
would close it.

### The reference sweep

**Deployed**: no.

**Record**: [`docs/history/references/README.md`](docs/history/references/README.md).

Three pinned commits of `pkgforge/soarpkgs` plus five related repositories,
with their trackers mined and kept under `references/`. ⭐ The central finding
is that build strategies with one uniform way to link statically survived at
3.1% to 7.1% disabled, while strategies needing bespoke per-package work
reached 92%.

---

## The rules this file follows

⛔ Four, and each is broken often enough to be worth stating:

1. ⛔ **Newest first.** A new entry goes at the top of its section.
2. ⛔ **Every heading carries a date.**
3. ⛔ **Every entry names its record**, the document or commit carrying the
   evidence. An entry with no record is a claim.
4. ⛔ **Every entry says whether it deployed.** "No" is a complete answer;
   silence is not.

⚠ **Do not tidy this file while shipping something else**, and ⛔ **do not
delete an entry.** A superseded one is amended in place with a dated note.
