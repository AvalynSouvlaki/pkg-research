# decision records

One record per decision. ⭐ **Each states the problem, the alternatives, the
tradeoff, the evidence, and what it costs to reverse.**

⛔ **A decision with no alternatives listed is a preference.** A record that
cannot say what it rejected has not made a decision; it has described a
default.

---

## The records

| # | decision | evidence class |
| --- | --- | --- |
| [0001](0001-inert-recipes.md) | ⭐ recipes are inert, with one contained escape hatch | ⭐ observed |
| [0002](0002-oci-substrate.md) | OCI registries as the substrate, GHCR as reference | observed, inferred |
| [0003](0003-static-musl-default.md) | ⭐ static linking by default, musl as the default libc | ⭐ measured |
| [0004](0004-registry-namespace.md) | the registry namespace shape | inferred |
| [0005](0005-referrers-fallback.md) | ⭐ evidence as referrers, with the fallback tag mandatory | ⭐ measured |
| [0006](0006-two-hashes.md) | two hashes, BLAKE3 and SHA-256, with distinct jobs | observed |
| [0007](0007-reproducibility-off-path.md) | reproducibility checked off the publish path | observed |
| [0008](0008-toml.md) | TOML for recipes | observed |
| [0009](0009-implementation-order.md) | the implementation order | recommended |
| [0010](0010-signing-scheme.md) | both minisign and Sigstore | recommended |
| [0011](0011-index-as-artifact.md) | the index as a signed artefact, not a service | recommended |
| [0012](0012-no-hooks.md) | ⭐ no package-supplied lifecycle hooks | recommended |

---

## The format

Each record has the same seven sections, so two can be compared:

| section | says |
| --- | --- |
| **Decision** | what was decided, in one sentence |
| **Problem** | what it solves |
| **Alternatives** | ⭐ what was rejected, and why |
| **Tradeoff** | ⭐ what this costs |
| **Evidence** | observed, inferred, measured or recommended, with the source |
| **Consequences** | ⭐ what an implementer must now do |
| **Reversal** | ⭐ what it would cost to change later |

⭐ **The reversal section is the one that is usually missing elsewhere**, and it
is the one a future maintainer needs most: it says whether a decision is a
door that is still open or a wall that has been built.

---

## Evidence classes

| class | means |
| --- | --- |
| ⭐ **measured** | a script in `experiments/` produced the number |
| **observed** | read in a source system at a pinned commit, cited |
| ⚠ **inferred** | a conclusion from the two above, labelled as a conclusion |
| ⚠ **recommended** | a judgement with no measurement behind it |

⚠ **Four of the twelve records are `recommended`.** That is not a failing, and
it is worth knowing which: 0009, 0010, 0011 and 0012 rest on judgement about
operational and human factors that this repository has no deployment to
measure.
