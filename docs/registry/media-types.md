# media types

Every media type and `artifactType` this system defines, what carries it, and
what a client does with one it does not recognise.

⛔ **This table is normative and it is the only place these strings are
written.** A value appearing anywhere else is derived from here.

---

## 1. Naming

```
application/vnd.opk.<thing>.v<N>[+<structure>]
```

| part | rule |
| --- | --- |
| `vnd.opk` | the vendor tree. ⚠ Replace `opk` with your own token when adopting; it appears in published artefacts and cannot be changed later without breaking clients. |
| `<thing>` | lowercase, dot-separated |
| `v<N>` | ⛔ **required**. A media type with no version cannot be changed without breaking every client that parsed it. |
| `+<structure>` | the underlying encoding: `json`, `tar`, `tar+zstd` |

⭐ **The version segment is the cheapest forward-compatibility this design
buys.** A `payload.v2` layer can sit beside a `payload.v1` in one repository,
and a v1-only client skips what it does not know instead of misreading it.

---

## 2. artifactType values

Set on a manifest. Says what the whole artefact is.

| value | the manifest is | referrer of |
| --- | --- | --- |
| `application/vnd.opk.package.v1+json` | ⭐ a package for one host | nothing |
| `application/vnd.opk.package-index.v1+json` | an index over hosts | nothing |
| `application/vnd.opk.signature.v1` | a signature over its subject's digest | a package |
| `application/vnd.opk.sbom.v1+json` | an SBOM | a package |
| `application/vnd.opk.provenance.v1+json` | a SLSA provenance statement | a package |
| `application/vnd.opk.buildlog.v1` | a build log | a package or a failure record |
| `application/vnd.opk.debuginfo.v1` | separated debug symbols | a package |
| `application/vnd.opk.buildfailure.v1+json` | ⛔ a build that produced nothing | nothing |
| `application/vnd.opk.catalog.v1+json` | the searchable index | nothing |
| `application/vnd.opk.bundle.v1+json` | an offline bundle | nothing |

⛔ **`buildfailure` carries no payload layer, ever.** That is what stops a
client installing a failure. Asserted by `experiments/30-oci-pipeline.sh`,
which builds a program that cannot compile and checks the resulting manifest
for a payload layer.

⭐ **A failure record is not a referrer of the package**, because the package
does not exist. It is published at the coordinate the package would have had,
so a user asking "why is there no aarch64 build of foo 1.2.3" finds the answer
at the address they already know.

---

## 3. Layer media types

| value | contains |
| --- | --- |
| `application/vnd.opk.payload.v1+tar+zstd` | ⭐ the artefact tree, normalised per [`../format/artifact-layout.md`](../format/artifact-layout.md) §6 |
| `application/vnd.opk.payload.v1` | a single uncompressed file, for a one-binary package where compression is not worth a decompress step |
| `application/vnd.opk.metadata.v1+json` | the document in [`../format/metadata-schema.md`](../format/metadata-schema.md) |
| `application/vnd.opk.checksums.v1` | the `CHECKSUMS` file |
| `application/vnd.opk.catalog-db.v1` | the catalogue as SQLite, per [`index-and-search.md`](index-and-search.md) §2 |
| `application/vnd.opk.signature.minisign.v1` | a minisign `.minisig` |
| `application/vnd.opk.signature.sigstore.v1+json` | a Sigstore bundle |
| `application/spdx+json` | ⭐ an SBOM. A standard type, not ours. |
| `application/vnd.cyclonedx+json` | an SBOM in the other standard format |
| `application/vnd.in-toto+json` | ⭐ an attestation. A standard type, not ours. |
| `text/plain` | ⚠ a build log. See §3.1. |
| `application/vnd.opk.buildlog.v1+zstd` | a compressed build log |

⛔ **Standard types are used where one exists.** An SBOM layer is
`application/spdx+json`, not `application/vnd.opk.sbom-content.v1+json`. The
`artifactType` says it is ours; the layer says what it actually is, so an
off-the-shelf SBOM tool can consume the blob.

### 3.1 ⚠ `text/plain` for logs, with a caveat

A build log is plain text and the honest type is `text/plain`. ⛔ **A client
MUST NOT render a build log as anything but text**, and **MUST** treat it as
untrusted: a build log contains whatever the compiler and the upstream source
printed, including terminal escape sequences and text that looks like the
client's own output. [`../ci/build-logs.md`](../ci/build-logs.md) §rendering.

**Logs above 1 MiB are compressed** and carry
`application/vnd.opk.buildlog.v1+zstd`.

---

## 4. Client behaviour on an unrecognised type

⛔ **The rule differs by position, and getting it backwards is a security
defect.**

| position | unrecognised type | why |
| --- | --- | --- |
| manifest `artifactType` | ⛔ **refuse.** Do not install. | an artefact whose kind you do not know may not be a package |
| a **required** layer (payload, metadata) | ⛔ **refuse.** | you cannot install what you cannot read |
| an **optional** layer (icon, extra) | ⭐ **ignore and continue.** | forward compatibility: a v2 publisher adding a layer must not break v1 clients |
| a referrer's `artifactType` | ⭐ **ignore that referrer.** | a new evidence kind is not a reason to refuse a package |
| a layer inside a referrer you do recognise | ⛔ **treat that referrer as unusable.** | a signature you cannot parse is not a signature you can trust |

⚠ **The fourth row has an exception that must not be lost.** Ignoring an
unknown *referrer* is safe. Ignoring an unknown *signature scheme* when the
trust policy requires a signature is not: the client has then found no usable
signature and **MUST** apply the policy's no-signature behaviour rather than
treating the package as verified.
[`../security/trust-and-verification.md`](../security/trust-and-verification.md).

---

## 5. Annotation keys

| key | on | value |
| --- | --- | --- |
| `org.opencontainers.image.created` | manifests | ⛔ the source epoch, ISO 8601 UTC. Never the wall clock. |
| `org.opencontainers.image.title` | layer descriptors | ⚠ the file's basename. See §5.1. |
| `org.opencontainers.image.version` | manifests | `<version>-<revision>` |
| `org.opencontainers.image.licenses` | manifests | an SPDX expression |
| `org.opencontainers.image.source` | manifests | the upstream URL |
| `org.opencontainers.image.revision` | manifests | ⚠ the **source commit**, per the OCI convention. Not this system's package revision. |
| `dev.opk.schema` | manifests | the metadata schema version |
| `dev.opk.name`, `.version`, `.revision`, `.host`, `.channel` | manifests | identity, for filtering without a fetch |
| `dev.opk.provides` | manifests | comma-separated, truncated per [`oci-ghcr.md`](oci-ghcr.md) §6.1 |
| `dev.opk.portable` | manifests | `"true"` or `"false"` |
| `dev.opk.build.status` | failure records | `"failed"` |

⚠ **`org.opencontainers.image.revision` colliding with this system's
`revision` is a genuine trap.** OCI's key means the source control revision;
ours means the rebuild counter. Both appear on the same manifest with different
meanings. The OCI key keeps its OCI meaning because generic tooling reads it,
and ours is namespaced.

### 5.1 ⚠ `image.title` is the path the puller writes

ORAS stores the path it was given and recreates it on pull. Pushing
`stage/build.log` makes a client write `stage/build.log`, not `build.log`.

**MUST**: the publisher pushes from the file's own directory so the title is a
basename.

⭐ **This was found by running the pipeline, not by reading the spec.**
`experiments/30-oci-pipeline.sh` failed to retrieve a build log it had just
attached, because the title carried the staging subdirectory. A client looking
for `build.log` found nothing and reported it as a missing log.

---

## 6. Registering these types

⚠ **`vnd.opk.*` is not registered with IANA and this specification does not
claim it is.** The `vnd.` tree permits vendor-specific types without
registration, and registries treat media types as opaque strings. Registration
would be appropriate if the format stabilises and third-party tools begin to
consume it; it is not a prerequisite for anything here.

⛔ **An adopter changing `opk` to their own token must change it everywhere at
once**, before any artefact is published. Media types appear in every manifest
and in every signature's covered bytes, so changing one later means republishing
and re-signing everything.
