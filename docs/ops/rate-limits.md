# rate limits

Registry and forge limits, what is measured and what is not, and how the system
stays inside a budget it cannot see.

---

## 1. ⛔ What is measured here, and what is not

⛔ **This repository measured none of the production limits.** It has no GHCR
namespace and no deployment. Every figure below is either from a provider's
published documentation or is a design budget chosen conservatively, and each
row says which.

⚠ **A limit quoted without its source and date is worse than no limit**,
because it gets planned around and then turns out to be wrong.
[`../open-questions.md`](../open-questions.md) carries the exact commands that
would measure each.

| limit | status |
| --- | --- |
| GHCR anonymous pulls | ⚠ **not measured**, not clearly documented |
| GHCR authenticated pulls | ⚠ **not measured** |
| GHCR pushes | ⚠ **not measured** |
| GHCR manifest size ceiling | ⚠ **not measured** |
| ⭐ GitHub REST API, authenticated | ⭐ documented: 5,000 requests per hour per token |
| ⭐ GitHub REST API, `GITHUB_TOKEN` in Actions | ⭐ documented: 1,000 requests per hour per repository |
| ⭐ GitHub REST API, unauthenticated | ⭐ documented: 60 requests per hour per address |
| GitHub Actions concurrency | ⭐ documented, plan-dependent |

⭐ **The one measurement this repository did take**: an anonymous GHCR pull
token was obtained and a manifest fetched successfully, by
`experiments/40-registry-conformance.sh`. That establishes the token flow
works anonymously, and nothing about volume.

---

## 2. ⛔ Design under an unknown limit

⭐ **Assume the tighter reading.** Where a limit is documented ambiguously, or
not at all, budget as though the strict interpretation holds. You are then
correct under both, and the optimistic reading is right only if you are lucky
and wrong in the direction that causes an outage.

| principle | consequence |
| --- | --- |
| ⭐ read the response, not the documentation | ⭐ `x-ratelimit-remaining` is ground truth; a doc is a claim |
| ⛔ honour `Retry-After` | ⛔ never a fixed sleep |
| ⭐ back off exponentially with jitter | a fleet retrying in lockstep is a second outage |
| ⛔ cap total retries | ⛔ a spiral makes the limit worse for everyone |
| ⭐ cache by digest | ⭐ the cheapest request is the one not made |
| ⚠ prefer routes with no quota | `git ls-remote` over the tags API |

⛔ **Retrying a rate limit without honouring its stated delay, and without a
cap, is the failure that turns a brief limit into a sustained one.**

---

## 3. The budget

⭐ **Design targets, not measurements.** They are set well inside the documented
figures so that a wrong assumption costs headroom rather than an outage.

| actor | budget | why |
| --- | --- | --- |
| update bot | ⭐ 1 request per package per run | ⭐ one strategy query; nothing else |
| update bot, total | 500 requests per run | ⛔ half the Actions per-repository hour |
| build job | ⚠ pulls one image, one source, its dependencies | dominated by the ecosystem, not by us |
| publish | ⭐ one manifest push plus its blobs, per package per host | |
| index generation | ⭐ one manifest fetch per release per host, ⭐ cached by digest | ⚠ the largest consumer; §4 |
| a client install | ⭐ one index fetch, one manifest, one blob set | ⭐ cached |
| a client update check | ⭐ **one** conditional request | §5 |

⛔ **`max-parallel` in the build matrix is a rate-limit control as much as a
cost control.** Four is the default here because it keeps push volume
predictable, not because four is fast.

---

## 4. ⭐ Index generation is the biggest consumer

Naively, regenerating an index over 1,000 packages on 2 hosts is 2,000 manifest
fetches plus 2,000 metadata blob fetches.

| control | effect |
| --- | --- |
| ⭐ cache by manifest digest | ⭐ a package that did not change costs one HEAD, or nothing |
| ⭐ incremental generation | only what the publish touched |
| ⭐ a full rebuild on a schedule, not per publish | ⭐ amortised |
| ⚠ conditional requests | ⭐ `If-None-Match` against a stored ETag |

⛔ **A full index rebuild on every publish is the shape that will hit a limit
first**, and it is the obvious implementation. Incremental generation with a
periodic full rebuild is specified in
[`../registry/index-and-search.md`](../registry/index-and-search.md) §5, and
this is the reason.

---

## 5. Client behaviour

⭐ **A client's whole steady-state cost should be one conditional request.**

```
opk update:
  HEAD the index tag
  ⭐ if the digest equals what we have, stop. Nothing else.
  otherwise fetch the index, verify, store the digest
```

⛔ **A client MUST NOT poll on a timer of its own choosing.** An automatic
background refresh with a short interval multiplied by every user is a
self-inflicted denial of service on the project's own registry, and the
individual user gains nothing.

| behaviour | value |
| --- | --- |
| index refresh | ⭐ on demand, or once per day at most |
| ⚠ jitter on a scheduled refresh | ⭐ required, or every client refreshes at midnight |
| ⛔ on 429 | ⛔ honour `Retry-After`, then exit 18 rather than spinning |
| ⭐ mirrors | ⭐ spread load off the primary |

⚠ **Exit 18 rather than retrying forever is deliberate.** A client that hangs
retrying looks broken to the user and keeps consuming the limit; one that exits
with a specific code lets a script decide.

---

## 6. Mirrors as a rate-limit control

⭐ **The most effective single measure available to a large consumer.**

| deployment | effect |
| --- | --- |
| an organisation's pull-through cache | ⭐ one fetch upstream serves every machine |
| a CI fleet pointed at an internal mirror | ⭐ removes the fleet from the primary's budget entirely |
| a geographic mirror | latency, and load spread |

⚠ **A pull-through cache must key by digest**, or it serves the wrong content
for a moved tag. [`../ops/failure-modes.md`](failure-modes.md) F7.

---

## 7. What to do when limited

```
1. read the response headers: which limit, how much is left, when it resets
2. ⛔ honour Retry-After
3. ⭐ identify the consumer: index generation, the bot, the build matrix, clients
4. reduce that consumer's concurrency first
5. ⭐ if it is clients, publish a mirror and say so
6. ⚠ if it persists, the budget in §3 is wrong: measure and rewrite this page
```

⛔ **Do not raise concurrency to "get through the backlog".** It is the
response the limit exists to prevent, and it converts a delay into a longer one.

---

## 8. Authentication and quota

⭐ **Authenticated requests get a much larger quota**, so the cheapest
improvement available to most consumers is to authenticate.

| route | quota source |
| --- | --- |
| anonymous | ⚠ shared per address; a CI runner shares with everyone on that address |
| ⭐ a token | per token |
| ⭐ `GITHUB_TOKEN` in Actions | per repository, ephemeral |

⚠ **A shared-address anonymous quota is the one that bites unexpectedly**, and
it explains failures that look random: a hosted runner's address is shared, so
another tenant's traffic can exhaust it.

⭐ **A client SHOULD support an optional token for exactly this reason**, and
⛔ **MUST NOT require one for public packages.** Requiring authentication to
install public software would defeat the point.
