# trust and verification

What the client checks, in what order, what it refuses, and how a user changes
that.

---

## 1. ⛔ The verification chain

```
  the user's trusted key set
      │  verifies
      ▼
  the signed INDEX  ──────────► name → version → digest + payload hash
      │                                       │
      │ resolves to                           │ carries
      ▼                                       ▼
  a MANIFEST fetched BY DIGEST         an expected payload hash
      │  its own digest is                    │
      │  what the signature covers            │
      ▼                                       ▼
  LAYERS fetched by digest ──────────► hashed while streaming to disk
                                              │
                            ⛔ BOTH must agree before anything is installed
```

⭐ **The two checks are independent, and that is the point.** The signature says
a key holder approved this manifest digest. The hash says these bytes are what
the index recorded. A signed manifest carrying a wrong hash still fails.
Invariant I6 in [`../architecture.md`](../architecture.md).

---

## 2. The order, and why it is this order

⛔ **A client MUST perform these in order.** Each step's input is the previous
step's verified output.

| # | step | on failure |
| --- | --- | --- |
| 1 | verify the index signature against the trusted key set | ⛔ refuse everything, exit 11 |
| 2 | check index freshness against the last seen | ⛔ refuse if older, exit 11 |
| 3 | resolve the name to a release coordinate | exit 12 |
| 4 | read the digest and payload hash from the verified index | |
| 5 | fetch the manifest **by digest** | exit 13 |
| 6 | check the manifest's own digest matches what was requested | ⛔ exit 13 |
| 7 | fetch layers by digest, hashing while writing | exit 13 |
| 8 | compare the payload hash against the index's | ⛔ exit 13 |
| 9 | discover referrers, fetch the signature | |
| 10 | verify the signature over the manifest digest | exit 14, per policy |
| 11 | validate every path in the metadata | ⛔ exit 15 |
| 12 | unpack into staging, verify declared paths exist | exit 15 |
| 13 | atomic rename, then link | |

⛔ **Nothing is executable before step 13.** Steps 1 to 12 write only into a
staging directory removed on any failure.

⚠ **Step 6 is not redundant with step 5.** A registry can return content that
does not match the digest requested, whether through a bug, a cache, or malice.
The client hashes what arrived.

⚠ **Step 7 hashes while streaming.** Reading the whole layer into memory to
hash it afterwards puts a ceiling on artefact size that will be hit in
production and not in a fixture.

---

## 3. Trust policies

⛔ **Named, and the active one is printed on every install.** A user who cannot
tell which policy is in force cannot reason about what was checked.

| policy | index signature | package signature | provenance | use |
| --- | --- | --- | --- | --- |
| `strict` | ⛔ required | ⛔ required | ⛔ required, and the builder must match | high-assurance environments |
| ⭐ `default` | ⛔ required | ⛔ required | recorded, not required | ⭐ **the default** |
| `hash-only` | ⛔ required | ⚠ warned if absent | recorded | ⚠ mirrors with no signing key |
| `unverified` | ⚠ warned | ⚠ warned | | ⛔ local development only |

⛔ **`unverified` prints a warning on every operation, not once.** A mode that
becomes invisible is a mode that becomes permanent.

⛔ **The hash check runs under every policy, including `unverified`.** It is not
a trust decision; it is an integrity check against corruption, and disabling it
buys nothing.

⚠ **`hash-only` exists for a real case**: an air-gapped mirror populated from a
verified source, where the signing key is deliberately not present on the
internal network. Using it because signature verification is inconvenient
defeats the design.

---

## 4. The trusted key set

```
$XDG_CONFIG_HOME/opk/trust.toml
```

```toml
[[key]]
id      = "opk-release-2026"
algo    = "minisign"
public  = "RWS...base64..."
repos   = ["opk"]
added   = "2026-01-01"
expires = "2028-01-01"

[[key]]
id     = "opk-release-sigstore"
algo   = "sigstore"
issuer = "https://token.actions.githubusercontent.com"
subject_pattern = "^https://github.com/example/opk-packages/\\.github/workflows/publish\\.yaml@refs/heads/main$"
repos  = ["opk"]
```

| field | rule |
| --- | --- |
| `repos` | ⛔ a key is scoped. A key trusted for one repository does not verify another's packages. |
| `expires` | ⚠ a key past expiry does not verify; the client says so rather than reporting a bad signature |
| `subject_pattern` | ⛔ anchored. An unanchored pattern matching a substring is an authentication bypass. |

### 4.1 Bootstrapping

⛔ **The first key has to come from somewhere, and every option has a cost.**

| route | trust rests on |
| --- | --- |
| ⭐ shipped in the client binary | ⭐ whoever the user got the client from |
| fetched over TLS from a project domain | the web PKI and the domain |
| ⚠ TOFU on first use | ⛔ that the first fetch was not attacked |
| out of band | ⭐ the strongest, and nobody does it |

⭐ **The client ships the key.** Getting the client is already a trust decision,
and adding a second independent one does not make it stronger, it makes it
easier to skip.

⛔ **The client MUST print the key fingerprint on first run** so a user can
compare it against a published value if they choose.

⚠ **TOFU is not used for release keys.** It is acceptable for a user's own
private repository, where the alternative is no verification at all, and the
client marks such a key as TOFU-acquired in `opk trust list`.

### 4.2 Rotation

⛔ **A new key is published, signed by the old one, and both are trusted during
an overlap.**

```
T+0     publish new key, signed by old. Both trusted. Sign with old.
T+30d   sign with new. Both still verify.
T+180d  old key removed from the shipped set.
        ⛔ artefacts signed only by the old key stop verifying.
```

⚠ **That last line is the one that hurts.** An artefact from three years ago,
signed with a retired key, no longer verifies under the current key set. Two
answers, and the design takes the second:

| option | cost |
| --- | --- |
| keep every retired key trusted forever | ⛔ a compromised old key stays useful forever |
| ⭐ re-sign the archive with the current key when rotating | ⭐ work at rotation time, bounded and scheduled |

⛔ **Compromise is not rotation.** A compromised key is revoked immediately, its
artefacts are re-signed, and the revocation is published in the index. There is
no overlap period.

---

## 5. Provenance verification, under `strict`

The provenance attestation is checked for:

| check | |
| --- | --- |
| the `subject` digest matches the artefact | ⛔ mandatory whenever provenance is read at all |
| `builder.id` matches a trusted builder pattern | `strict` only |
| the source repository matches the package's declared source | `strict` only |
| ⚠ the attestation's own signature | ⛔ an unsigned attestation is a claim, not evidence |

⛔ **An unsigned provenance statement is worth nothing** and the client says so
rather than displaying it as if it were verified.

---

## 6. What a refusal looks like

⛔ **A refusal names what failed, what was expected, what was found, and what
the user can do.**

```
opk: refusing to install ripgrep 14.1.1-1 (x86_64-linux)

  signature verification failed
    manifest  sha256:d4311144c0b4d63b4e2f6e22e3286602a9f8508fe14a02822c9c0ba1e5f60b07
    key       opk-release-2026 (RWS4f2...)
    reason    no signature found among 3 referrers

  This package is not signed by a key you trust.
  To see what evidence exists:      opk verify ripgrep --explain
  To install anyway, this once:     opk install ripgrep --trust-policy hash-only
                                    (the payload hash is still checked)
```

⚠ **The escape hatch is shown, and it is per-invocation.** Hiding it produces
users who disable verification permanently in a config file; naming it with its
exact scope produces users who use it once.

⛔ **The message never suggests a flag that disables the hash check**, because
none exists.

---

## 7. `opk verify`

Re-runs verification against what is installed or against a coordinate, and
prints the chain:

```
$ opk verify ripgrep --explain
ripgrep 14.1.1-1 x86_64-linux
  index signature      ✅ opk-release-2026, generated 2026-09-01T10:04:11Z (2h ago)
  manifest digest      ✅ sha256:d4311144...
  payload hash         ✅ b3:0e5f0c9d... matches the index
  package signature    ✅ opk-release-2026 over the manifest digest
  provenance           ✅ subject matches; builder github.com/example/opk-packages
  sbom                 ✅ present, SPDX-2.3
  build log            ✅ present, 412 lines
  installed files      ✅ 3 files match CHECKSUMS
```

⭐ **This is the command that makes the security model legible.** A user who
cannot see what was checked cannot tell a working system from a decorative one.
