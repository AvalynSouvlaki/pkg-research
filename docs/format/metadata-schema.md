# metadata schema

The JSON a client consumes. One document per published release, shipped as a
layer inside the artefact and summarised into the index.

[`build-manifest.md`](build-manifest.md) is what a human writes.
**This is what a machine reads.** They are different documents on purpose: the
recipe carries build instructions a client must never see, and the metadata
carries resolved facts a recipe cannot know until after a build.

---

## 1. Versioning

⛔ **Every metadata document carries `schemaVersion` as its first key.**

| rule | |
| --- | --- |
| a client **MUST** refuse a `schemaVersion` it does not implement | |
| a client **MUST NOT** guess from field presence | ⚠ a positional or implicit format with no version mis-reads silently when its shape changes, which corrupts rather than errors |
| adding an optional field does not bump the version | |
| removing a field, changing a type, or changing a meaning does | |
| a client **MUST** ignore unknown *optional* fields at a version it supports | forward compatibility within a major |

Current version: **1**.

---

## 2. The document

```json
{
  "schemaVersion": 1,
  "repository": "opk",
  "family": "ripgrep",
  "name": "ripgrep",
  "version": "14.1.1",
  "revision": 1,
  "epoch": 0,
  "host": "x86_64-linux",
  "channel": "stable",

  "description": "Recursively search directories for a regex pattern",
  "homepage": ["https://github.com/BurntSushi/ripgrep"],
  "license": ["MIT", "Unlicense"],
  "maintainer": ["Example Person <person@example.org>"],
  "category": ["ConsoleOnly", "Utility"],
  "tag": ["grep", "search"],
  "note": [],

  "provides": [
    { "program": "rg", "aliases": [], "symlinks": [], "path": "bin/rg" }
  ],

  "portable": true,
  "portable_reason": null,
  "min_kernel": null,
  "microarch": null,

  "artifact": {
    "manifest_digest": "sha256:d4311144c0b4d63b4e2f6e22e3286602a9f8508fe14a02822c9c0ba1e5f60b07",
    "size": 5242880,
    "files": [
      { "path": "bin/rg", "sha256": "sha256:afb4...", "blake3": "b3:0e5f...",
        "size": 5238784, "mode": "0755", "elf": {
          "machine": "x86_64", "interp": null, "needed": [], "build_id": null } },
      { "path": "share/licenses/ripgrep/LICENSE-MIT", "sha256": "sha256:1a2b...",
        "blake3": "b3:9f8e...", "size": 1071, "mode": "0644", "elf": null }
    ]
  },

  "source": {
    "kind": "git",
    "url": "https://github.com/BurntSushi/ripgrep",
    "commit": "4649aa9700d4dbaad0c85b0ac8b2c66e2b649b6c",
    "upstream": "https://github.com/BurntSushi/ripgrep"
  },

  "build": {
    "image": "docker.io/library/rust@sha256:b4b54b17...",
    "target": "x86_64-unknown-linux-musl",
    "source_date_epoch": 1714435200,
    "hermetic": false,
    "network": "restricted",
    "builder_id": "https://github.com/example/opk-packages/.github/workflows/build.yaml@refs/heads/main",
    "run_url": "https://github.com/example/opk-packages/actions/runs/1234567890",
    "recipe_url": "https://github.com/example/opk-packages/blob/4d5e6f/packages/ripgrep/opk.toml",
    "recipe_sha256": "sha256:7c8d9e..."
  },

  "evidence": {
    "signature":  "sha256:aa11...",
    "sbom":       "sha256:bb22...",
    "provenance": "sha256:cc33...",
    "buildlog":   "sha256:dd44..."
  },

  "created": "2026-09-01T10:04:11Z",
  "snapshots": ["14.1.0-1", "14.0.3-1"]
}
```

---

## 3. Field reference

### 3.1 Identity

| field | type | required | notes |
| --- | --- | --- | --- |
| `schemaVersion` | integer | yes | first key |
| `repository` | string | yes | which package set |
| `family`, `name` | string | yes | [`package-identity.md`](package-identity.md) §1 |
| `version` | string | yes | validated against the version grammar |
| `revision` | integer | yes | ≥ 1 |
| `epoch` | integer | yes | ≥ 0, usually 0 |
| `host` | string | yes | host triple |
| `channel` | string | yes | |

### 3.2 Human-facing

`description`, `homepage`, `license`, `maintainer`, `category`, `tag`, `note`
carry the recipe's values unchanged. ⚠ **A client MUST treat every one as
untrusted display text**: escape it before rendering, never interpret it as
markup, and never pass it to a shell.
[`../security/security-model.md`](../security/security-model.md) §display.

### 3.3 `provides`

An array of objects, not of strings, because the operators in the recipe's
compact syntax are ambiguous to re-parse.

| field | type | meaning |
| --- | --- | --- |
| `program` | string | the program name |
| `aliases` | array of string | search-only alternatives |
| `symlinks` | array of string | additional names created on disk |
| `path` | string | where in the artefact the program is |
| `path_only` | bool | true when `=>` was used: only the symlink reaches `PATH` |

⭐ **The client never re-parses the recipe's `provides` string.** It reads this
structure. One read path, one write path.

### 3.4 `artifact`

| field | type | notes |
| --- | --- | --- |
| `manifest_digest` | string | the OCI manifest digest. ⛔ This is what a signature covers. |
| `size` | integer | total unpacked bytes |
| `files[]` | array | ⛔ **every** shipped file, with both hashes |
| `files[].elf` | object or null | present for ELF files, from `tools/elfprobe.py` |

⭐ **`files[].elf.interp` being non-null is the machine-checkable form of "this
is not portable".** A client can refuse it under a strict policy without
running anything.

### 3.5 `build`

| field | notes |
| --- | --- |
| `hermetic` | ⛔ `true` only when `network = "none"`. Never asserted otherwise. |
| `builder_id` | the SLSA builder identity, matching the provenance attestation |
| `run_url` | the CI run, so a human can reach the log the ordinary way |
| `recipe_url` | ⭐ the exact recipe, at the exact commit, that produced this |
| `recipe_sha256` | so the linked recipe can be checked against what was built |

⭐ **`recipe_url` plus `recipe_sha256` is the linkage that made the historical
system's package pages useful.** Era 1 published `build_script` pointing at the
recipe and `build_gha` pointing at the CI run, and users could go from a binary
to the source of its build in two clicks. ⚠ Era 1's link pointed at
`refs/heads/main`, so it drifted: following it later showed the *current*
recipe, not the one that built the artefact. This schema pins the commit and
records the hash so the drift is both prevented and detectable.

### 3.6 `evidence`

Digests of the referrer artefacts. ⚠ **Advisory, not authoritative.** A client
**MUST** still discover referrers from the registry
([`../registry/oci-ghcr.md`](../registry/oci-ghcr.md) §referrers) rather than
trusting this map, because evidence can be attached after the metadata was
written. The map exists so a client can fetch the signature in one round trip
in the common case, and it is checked against what discovery returns.

### 3.7 `snapshots`

Previously published `version-revision` pairs for this package and host, newest
first, at most 64 entries.

⭐ **This is what makes `opk rollback` work without a network round trip per
candidate**, and it is adopted from era 2's `snapshots` field, which existed for
the same reason.

---

## 4. What is NOT in the metadata

⛔ Each of these was considered and excluded, with the reason.

| excluded | why |
| --- | --- |
| the build script | a client has no use for it, and shipping it invites a client to run it |
| `[update]` | it is a bot's input, and shipping it tells an attacker what to poison |
| download counts, ranking | mutable and not integrity-relevant; they belong in the index |
| a mirror list | ⛔ a mirror list inside a signed artefact cannot be updated when a mirror dies without re-signing every package. Mirrors are client configuration. |
| absolute install paths | the artefact is relocatable; the client decides |
| a timestamp of *this* document's generation | it would differ between two otherwise identical builds and break reproducibility |

⚠ **The last row is subtle and it has bitten real systems.** `created` above is
the *source* epoch rendered as a timestamp, not the moment the file was
written. Two reproducible builds produce identical metadata, and a metadata
document that differs only by a generation timestamp makes the whole artefact
non-reproducible for no benefit.

---

## 5. Validation

A client **MUST**, before acting on a metadata document:

1. check `schemaVersion` is supported;
2. check `name`, `version`, `revision`, `host` against their grammars;
3. check every `files[].path` against the path rules in
   [`build-manifest.md`](build-manifest.md) §9;
4. check that every `provides[].path` appears in `files[]`;
5. check that the document's own hash matches what the index recorded.

⛔ **Step 3 is not optional and it is not the archive extractor's job.** A
metadata document is attacker-influenced if the registry is compromised, and a
`files[].path` of `../../.bashrc` is a working attack against a client that
trusts it. Defence in depth: the extractor rejects it too.
