#!/usr/bin/env bash
# 40-registry-conformance.sh
#
# QUESTION: which parts of OCI distribution-spec 1.1 does a given registry
# actually implement, and specifically does it answer the REFERRERS API?
#
# ⭐ This decides an architecture, not a detail. If the referrers API is
# absent, signatures, SBOMs, provenance and build logs cannot be discovered by
# asking the registry what refers to a package, and the fallback tag scheme in
# the distribution spec has to carry that job instead.
#
# ⛔ A 404 IS EVIDENCE ONLY BESIDE A CONTROL. A referrers 404 means "not
# implemented" only once the same digest has been shown to resolve as a
# manifest on the same registry in the same run. Without that control it
# equally means the digest was wrong, so this script always runs both.
#
# Usage:
#   40-registry-conformance.sh                      probe GHCR (anonymous)
#   40-registry-conformance.sh REPO REFERENCE       probe another public repo
#
# Exit codes: 0 the probe ran and its controls held, 1 a control failed so the
# result means nothing, 2 could not run.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${HERE}/out"; mkdir -p "${OUT}" || exit 2
# Tools fetched by 00-fetch-tools.sh live here. Anything already on PATH
# wins, so a host with its own zig or oras uses that.
PATH="${PATH}:$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.tmp/bin"
export PATH

WORK="$(mktemp -d)"; trap 'rm -rf "${WORK}"' EXIT

REGISTRY="${REGISTRY:-ghcr.io}"
# A public repository that is known to exist, so an anonymous probe has
# something real to ask about. Pinned by tag on purpose: the tag is part of
# the evidence and a moved tag would be visible as a changed digest.
REPO="${1:-pkgforge/bincache/b3sum/official/b3sum}"
REFERENCE="${2:-HEAD-c54ee7e-251030T105114-x86_64-linux}"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }

say() { printf '%s\n' "$1"; }
CONTROL_OK=1

{
  echo "# registry conformance probe"
  echo
  echo "date_utc  $(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "registry  ${REGISTRY}"
  echo "repo      ${REPO}"
  echo "reference ${REFERENCE}"
  echo

  # ---- 0. base endpoint and advertised version
  echo "## /v2/ base endpoint"
  curl -sS --max-time 30 -D "${WORK}/base.hdr" -o /dev/null "https://${REGISTRY}/v2/" 2>/dev/null
  BASE_CODE=$(awk '/^HTTP\//{c=$2} END{print c}' "${WORK}/base.hdr" 2>/dev/null)
  echo "status                       ${BASE_CODE:-none}   (401 is normal: it means auth is required, not that it is down)"
  echo "docker-distribution-api-version $(grep -i '^docker-distribution-api-version' "${WORK}/base.hdr" 2>/dev/null | tr -d '\r' | awk '{print $2}' || echo '(absent)')"
  echo "oci-subject header support   $(grep -ci '^oci-subject' "${WORK}/base.hdr" 2>/dev/null || echo 0) (only meaningful on a push response)"
  echo

  # ---- 1. token
  TOKEN=$(curl -sS --max-time 60 \
    "https://${REGISTRY}/token?scope=repository:${REPO}:pull&service=${REGISTRY}" 2>/dev/null \
    | jq -r '.token // .access_token // empty')
  if [ -z "${TOKEN}" ]; then
    echo "## FATAL: no anonymous pull token for ${REPO}"
    CONTROL_OK=0
  fi
  AUTH=(-H "Authorization: Bearer ${TOKEN}")

  # ---- 2. CONTROL A: resolve the tag, and check our digest against the
  #        registry's own Docker-Content-Digest rather than trusting ours.
  echo "## control A: tag resolves, and the digest we compute is the digest it reports"
  MCODE=$(curl -sS --max-time 60 "${AUTH[@]}" -D "${WORK}/m.hdr" -o "${WORK}/m.json" \
    -H "Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.v2+json" \
    -w '%{http_code}' "https://${REGISTRY}/v2/${REPO}/manifests/${REFERENCE}" 2>/dev/null)
  SRV_DIGEST=$(grep -i '^docker-content-digest' "${WORK}/m.hdr" 2>/dev/null | tr -d '\r' | awk '{print $2}')
  OUR_DIGEST="sha256:$(sha256sum "${WORK}/m.json" | cut -d' ' -f1)"
  echo "GET manifests/TAG            HTTP ${MCODE}"
  echo "registry Docker-Content-Digest ${SRV_DIGEST:-（absent）}"
  echo "digest we computed             ${OUR_DIGEST}"
  if [ "${MCODE}" = "200" ] && [ "${SRV_DIGEST}" = "${OUR_DIGEST}" ]; then
    echo "control A                    HELD"
  else
    echo "control A                    FAILED - every result below is uninterpretable"
    CONTROL_OK=0
  fi
  echo

  # ---- 3. CONTROL B: the same digest resolves as a manifest.
  echo "## control B: that digest is addressable as a manifest"
  DCODE=$(curl -sS --max-time 60 "${AUTH[@]}" -o /dev/null -w '%{http_code}' \
    -H "Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.oci.image.index.v1+json" \
    "https://${REGISTRY}/v2/${REPO}/manifests/${SRV_DIGEST}" 2>/dev/null)
  echo "GET manifests/DIGEST         HTTP ${DCODE}"
  if [ "${DCODE}" = "200" ]; then echo "control B                    HELD"; else echo "control B                    FAILED"; CONTROL_OK=0; fi
  echo

  # ---- 4. THE TEST: referrers for that proven-real digest.
  echo "## test: the referrers API, on a digest both controls just proved real"
  RCODE=$(curl -sS --max-time 60 "${AUTH[@]}" -o "${WORK}/ref.json" -w '%{http_code}' \
    "https://${REGISTRY}/v2/${REPO}/referrers/${SRV_DIGEST}" 2>/dev/null)
  echo "GET referrers/DIGEST         HTTP ${RCODE}"
  echo "body                         $(head -c 200 "${WORK}/ref.json" 2>/dev/null | tr -d '\n')"
  case "${RCODE}" in
    200) echo "VERDICT                      referrers API IMPLEMENTED"
         echo "entries                      $(jq -r '.manifests | length' "${WORK}/ref.json" 2>/dev/null || echo '?')" ;;
    404) echo "VERDICT                      referrers API NOT IMPLEMENTED on this registry" ;;
    401|403) echo "VERDICT                      INCONCLUSIVE - refused before it could answer" ;;
    *)   echo "VERDICT                      INCONCLUSIVE - unexpected status" ;;
  esac
  echo

  # ---- 5. the fallback the spec defines when referrers is absent.
  echo "## fallback tag scheme (distribution-spec: referrers may be an index at tag sha256-HEX)"
  FALLBACK_TAG="$(printf '%s' "${SRV_DIGEST}" | tr ':' '-')"
  FCODE=$(curl -sS --max-time 60 "${AUTH[@]}" -o "${WORK}/fb.json" -w '%{http_code}' \
    -H "Accept: application/vnd.oci.image.index.v1+json" \
    "https://${REGISTRY}/v2/${REPO}/manifests/${FALLBACK_TAG}" 2>/dev/null)
  echo "GET manifests/${FALLBACK_TAG:0:26}...  HTTP ${FCODE}"
  if [ "${FCODE}" = "200" ]; then
    echo "fallback index present       yes ($(jq -r '.manifests | length' "${WORK}/fb.json" 2>/dev/null) entries)"
  else
    echo "fallback index present       no - this repository publishes no referrers by either route"
  fi
  echo

  # ---- 6. what the manifest itself looks like, since the shape is the design.
  echo "## the manifest this repository actually publishes"
  jq '{mediaType, artifactType, config: .config.mediaType, layers: (.layers | length),
       layer_mediatypes: ([.layers[].mediaType] | unique),
       titles: [.layers[].annotations["org.opencontainers.image.title"]]}' \
     "${WORK}/m.json" 2>/dev/null || head -c 400 "${WORK}/m.json"
} | tee "${OUT}/40-registry-conformance.txt"

echo
echo "written: ${OUT}/40-registry-conformance.txt"
[ "${CONTROL_OK}" = "1" ] || exit 1
exit 0
