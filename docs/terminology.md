# terminology

Every term this specification uses, defined once. A reader with no background
in packaging or registries can read this file and then read any other.

⚠ Several of these words mean something narrower here than in general use.
Where that is so, the entry says what the wider meaning is and why this one is
narrower.

---

## Packaging

**Package.** A named, versioned unit of installable software. In this system a
package is defined by a **recipe** and realised as one or more **artefacts**,
one per **host triple**. Full identity rules:
[`format/package-identity.md`](format/package-identity.md).

**Recipe.** The file that declares a package: `opk.toml`. It is **inert**:
parsing, validating or resolving it never executes anything it contains.
Specified in [`format/build-manifest.md`](format/build-manifest.md).

**Artefact.** The bytes a build produced, plus the files shipped alongside
them. What a client downloads and installs.
[`format/artifact-layout.md`](format/artifact-layout.md).

**Inert.** A file that is data and only data. The contrast is a package format
whose definition is a program, where reading the definition to find out the
version means running the author's code. Both historical systems studied here
sat on opposite sides of this line, which is why the word gets an entry.

**Provides.** The programs a package installs. A package named `ripgrep` may
provide the binary `rg`. Aliases and symlinks are part of this;
[`format/package-identity.md`](format/package-identity.md) has the syntax.

**Revision.** A counter, separate from the version, incremented when the
package is rebuilt without the upstream version changing. `1.2.3-2` is the
second build of upstream `1.2.3`. It exists because a packaging fix must be
distributable without lying about which upstream release it contains.

**Epoch.** An integer that, when present, dominates version comparison. It
exists for the one case ordinary version ordering cannot express: upstream
renumbering downwards, for example from `2024.10` to `1.0`. Almost never used.

**Channel.** A named line of releases a user can follow: `stable`, `beta`,
`nightly`. A channel is a mutable pointer at an immutable artefact.

**Variant.** A build of the same upstream software with different options, for
example `ffmpeg` with and without non-free codecs. Distinct from a revision,
which is the same options built again.
[`format/variants-and-features.md`](format/variants-and-features.md).

**Profile.** A named set of build settings applied across packages, for
example `release`, `debug`, `size`. Not a per-package concept.

---

## Linking, ABI and portability

**Static linking.** Copying the machine code of every library a program uses
into the program's own file, so at run time it needs nothing but the kernel.
The measured consequences are in
[`build/static-linking.md`](build/static-linking.md).

**Dynamic linking.** Leaving library code out of the program, to be found and
loaded at start-up by the **dynamic loader**. Smaller files and shared
security updates, at the cost of the program only running where those exact
libraries exist.

**PT_INTERP.** A field in an ELF file naming the dynamic loader the program
requires, by absolute path, for example `/lib64/ld-linux-x86-64.so.2`.

⭐ **PT_INTERP is the property this system actually cares about.** A binary
with none runs on a host that provides no matching loader, which is the whole
portability claim. `tools/elfprobe.py` reports it as a field, and every build
is gated on it.

⚠ **"Static" and "has no PT_INTERP" are not synonyms in casual use.** A
**static-pie** binary is position-independent and has a `PT_DYNAMIC` segment,
which makes some tools call it dynamic, yet it has no `PT_INTERP` and is
portable. Measured on the probe host: `file` 5.45 calls it "static-pie
linked", and a check grepping for the string "statically linked" rejects it.
This is why the gate reads the field.

**DT_NEEDED.** An entry in a dynamic binary naming a shared library it
requires, for example `libc.so.6`.

**libc.** The C standard library, the layer between a program and the kernel.
Which one a binary is built against decides where it runs.

| libc | in this system |
| --- | --- |
| **glibc** | the GNU C Library. What most Linux distributions use. Statically linking it works but is large, and its name-service and locale machinery still expects to `dlopen` shared modules at run time. |
| **musl** | small, permissively licensed, and designed to link statically. ⭐ The default target here. |
| **uClibc-ng** | for space-constrained embedded targets. Supported as a target, not a default. |
| **bionic** | Android's libc. Relevant only to Android targets. |

**ABI.** Application Binary Interface: the machine-level contract between
compiled components. Two libraries with the same API can be ABI-incompatible,
in which case a binary built against one crashes against the other.

**Symbol versioning.** A glibc mechanism that records the minimum glibc
version each symbol requires. It is the direct cause of the `GLIBC_2.38 not
found` failure: a binary built on a newer machine records requirements an
older machine cannot satisfy. Static musl linking sidesteps the mechanism
entirely.

**Host triple.** The identifier for what a binary runs on, in this system
`<arch>-<os>`, for example `x86_64-linux`. ⚠ Not the same as a **target
triple**.

**Target triple.** The compiler's identifier for what it is emitting, in the
form `<arch>-<vendor>-<os>-<abi>`, for example
`x86_64-unknown-linux-musl`. One host triple maps to different target triples
per toolchain, and the recipe states the mapping.

**Microarchitecture level.** A named CPU feature baseline within one
architecture: `x86-64-v1` through `x86-64-v4`. A binary built for a level does
not run on a CPU below it.

**Cross-compilation.** Building on one architecture for another.
[`build/cross-compilation.md`](build/cross-compilation.md).

**Relocatable.** An artefact that works wherever it is unpacked, with no path
compiled into it. Required here.
[`client/installation-layout.md`](client/installation-layout.md).

---

## Registries and OCI

**OCI.** The Open Container Initiative, which publishes the specifications
this system's storage layer uses. Three matter:

| specification | what it defines |
| --- | --- |
| **image-spec** | manifests, indexes, descriptors, media types |
| **distribution-spec** | the HTTP API a registry serves, including referrers |
| **artifact guidance** | how to store things that are not container images |

⚠ **OCI is not Docker.** Docker is one client. The registry API is an open
specification with many implementations, which is what makes it usable as a
general content-addressed store.

**Registry.** A server storing content-addressed blobs and the manifests that
describe them, speaking the distribution-spec HTTP API. Examples: GHCR, Docker
Hub, zot, Harbor, ECR.

**GHCR.** GitHub Container Registry, at `ghcr.io`. The reference host here.
Its measured limits are in [`registry/oci-ghcr.md`](registry/oci-ghcr.md).

**Repository.** A named collection inside a registry, for example
`ghcr.io/example/opk/ripgrep`. Not a git repository.

**Blob.** An opaque byte string in a registry, addressed only by its digest.

**Digest.** The hash of some bytes, written `sha256:` followed by 64 hex
characters. ⭐ **A digest is the only immutable way to name anything in a
registry.**

**Tag.** A mutable human-readable label pointing at a manifest, for example
`1.2.3-1-x86_64-linux`. ⛔ A tag can be moved to different bytes at any time,
so a tag is a lookup key and never an integrity claim.

**Manifest.** A JSON document listing the blobs that make up one artefact,
each as a **descriptor**. Itself stored as a blob, so it has its own digest,
and that digest is what a signature covers.

**Descriptor.** A reference to a blob: media type, digest, size, and optional
annotations. The unit of content addressing.

**Media type.** A string declaring what a blob contains, for example
`application/vnd.opk.payload.v1`. Every one this system defines is in
[`registry/media-types.md`](registry/media-types.md).

**artifactType.** A field on a manifest declaring what the whole artefact is,
as opposed to what one layer contains. It is how a client tells a package from
a signature without downloading either.

⚠ **The historical system published manifests with no `artifactType` and with
every layer claiming `application/vnd.oci.image.layer.v1.tar` while containing
raw, untarred files.** Observed on `ghcr.io/pkgforge/bincache` on 2026-09-02
by `experiments/40-registry-conformance.sh`. This specification does not do
that, and [`registry/media-types.md`](registry/media-types.md) says why it
matters.

**Index.** A manifest listing other manifests, used here to group the
per-architecture artefacts of one version under one tag. Sometimes called a
manifest list.

**Referrer.** A manifest that names another manifest as its `subject`, which
is how a signature, SBOM, provenance statement or build log is attached to a
package *after* the package is published, without changing the package's own
digest.

**Referrers API.** The registry endpoint `/v2/<repo>/referrers/<digest>`,
which lists what refers to a manifest.

⛔ **GHCR does not implement it.** Verified on 2026-09-02 with two controls
holding, by `experiments/40-registry-conformance.sh`. The consequence, and the
fallback that carries the same job, are in
[`registry/oci-ghcr.md`](registry/oci-ghcr.md).

**Fallback tag.** The distribution-spec's alternative to the referrers API:
the referrers of `sha256:HEX` are published as an image index at the ordinary
tag `sha256-HEX`. Proven working by
`experiments/41-referrers-fallback.sh`.

**ORAS.** A command-line tool and library for pushing and pulling arbitrary
artefacts to an OCI registry. Used throughout the examples.

---

## Integrity, trust and provenance

**Content addressing.** Naming data by the hash of its bytes, so the name
cannot refer to anything else. The property everything else here rests on.

**Checksum.** A hash used to detect corruption or substitution. This system
records two per artefact, for the reason in
[`security/trust-and-verification.md`](security/trust-and-verification.md):

| hash | role |
| --- | --- |
| **BLAKE3** | what the client verifies. Fast, tree-structured, parallel. |
| **SHA-256** | what a registry or forge independently reports, so the two can be cross-checked |

**Signature.** A cryptographic assertion, verifiable with a public key, that
some bytes were approved by the key's holder. Here a signature covers a
**digest**, never a tag.

**minisign.** A small signature tool with short keys and no infrastructure.
The baseline signing scheme here.

**Sigstore / cosign.** A signing ecosystem using short-lived certificates
bound to an OIDC identity, with a public transparency log. Supported as an
additional scheme.
[`security/signing-and-attestations.md`](security/signing-and-attestations.md).

**Attestation.** A signed statement *about* an artefact, as opposed to a
signature *of* it. "This was built by X from source Y" is an attestation.

**in-toto.** The statement format attestations use here: a `subject` naming
what is described, a `predicateType` saying what kind of claim it is, and a
`predicate` carrying it.

**SLSA.** A framework of levels describing how resistant a build pipeline is
to tampering. Which level this design targets, and what is missing for the
next, is in [`security/sbom-and-provenance.md`](security/sbom-and-provenance.md).

**Provenance.** The record of how an artefact came to exist: source, builder,
parameters, environment. Here it is a SLSA provenance attestation attached as
a referrer.

**SBOM.** Software Bill of Materials: the inventory of components inside an
artefact. Formats: SPDX and CycloneDX.

⚠ **An SBOM of a stripped static binary is thin, and saying so is part of
using it honestly.** Measured limits are in
[`security/sbom-and-provenance.md`](security/sbom-and-provenance.md).

**Reproducible build.** A build that produces byte-identical output from the
same inputs, on a different machine at a different time. ⭐ It is what lets a
third party check the builder rather than trust it.

**Hermetic build.** A build whose inputs are fully declared, with no access to
anything undeclared, in particular no unrestricted network. Hermeticity is a
means; reproducibility is the observable end.
[`build/reproducibility.md`](build/reproducibility.md).

**`SOURCE_DATE_EPOCH`.** The cross-ecosystem environment variable carrying a
fixed timestamp for build tools to embed instead of the current time. Taken
here from the source commit, never from the clock.

**TOFU.** Trust On First Use: accepting an unverified identity the first time
and pinning it thereafter. Where this system uses it, and where it refuses to,
is in [`security/trust-and-verification.md`](security/trust-and-verification.md).

---

## Building and CI

**Build manifest.** Synonym for recipe. This tree prefers "recipe".

**Build input.** Anything that can change a build's output: source, toolchain
image, tools, patches, environment. ⛔ Every build input is pinned by digest
or by hash. An unpinned input is a build that means nothing on the second run.

**Build dependency.** Something needed to build but not to run.

**Runtime dependency.** Something needed to run. In a statically linked
system the set is usually empty, and
[`format/dependencies.md`](format/dependencies.md) says what remains.

**Optional dependency.** Something that enables a feature if present.

**Escape hatch.** A deliberate place where a declarative system allows
arbitrary code, because no finite set of fields covers every real project.
Here it is `[build.script].run`, and it is contained rather than removed.
[`principles.md`](principles.md).

**Runner.** The machine executing CI. GitHub provides x86-64 and aarch64
Linux runners; other architectures need cross-compilation or emulation.

**Index generation.** Producing the searchable catalogue a client resolves
against, from the recipes and published artefacts.

---

## The systems studied

⚠ Historical context. These names appear in citations throughout and are
defined here so a citation is readable without opening the history.

**pkgforge.** The organisation whose systems this specification was built by
studying. Full sweep:
[`history/references/README.md`](history/references/README.md).

**soarpkgs.** Its package repository. Read at three pinned commits, called
here **era 1** (`6f1cbb9`, the build-and-store system), **era 2**
(`dc3bed5`, peak CI automation) and **era 3** (`50379ab`, the inert declarative
system).

**SBUILD.** Era 1 and era 2's recipe format: YAML carrying a `x_exec.run`
shell script.

**soar.** The client that installs from those repositories.

**bincache / pkgcache.** The GHCR namespaces the built artefacts were pushed
to.

**sbuild / sbuilder.** The tool that executed SBUILD recipes.

**pkgforge/builds.** The small build repository era 3 kept as its escape
hatch. ⭐ Its reproducibility discipline is the single most directly adopted
piece of prior art in this design.
