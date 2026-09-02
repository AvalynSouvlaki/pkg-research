# delta updates, caching and garbage collection

Reclaiming disk on the client, and reducing what has to cross the network.

Registry-side retention is [`../registry/retention.md`](../registry/retention.md).

---

## 1. Caching

```
<cache>/blobs/sha256/<digest>       ⭐ content-addressed
<cache>/index/<repository>/<digest>
<cache>/tmp/
```

⭐ **Keyed by digest, so a cache entry can never be wrong.** A blob either
hashes to its name or it is corrupt and discarded.

| property | value |
| --- | --- |
| eviction | least recently used, above `cache.max-size`, default 5 GiB |
| ⛔ pinned entries | `--pin-cache` marks blobs as not evictable |
| ⭐ sharing between prefixes | ⭐ safe: content addressing means no collision |
| ⚠ concurrent writers | write to `tmp/` then rename; ⛔ never write in place |
| corruption | detected on read, entry discarded, refetched |

⛔ **Never write a blob in place.** A partially written file that already has
its final name is a cache entry a later run will trust.

⚠ **A shared cache on a multi-user machine is a mode this design supports and
does not default to.** It works because of content addressing, and it leaks
which packages other users are installing, which is why `cache/` is `0700` per
[`installation-layout.md`](installation-layout.md) §8.

---

## 2. Delta updates

⛔ **Delta at three levels, and only the first is free.**

### 2.1 Layer reuse

⭐ **Free, and it is the one that matters.** An upgrade fetches only the layers
whose digests changed. A package whose licence, metadata and checksums are
unchanged fetches only the payload.

⚠ **In practice the payload is nearly all of it**, so the saving is small for a
single-layer artefact. §2.2 is what would change that.

### 2.2 Splitting the payload

⚠ **Considered and not adopted by default.**

Splitting an artefact into several layers, for example the binary in one and
the documentation in another, means an upgrade that only changed the binary
skips the rest.

| | |
| --- | --- |
| ⭐ gains | real for packages with large static data |
| ⛔ costs | more blobs per package, more requests, more registry objects, and a rate-limit cost per request |
| ⚠ verdict | ⭐ **opt-in per package** through `[artifact.layers]`, not a default |

⛔ **More requests is not a free trade.** [`../ops/rate-limits.md`](../ops/rate-limits.md)
is the constraint, and a design that quadruples request count to save bandwidth
has optimised the wrong resource for a registry-hosted system.

### 2.3 Binary deltas

⚠ **Specified as possible, not implemented, and honestly assessed.**

A binary diff between two versions of a static binary, `bsdiff` or `zstd
--patch-from`, can be much smaller than the whole artefact.

| | |
| --- | --- |
| ⭐ gain | ⚠ large in principle; a static binary's code shifts, so a naive diff can be poor |
| cost | ⛔ a patch per version pair, or per version to the newest, stored in the registry |
| ⛔ verification | ⭐ the *result* is hashed and must match; a patch is never trusted |
| ⚠ complexity | a new artefact kind, a new failure mode, and a new thing to get wrong |

⛔ **A delta is a transport optimisation and never a trust path.** The client
applies the patch, hashes the result, and compares against the signed hash. A
mismatch discards the patch and fetches the whole artefact.

⚠ **Not measured here**, and a real implementation should measure before
building it: for a 5 MB Rust binary between adjacent patch versions, the
question is whether the delta is 200 KB or 4 MB, and that depends on the
compiler and the change.
[`../open-questions.md`](../open-questions.md).

---

## 3. Garbage collection

```sh
opk gc                       # apply the configured policy
opk gc --dry-run             # ⭐ what would go
opk gc --keep 1              # only the active version per package
opk gc --older-than 90d
opk gc --cache-only
```

### 3.1 ⛔ What is never collected

| | |
| --- | --- |
| ⛔ the active version of an installed package | |
| ⛔ the immediately previous version | ⭐ it is what `opk rollback` uses |
| ⛔ anything pinned with `opk pin` | |
| ⛔ `etc/` | |
| ⛔ state and history | |

**Default policy**: keep the active version plus 1 previous, per package. Cache
blobs evict by LRU above the size cap.

### 3.2 What it reclaims

| | |
| --- | --- |
| version directories beyond the keep count | |
| cache blobs above the cap | |
| ⚠ orphaned staging directories | from a hard kill |
| dangling symlinks | ⭐ reported, not silently removed; a dangling link is a bug worth seeing |

⚠ **`gc` prints what it removed and how much it reclaimed.** A command that
frees 3 GB silently is a command users do not trust and therefore do not run.

```
$ opk gc
removed  ripgrep 14.0.3-1         5.0 MiB
removed  fd 9.0.0-1               3.2 MiB
evicted  12 cache blobs          48.1 MiB
kept     ripgrep 14.1.0-1        (previous version, needed for rollback)

reclaimed 56.3 MiB
```

⛔ **The `kept` line matters as much as the `removed` lines.** A user running
`gc` to free space needs to know why something stayed.

---

## 4. Interaction with rollback

⚠ **`gc` can make a rollback impossible**, and the client is explicit about it:

```
$ opk gc --keep 1
⚠ this removes the previous version of 12 packages
  `opk rollback` for those will need to download again
  continue? [y/N]
```

⭐ **The failure, when it comes, is clear** rather than a confusing error:
[`client-behaviour.md`](client-behaviour.md) §5 shows the message, which names
the collection date and offers the `downgrade` form that refetches.

---

## 5. Disk pressure

⚠ **An install that runs out of disk mid-unpack must not corrupt anything.**

| control | |
| --- | --- |
| ⭐ check free space against the metadata's size before staging | fail early with a clear message |
| ⭐ stage, then rename | ⛔ a failed unpack leaves only a staging directory |
| ⚠ on `ENOSPC` | remove staging, report the shortfall and the space needed |
| ⛔ never | ⛔ run `gc` automatically to make room |

⛔ **Automatic garbage collection during an install is a destructive action a
user did not ask for**, taken at the moment they are least able to think about
it. The client suggests `opk gc` and stops.
