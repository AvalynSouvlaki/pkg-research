# OCI and GHCR

⭐ **The storage layer.** Repository layout, manifest shapes, how evidence is
attached, and the GHCR limits that shaped all three.

Media type values are [`media-types.md`](media-types.md). The searchable
catalogue is [`index-and-search.md`](index-and-search.md). This document owns
the **registry-side structure** and the **measured registry behaviour**.

---

## 1. Why a container registry at all

A registry is a content-addressed blob store with authentication, an HTTP API,
CDN-backed delivery, and clients on every platform. Using one means the project
operates no storage.

| what a registry gives | what it does not |
| --- | --- |
| content addressing by digest | ⛔ search of any kind |
| deduplication across repositories | ⛔ a listing of what exists, other than tags |
| resumable, ranged downloads | ⛔ per-file access inside an artefact |
| authentication and per-repository access control | ⛔ mutable-tag protection |
| free hosting for public content on GHCR | ⛔ a guarantee that the referrers API exists |

⭐ **The last row is the finding that shaped the whole design.** See §5.

Alternatives considered, with the reason each was rejected, are in
[`../decisions/0002-oci-substrate.md`](../decisions/0002-oci-substrate.md).

---

## 2. Repository layout

```
ghcr.io/<org>/opk/<family>/<name>
```

| segment | example | why |
| --- | --- | --- |
| `<org>` | `example` | the GitHub org or user that owns the packages |
| `opk` | literal | ⛔ a fixed namespace segment. Without it a package named `index` collides with the index repository. |
| `<family>` | `ripgrep` | groups variants of one upstream project |
| `<name>` | `ripgrep` | the package |

**Tags in that repository:**

| tag | points at | mutable |
| --- | --- | --- |
| `<version>-<revision>-<host>` | one platform's manifest | ⛔ never moved |
| `<version>-<revision>` | an index over every host | ⛔ never moved |
| `stable`, `beta`, `nightly` | the current release on that channel | ⭐ moves, by design |
| `sha256-<hex>` | the referrers fallback index for that digest | appended to |

**Separate repositories:**

```
ghcr.io/<org>/opk-index          the signed catalogue
ghcr.io/<org>/opk-bundle         offline bundles, if published
```

⚠ **GHCR maps the first path segment after the org to a GitHub Packages
entry**, so `ghcr.io/example/opk/ripgrep/ripgrep` appears in the UI under the
package `opk/ripgrep/ripgrep`. The nesting is legal and it does affect how
packages are listed and how visibility is administered;
[`../ops/operations.md`](../ops/operations.md) §ghcr-admin covers the
consequences.

---

## 3. The package manifest

⛔ **An OCI image manifest with `artifactType` set and an empty config.**

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "artifactType": "application/vnd.opk.package.v1+json",
  "config": {
    "mediaType": "application/vnd.oci.empty.v1+json",
    "digest": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "size": 2
  },
  "layers": [
    {
      "mediaType": "application/vnd.opk.payload.v1+tar+zstd",
      "digest": "sha256:afb42bf28b19048dac5b970cb2474ead0f7ea02d1307a86104d18644f13a824f",
      "size": 5242880,
      "annotations": { "org.opencontainers.image.title": "payload.tar.zst" }
    },
    {
      "mediaType": "application/vnd.opk.metadata.v1+json",
      "digest": "sha256:1a2b3c...",
      "size": 4096,
      "annotations": { "org.opencontainers.image.title": "metadata.json" }
    },
    {
      "mediaType": "application/vnd.opk.checksums.v1",
      "digest": "sha256:9f8e7d...",
      "size": 512,
      "annotations": { "org.opencontainers.image.title": "CHECKSUMS" }
    }
  ],
  "annotations": {
    "org.opencontainers.image.created": "2026-05-01T00:00:00Z",
    "org.opencontainers.image.title": "ripgrep",
    "org.opencontainers.image.version": "14.1.1-1",
    "org.opencontainers.image.licenses": "MIT OR Unlicense",
    "org.opencontainers.image.source": "https://github.com/BurntSushi/ripgrep",
    "org.opencontainers.image.revision": "4649aa9700d4dbaad0c85b0ac8b2c66e2b649b6c",
    "dev.opk.schema": "1",
    "dev.opk.name": "ripgrep",
    "dev.opk.version": "14.1.1",
    "dev.opk.revision": "1",
    "dev.opk.host": "x86_64-linux",
    "dev.opk.channel": "stable",
    "dev.opk.provides": "rg",
    "dev.opk.portable": "true"
  }
}
```

### 3.1 Rules

⛔ **`artifactType` MUST be set.** It is how a client tells a package from a
signature without downloading either.

⚠ **The historical system did not set it.** Verified on 2026-09-02 by
`experiments/40-registry-conformance.sh`: the live manifest at
`ghcr.io/pkgforge/bincache/b3sum/official/b3sum` reports `"artifactType":
null`. Every consumer therefore has to fetch and guess.

⛔ **Layer media types MUST describe what the layer contains.**

⚠ **The historical system publishes fifteen layers, all declaring
`application/vnd.oci.image.layer.v1.tar`, none of which is a tar file.**
Verified in the same run: the payload layer's digest equals the sha256 of the
raw `b3sum` executable. This is what `oras push` does when a media type is not
given. A generic OCI tool that trusts the declared type and tries to untar the
layer fails, and the failure is confusing because the file is fine.

⛔ **Annotations carry only what a client needs before fetching a layer.** They
are for filtering a listing. They are not a database, and §6 states the budget.

⛔ **The empty config blob MUST be pushed.** `application/vnd.oci.empty.v1+json`
has the fixed content `{}`, two bytes, digest
`sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a`.

⚠ **The historical system's manifest declares that media type with `"size":
0` and the digest of the *empty string*** rather than of `{}`. A strict client
that fetches and validates the config blob against its declared type finds two
bytes of nothing where JSON should be. It is tolerated by permissive clients
and it is not correct.

---

## 4. Multi-architecture: the index

One tag covering every host, so `opk install ripgrep@14.1.1-1` works without
the client knowing which hosts exist.

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "artifactType": "application/vnd.opk.package-index.v1+json",
  "manifests": [
    { "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "artifactType": "application/vnd.opk.package.v1+json",
      "digest": "sha256:d43111...", "size": 1234,
      "platform": { "architecture": "amd64", "os": "linux" },
      "annotations": { "dev.opk.host": "x86_64-linux" } },
    { "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "artifactType": "application/vnd.opk.package.v1+json",
      "digest": "sha256:7c0504...", "size": 1234,
      "platform": { "architecture": "arm64", "os": "linux" },
      "annotations": { "dev.opk.host": "aarch64-linux" } }
  ]
}
```

⛔ **Both `platform` and `dev.opk.host` are set.** They are not redundant:
`platform` uses Go's architecture names (`amd64`, `arm64`) which every OCI
tool understands, while `dev.opk.host` carries this system's own triple
including any microarchitecture suffix, which `platform` cannot express.

| host triple | `platform.architecture` | `platform.variant` |
| --- | --- | --- |
| `x86_64-linux` | `amd64` | absent |
| `x86_64-v3-linux` | `amd64` | ⚠ `v3`, and see below |
| `aarch64-linux` | `arm64` | absent |
| `riscv64-linux` | `riscv64` | absent |
| `armv7-linux` | `arm` | `v7` |
| `loongarch64-linux` | `loong64` | absent |

⚠ **`platform.variant` for x86-64 microarchitecture levels is not a settled
convention across tools.** `dev.opk.host` is authoritative here and the client
reads that; `platform.variant` is set for the benefit of generic tools and is
not relied on.

---

## 5. Evidence: referrers, and the fallback GHCR forces

Signature, SBOM, provenance and build log are separate manifests naming the
package as their `subject`.

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "artifactType": "application/vnd.opk.provenance.v1+json",
  "config": { "mediaType": "application/vnd.oci.empty.v1+json",
              "digest": "sha256:44136fa3...", "size": 2 },
  "layers": [
    { "mediaType": "application/vnd.in-toto+json",
      "digest": "sha256:cc33...", "size": 2048,
      "annotations": { "org.opencontainers.image.title": "provenance.json" } }
  ],
  "subject": {
    "mediaType": "application/vnd.oci.image.manifest.v1+json",
    "digest": "sha256:d4311144c0b4d63b4e2f6e22e3286602a9f8508fe14a02822c9c0ba1e5f60b07",
    "size": 1234
  },
  "annotations": { "org.opencontainers.image.created": "2026-05-01T00:00:00Z" }
}
```

⭐ **Why evidence is a referrer and not a layer.** A signature is created
*after* the manifest exists, because it signs that manifest's digest. Putting
it in the manifest would change the digest, which would invalidate the
signature. The circularity is not avoidable by being clever; the subject
relationship is the mechanism the spec provides for it.

### 5.1 ⛔ GHCR does not implement the referrers API

**Measured, 2026-09-02, by `experiments/40-registry-conformance.sh`, with two
controls held in the same run:**

| step | result |
| --- | --- |
| control A: registry's `Docker-Content-Digest` equals the digest we computed | ✅ held |
| control B: that digest resolves as a manifest | ✅ HTTP 200 |
| test: `GET /v2/<repo>/referrers/<that same digest>` | ❌ **HTTP 404 `MANIFEST_UNKNOWN`** |
| GHCR's advertised version | `docker-distribution-api-version: registry/2.0` |

⚠ **A 404 alone would prove nothing** because it equally means the digest was
wrong. The two controls are what turn it into evidence, and they are why the
probe refuses to report a verdict without them.

### 5.2 The fallback, and it is not a degraded mode

The distribution spec allows referrers to be published as an OCI image index
at the ordinary tag `sha256-<hex>`, where `<hex>` is the subject digest's hex
with `:` replaced by `-`.

⛔ **A publisher MUST write the fallback tag.** ⛔ **A client MUST try the
referrers API first and fall back to the tag on 404.**

```
subject digest   sha256:d4311144c0b4d63b4e2f6e22e3286602a9f8508fe14a02822c9c0ba1e5f60b07
fallback tag     sha256-d4311144c0b4d63b4e2f6e22e3286602a9f8508fe14a02822c9c0ba1e5f60b07
```

The index at that tag carries one entry per referrer, keeping each referrer's
`artifactType` and `annotations` so a client filters without fetching:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "manifests": [
    { "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "artifactType": "application/vnd.opk.signature.v1",
      "digest": "sha256:aa11...", "size": 800 },
    { "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "artifactType": "application/vnd.opk.buildlog.v1",
      "digest": "sha256:dd44...", "size": 700 }
  ]
}
```

**Proven working** by `experiments/41-referrers-fallback.sh`, which runs the
discovery routine with the API path disabled and finds the same referrers by
`artifactType` that the API returned, then returns cleanly for a subject with
none.

⛔ **Writing the fallback tag is not atomic and the race is real.** Two
concurrent attaches both read the index, both append, and the second write wins,
losing the first. The publisher **MUST** serialise fallback-tag writes per
subject. [`../ci/ci-system.md`](../ci/ci-system.md) §concurrency specifies the
lock, and a reconciliation job repairs any index that lost an entry.

⚠ **The reconciliation job is not optional belt-and-braces.** A lost signature
entry presents to a user as an unsigned package, which under the default trust
policy is a refused install.

### 5.3 Discovery algorithm

```
discover_referrers(repo, subject_digest, artifact_type=None):
    r = GET /v2/{repo}/referrers/{subject_digest}
        [+ ?artifactType={artifact_type} if supported]
    if r.status == 200:
        return r.body.manifests           # filter locally too: the server
                                          # MAY ignore the query parameter
    if r.status in (404, 400, 405):
        tag = subject_digest.replace(":", "-")
        r2 = GET /v2/{repo}/manifests/{tag}
             Accept: application/vnd.oci.image.index.v1+json
        if r2.status == 200:
            return r2.body.manifests
        if r2.status == 404:
            return []                     # no referrers, not an error
    raise RegistryError(r.status)
```

⚠ **Filter locally even when the server accepted an `artifactType` query.** The
spec permits a registry to ignore the filter and return everything, and it
signals that with an `OCI-Filters-Applied` header a client must not assume is
present.

---

## 6. GHCR constraints

Everything in this table is a property of GHCR, not of this design.

| # | constraint | status | consequence |
| --- | --- | --- | --- |
| G1 | no referrers API | ⭐ **measured** 2026-09-02, controls held | fallback tag is mandatory |
| G2 | tags are mutable and unprotected | documented behaviour of the API | signatures cover digests only |
| G3 | anonymous pull needs a token from `ghcr.io/token` | ⭐ measured: token obtained, manifest fetched | clients must implement the token flow, not just basic auth |
| G4 | a package's visibility is set in GitHub Packages, not by the registry API | GitHub documentation | first push of a new repository is private; publishing requires a UI or API step |
| G5 | deleting a version is a GitHub Packages API call | GitHub documentation | retention is not a registry operation. [`retention.md`](retention.md) |
| G6 | manifest size ceiling | ⚠ **not measured here** | the annotation budget in §6.1 is set conservatively |
| G7 | rate limits on the token endpoint and on pulls | ⚠ **not measured here** | [`../ops/rate-limits.md`](../ops/rate-limits.md) states the budget and how it is discovered |
| G8 | `GITHUB_TOKEN` in Actions can push to the same org | GitHub documentation | no long-lived registry credential is needed in CI |

⛔ **G6 and G7 are marked unmeasured on purpose.** Measuring them requires
pushing to a real GHCR namespace with credentials this repository does not
have. The exact command that would measure each is in
[`../open-questions.md`](../open-questions.md), so the next person with an
account can close them in minutes rather than re-deriving the question.

### 6.1 Annotation budget

Until G6 is measured, the design keeps well inside any plausible ceiling:

| rule | value |
| --- | --- |
| total annotation bytes per manifest | **SHOULD NOT** exceed 8 KiB |
| a single annotation value | **MUST NOT** exceed 1 KiB |
| number of annotations | **SHOULD NOT** exceed 32 |

⛔ **`dev.opk.provides` is a comma-separated list and it can be long.** When it
would exceed 1 KiB the annotation is truncated with a trailing `,...` and the
authoritative list stays in the metadata layer. A client that needs the full
list fetches the layer.

---

## 7. Authentication

| actor | credential | scope |
| --- | --- | --- |
| anonymous client | a token from `ghcr.io/token` for `repository:<repo>:pull` | ⭐ read-only, public packages |
| CI publisher | the workflow's `GITHUB_TOKEN` with `packages: write` | push to the same org |
| a human publishing by hand | a personal access token with `write:packages` | ⚠ discouraged; see below |
| mirror agent | a read token for the source, a write token for the destination | |

⛔ **A long-lived personal access token is not used in automation.** In
GitHub Actions the ephemeral `GITHUB_TOKEN` is scoped to the run and expires
with it. [`../security/secrets.md`](../security/secrets.md) is the full
credential inventory.

⚠ **`oras login` writes credentials to a config file in plain text by
default.** In CI that file lives on a runner that is destroyed; on a developer
machine it does not. `opk` uses a credential helper where one exists and warns
when it falls back to a file.

---

## 8. Migrating to another registry

⭐ **The layout uses no GHCR-specific feature**, which is the point of using
open specifications. Moving to another registry is:

1. copy every manifest and blob, preserving digests, with `oras cp` or
   `skopeo copy --all`;
2. recreate the tags, including the `sha256-*` fallback tags;
3. re-point the index's `registry` field and re-sign the index;
4. publish the new location; clients pick it up on their next index refresh.

⛔ **Digests are preserved by the copy, so every existing signature stays
valid.** That is the property that makes migration a copy rather than a
re-signing exercise, and it is a direct consequence of signing digests rather
than tags.

⚠ **What does not survive a move**: download counts, GitHub Packages
visibility settings, and anything that reads `ghcr.io` from a hardcoded string.
[`../migration.md`](../migration.md) §registry-move has the checklist.

⚠ **A registry that DOES implement the referrers API still needs the fallback
tags written**, or a client that used the API at the old registry and the
fallback at the new one sees a different set. The publisher always writes both.
