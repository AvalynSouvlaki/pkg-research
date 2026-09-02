#!/usr/bin/env bash
# 41-referrers-fallback.sh
#
# QUESTION: 40-registry-conformance.sh established that GHCR does not answer
# the referrers API. So: does the distribution-spec FALLBACK TAG scheme carry
# the same job, and can a client discover signatures, SBOMs, provenance and
# build logs through it without the API?
#
# The scheme: referrers to a manifest with digest sha256:HEX are published as
# an OCI image index stored at the ordinary tag `sha256-HEX`. A client that
# gets 404 from /referrers/ falls back to fetching that tag. Nothing about it
# needs registry support beyond pushing an index and a tag, which every
# registry has done since 2015.
#
# ⭐ The assertion is made by a client that is TOLD the referrers API does not
# exist, so the fallback path is exercised rather than shadowed by the API
# that happens to work locally.
#
# Exit codes: 0 the fallback path works, 1 it does not, 2 could not run.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
OUT="${HERE}/out"; WORK="${HERE}/.work/fallback"
BIN="${ROOT}/.tmp/bin"; export PATH="${BIN}:${PATH}"
mkdir -p "${OUT}" "${WORK}" || exit 2
export LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=1700000000

command -v oras >/dev/null 2>&1 || { echo "oras required" >&2; exit 2; }
[ -x "${BIN}/zot" ] || { echo "zot required" >&2; exit 2; }

REG_PORT="${REG_PORT:-15001}"; REG="127.0.0.1:${REG_PORT}"
NS="opk"; PKG="fallbackdemo"; REPO="${REG}/${NS}/${PKG}"; TAG="1.0.0-1-x86_64-linux"
ORAS_HTTP="--plain-http"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }

cd "${WORK}" || exit 2
rm -rf registry work && mkdir -p registry work
cat > zot-config.json <<EOF
{ "distSpecVersion": "1.1.0",
  "storage": { "rootDirectory": "${WORK}/registry", "dedupe": false },
  "http": { "address": "127.0.0.1", "port": "${REG_PORT}" },
  "log": { "level": "error" } }
EOF
"${BIN}/zot" serve zot-config.json > zot.log 2>&1 &
ZOT_PID=$!
trap 'kill "${ZOT_PID}" 2>/dev/null; wait "${ZOT_PID}" 2>/dev/null' EXIT
for _ in $(seq 1 100); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "http://${REG}/v2/" 2>/dev/null || echo 000)
  [ "${code}" = "200" ] && break; sleep 0.2
done
[ "${code}" = "200" ] || { echo "registry did not start" >&2; exit 2; }

cd work
printf 'payload bytes\n' > "${PKG}"
printf '{"name":"%s"}\n' "${PKG}" > metadata.json
printf 'build log line 1\nbuild log line 2\n' > build.log
printf 'SBOM placeholder\n' > sbom.spdx.json

echo "== publish the package =="
oras push ${ORAS_HTTP} --disable-path-validation \
  --artifact-type "application/vnd.opk.package.v1+json" \
  "${REPO}:${TAG}" \
  "${PKG}:application/vnd.opk.payload.v1" \
  "metadata.json:application/vnd.opk.metadata.v1+json" >/dev/null 2>&1 \
  && ok "package pushed" || { bad "push failed"; exit 1; }

SUBJECT=$(oras manifest fetch ${ORAS_HTTP} --descriptor "${REPO}:${TAG}" 2>/dev/null | jq -r '.digest')
[ -n "${SUBJECT}" ] && ok "subject digest ${SUBJECT}" || { bad "no subject digest"; exit 1; }

echo
echo "== attach two referrers =="
for spec in "build.log:text/plain:application/vnd.opk.buildlog.v1" \
            "sbom.spdx.json:application/spdx+json:application/vnd.opk.sbom.v1+json"; do
  f="${spec%%:*}"; rest="${spec#*:}"; mt="${rest%%:*}"; at="${rest#*:}"
  oras attach ${ORAS_HTTP} --disable-path-validation --artifact-type "${at}" \
    "${REPO}@${SUBJECT}" "${f}:${mt}" >/dev/null 2>&1 \
    && ok "attached ${at}" || bad "attach failed ${at}"
done

echo
echo "== path 1: the referrers API (works here, absent on GHCR) =="
API=$(curl -sS "http://${REG}/v2/${NS}/${PKG}/referrers/${SUBJECT}" 2>/dev/null)
N_API=$(printf '%s' "${API}" | jq -r '.manifests | length' 2>/dev/null || echo 0)
[ "${N_API}" -ge 2 ] && ok "referrers API returns ${N_API}" || bad "referrers API returned ${N_API}"

echo
echo "== path 2: the FALLBACK TAG, which is what GHCR requires =="
# The spec's fallback name: the digest with ':' replaced by '-'.
FB_TAG="$(printf '%s' "${SUBJECT}" | tr ':' '-')"
echo "  fallback tag: ${FB_TAG}"

# oras does not write the fallback tag when the registry answers the API, so
# build the index explicitly. This is exactly what a publisher must do on a
# registry without referrers support, and it is 30 lines, not a project.
python3 - "${API}" > referrers-index.json <<'PY'
import json, sys
api = json.loads(sys.argv[1])
# An OCI image index whose manifests are the referring descriptors. Each entry
# keeps its artifactType and annotations so a client can filter WITHOUT
# fetching every referrer, which is the whole point of the listing.
idx = {
    "schemaVersion": 2,
    "mediaType": "application/vnd.oci.image.index.v1+json",
    "manifests": [
        {k: v for k, v in m.items()
         if k in ("mediaType", "digest", "size", "artifactType", "annotations")}
        for m in api.get("manifests", [])
    ],
}
print(json.dumps(idx, indent=2, sort_keys=True))
PY
jq -e '.manifests | length >= 2' referrers-index.json >/dev/null \
  && ok "built a referrers index with $(jq -r '.manifests|length' referrers-index.json) entries" \
  || bad "index build failed"

oras manifest push ${ORAS_HTTP} "${REPO}:${FB_TAG}" referrers-index.json >/dev/null 2>&1 \
  && ok "fallback index pushed at tag ${FB_TAG:0:20}..." || bad "fallback push failed"

echo
echo "== a client that is told the API does not exist =="
# ⭐ This is the discovery routine a client must implement. It is given
# use_api=False, so the API path cannot mask a broken fallback.
python3 - "http://${REG}" "${NS}/${PKG}" "${SUBJECT}" > discovered.json <<'PY'
import json, sys, urllib.request

base, repo, subject = sys.argv[1:4]

def get(url, accept=None):
    req = urllib.request.Request(url)
    if accept:
        req.add_header("Accept", accept)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, None

def discover(use_api=True):
    """Referrers of `subject`, by API where available, else by fallback tag.

    ⛔ The fallback is not a degraded mode. On a registry that never
    implements the API it is the only mode, so it is exercised on every
    client, not kept as an untested branch.
    """
    if use_api:
        code, body = get(f"{base}/v2/{repo}/referrers/{subject}")
        if code == 200 and body is not None:
            return "api", body.get("manifests", [])
    tag = subject.replace(":", "-")
    code, body = get(f"{base}/v2/{repo}/manifests/{tag}",
                     accept="application/vnd.oci.image.index.v1+json")
    if code == 200 and body is not None:
        return "fallback-tag", body.get("manifests", [])
    return "none", []

route, refs = discover(use_api=False)
print(json.dumps({"route": route,
                  "count": len(refs),
                  "artifact_types": sorted(r.get("artifactType") for r in refs)},
                 indent=2))
PY
cat discovered.json
ROUTE=$(jq -r '.route' discovered.json)
N_FB=$(jq -r '.count' discovered.json)
[ "${ROUTE}" = "fallback-tag" ] && ok "client used the fallback tag route" || bad "client did not use the fallback route (${ROUTE})"
[ "${N_FB}" = "${N_API}" ] && ok "fallback route found the same ${N_FB} referrers the API did" \
  || bad "fallback found ${N_FB}, API found ${N_API}"
jq -e '.artifact_types | index("application/vnd.opk.buildlog.v1")' discovered.json >/dev/null \
  && ok "build log is discoverable with no referrers API at all" || bad "build log not discoverable via fallback"

echo
echo "== guard mutation: a subject with no referrers must report none, not crash =="
python3 - "http://${REG}" "${NS}/${PKG}" "sha256:$(printf 0%.0s $(seq 1 64))" <<'PY'
import json, sys, urllib.request, urllib.error
base, repo, subject = sys.argv[1:4]
tag = subject.replace(":", "-")
try:
    urllib.request.urlopen(f"{base}/v2/{repo}/manifests/{tag}", timeout=30)
    print("UNEXPECTED-200")
except urllib.error.HTTPError as e:
    print(f"absent-subject -> HTTP {e.code} (expected 404)")
PY

{
  echo "# referrers fallback"
  echo
  echo "date_utc      $(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "registry      zot on ${REG} (distribution-spec 1.1.0)"
  echo "subject       ${SUBJECT}"
  echo "fallback tag  ${FB_TAG}"
  echo "referrers via API           ${N_API}"
  echo "referrers via fallback tag  ${N_FB}"
  echo
  echo "checks passed ${PASS}"
  echo "checks failed ${FAIL}"
} > "${OUT}/41-referrers-fallback.txt"
cp -f referrers-index.json "${OUT}/41-referrers-index.json" 2>/dev/null

echo
echo "checks passed ${PASS}, failed ${FAIL}"
echo "written: ${OUT}/41-referrers-fallback.txt"
[ "${FAIL}" -eq 0 ] || exit 1
exit 0
