#!/usr/bin/env bash
# 50-mirror.sh
#
# QUESTION: can a package be mirrored to a second registry so that its
# signature still verifies there, and does a mirror that ALTERS anything get
# caught?
#
# ⭐ This is the property that makes mirroring safe: a mirror copies bytes and
# never creates them, so a client verifies a mirrored artefact against the same
# signed values it would use for the primary. The mirror is a transport, not a
# party the client trusts.
#
# ⛔ THE STEP THAT GETS MISSED: referrers on a registry without the referrers
# API live under the fallback tag `sha256-HEX`, which is not the tag of
# anything a package listing shows. A tool copying by tag does not see them,
# and the result is a mirror where every package reads as UNSIGNED.
#
# Two registries are started on loopback, so nothing here needs credentials.
#
# Exit codes: 0 the mirror is faithful and the tamper is caught, 1 an assertion
# failed, 2 could not run.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
OUT="${HERE}/out"; WORK="${HERE}/.work/mirror"
BIN="${ROOT}/.tmp/bin"; export PATH="${BIN}:${PATH}"
mkdir -p "${OUT}" "${WORK}" || exit 2
export LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=1700000000

command -v oras >/dev/null 2>&1 || { echo "oras required" >&2; exit 2; }
command -v jq   >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }
[ -x "${BIN}/zot" ] || { echo "zot required; run 00-fetch-tools.sh" >&2; exit 2; }

SRC_PORT="${SRC_PORT:-15002}"; DST_PORT="${DST_PORT:-15003}"
SRC="127.0.0.1:${SRC_PORT}"; DST="127.0.0.1:${DST_PORT}"
NS="opk"; PKG="mirrordemo"; TAG="1.0.0-1-x86_64-linux"
SRC_REPO="${SRC}/${NS}/${PKG}"; DST_REPO="${DST}/${NS}/${PKG}"
H="--plain-http"
# ⚠ `oras cp` does NOT take --plain-http. It takes a flag per side, and
# passing the wrong one fails every copy with an error that reads like a
# network problem.
CP="--from-plain-http --to-plain-http"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }
step() { printf '\n== %s ==\n' "$1"; }

cd "${WORK}" || exit 2
rm -rf src-reg dst-reg work && mkdir -p src-reg dst-reg work

start_zot() { # <port> <dir> <logfile>
  cat > "zot-$1.json" <<EOF
{ "distSpecVersion": "1.1.0",
  "storage": { "rootDirectory": "${WORK}/$2", "dedupe": false },
  "http": { "address": "127.0.0.1", "port": "$1" },
  "log": { "level": "error" } }
EOF
  "${BIN}/zot" serve "zot-$1.json" > "$3" 2>&1 &
  echo $!
}
SRC_PID=$(start_zot "${SRC_PORT}" src-reg src.log)
DST_PID=$(start_zot "${DST_PORT}" dst-reg dst.log)
trap 'kill "${SRC_PID}" "${DST_PID}" 2>/dev/null; wait 2>/dev/null' EXIT

for reg in "${SRC}" "${DST}"; do
  for _ in $(seq 1 100); do
    c=$(curl -sS -o /dev/null -w '%{http_code}' "http://${reg}/v2/" 2>/dev/null || echo 000)
    [ "$c" = "200" ] && break; sleep 0.2
  done
  [ "$c" = "200" ] || { echo "registry ${reg} did not start" >&2; exit 2; }
done
ok "two registries up: source ${SRC}, mirror ${DST}"

# ---------------------------------------------------------------- publish
step "publish a signed package to the source"
cd work
printf 'payload bytes for the mirror demo\n' > "${PKG}"
printf '{"name":"%s","version":"1.0.0"}\n' "${PKG}" > metadata.json
printf 'build log line one\nbuild log line two\n' > build.log

oras push ${H} --disable-path-validation \
  --artifact-type "application/vnd.opk.package.v1+json" \
  "${SRC_REPO}:${TAG}" \
  "${PKG}:application/vnd.opk.payload.v1" \
  "metadata.json:application/vnd.opk.metadata.v1+json" >/dev/null 2>&1 \
  && ok "package pushed" || { bad "push failed"; exit 1; }

SUBJECT=$(oras manifest fetch ${H} --descriptor "${SRC_REPO}:${TAG}" 2>/dev/null | jq -r '.digest')
[ -n "${SUBJECT}" ] || { bad "no subject digest"; exit 1; }

oras attach ${H} --disable-path-validation \
  --artifact-type "application/vnd.opk.buildlog.v1" \
  "${SRC_REPO}@${SUBJECT}" "build.log:text/plain" >/dev/null 2>&1 \
  && ok "build log attached as a referrer" || bad "attach failed"

SIGNED=no
if [ -x "${BIN}/minisign" ]; then
  rm -f mk.key mk.pub
  printf '\n\n' | "${BIN}/minisign" -G -f -s mk.key -p mk.pub >/dev/null 2>&1
  printf '%s' "${SUBJECT}" > digest.txt
  printf '\n' | "${BIN}/minisign" -S -s mk.key -m digest.txt -x digest.txt.minisig \
      -t "opk ${PKG} 1.0.0-1 x86_64-linux" >/dev/null 2>&1
  if [ -s digest.txt.minisig ]; then
    oras attach ${H} --disable-path-validation \
      --artifact-type "application/vnd.opk.signature.v1" \
      "${SRC_REPO}@${SUBJECT}" \
      "digest.txt.minisig:application/vnd.opk.signature.minisign.v1" >/dev/null 2>&1 \
      && { ok "signature over the digest attached"; SIGNED=yes; } || bad "signature attach failed"
  fi
fi
cd "${WORK}"

# The fallback index, which is what a registry without a referrers API needs.
API=$(curl -sS "http://${SRC}/v2/${NS}/${PKG}/referrers/${SUBJECT}" 2>/dev/null)
N_SRC=$(printf '%s' "${API}" | jq -r '.manifests | length' 2>/dev/null || echo 0)
python3 - "${API}" > fb.json <<'PY'
import json, sys
api = json.loads(sys.argv[1])
print(json.dumps({
    "schemaVersion": 2,
    "mediaType": "application/vnd.oci.image.index.v1+json",
    "manifests": [{k: v for k, v in m.items()
                   if k in ("mediaType", "digest", "size", "artifactType", "annotations")}
                  for m in api.get("manifests", [])],
}, indent=2, sort_keys=True))
PY
FB_TAG="$(printf '%s' "${SUBJECT}" | tr ':' '-')"
oras manifest push ${H} "${SRC_REPO}:${FB_TAG}" fb.json >/dev/null 2>&1 \
  && ok "fallback index published (${N_SRC} referrers)" || bad "fallback push failed"

# ---------------------------------------------------------------- mirror
step "mirror to the second registry"

# ⛔ Copy the package tag AND the fallback tag. A tool copying by tag alone
# never sees the second, and the mirror then reads as unsigned.
oras cp ${CP} "${SRC_REPO}:${TAG}" "${DST_REPO}:${TAG}" >/dev/null 2>&1 \
  && ok "package copied" || bad "package copy failed"

REF_FAIL=0; REF_N=0
for d in $(printf '%s' "${API}" | jq -r '.manifests[].digest'); do
  REF_N=$((REF_N+1))
  oras cp ${CP} "${SRC_REPO}@${d}" "${DST_REPO}@${d}" >/dev/null 2>&1 \
    || { REF_FAIL=$((REF_FAIL+1)); }
done
# ⛔ Assert on the count. An ok() sitting after a loop fires whether or not the
# loop did anything, which is the vacuous pass this file exists to demonstrate.
[ "${REF_N}" -gt 0 ] && [ "${REF_FAIL}" -eq 0 ] \
  && ok "all ${REF_N} referrers copied by digest" \
  || bad "${REF_FAIL} of ${REF_N} referrer copies failed"

oras cp ${CP} "${SRC_REPO}:${FB_TAG}" "${DST_REPO}:${FB_TAG}" >/dev/null 2>&1 \
  && ok "⛔ the fallback tag copied, which a tag-only copy would miss" \
  || bad "fallback tag copy failed"

# ---------------------------------------------------------------- verify
step "verify the mirror, by reading it back"

DST_SUBJECT=$(oras manifest fetch ${H} --descriptor "${DST_REPO}:${TAG}" 2>/dev/null | jq -r '.digest')
[ "${DST_SUBJECT}" = "${SUBJECT}" ] \
  && ok "the mirrored manifest digest is unchanged" \
  || bad "digest changed: ${SUBJECT} -> ${DST_SUBJECT}"

DST_FB=$(curl -sS -H "Accept: application/vnd.oci.image.index.v1+json" \
  "http://${DST}/v2/${NS}/${PKG}/manifests/${FB_TAG}" 2>/dev/null)
N_DST=$(printf '%s' "${DST_FB}" | jq -r '.manifests | length' 2>/dev/null || echo 0)
[ "${N_DST}" = "${N_SRC}" ] \
  && ok "the mirror lists the same ${N_DST} referrers" \
  || bad "referrer count differs: source ${N_SRC}, mirror ${N_DST}"

rm -rf pull && mkdir -p pull && cd pull
oras pull ${H} "${DST_REPO}@${DST_SUBJECT}" >/dev/null 2>&1
cd "${WORK}"
SRC_HASH=$(sha256sum "work/${PKG}" | cut -d' ' -f1)
DST_HASH=$(sha256sum "pull/${PKG}" 2>/dev/null | cut -d' ' -f1)
[ -n "${DST_HASH}" ] && [ "${SRC_HASH}" = "${DST_HASH}" ] \
  && ok "the payload pulled from the mirror is byte-identical" \
  || bad "payload differs"

if [ "${SIGNED}" = "yes" ]; then
  SIG_D=$(printf '%s' "${DST_FB}" | jq -r '.manifests[] | select(.artifactType=="application/vnd.opk.signature.v1") | .digest')
  rm -rf psig && mkdir -p psig && cd psig
  oras pull ${H} "${DST_REPO}@${SIG_D}" >/dev/null 2>&1
  cd "${WORK}"
  if [ -s psig/digest.txt.minisig ]; then
    ok "the signature was retrieved from the mirror"
    printf '%s' "${SUBJECT}" > vd.txt
    "${BIN}/minisign" -V -p work/mk.pub -m vd.txt -x psig/digest.txt.minisig >/dev/null 2>&1 \
      && ok "⭐ the ORIGINAL signature verifies against the MIRRORED artefact" \
      || bad "the signature did not verify after mirroring"
  else
    bad "signature missing on the mirror; the checks below would pass vacuously"
  fi
fi

# ---------------------------------------------------------------- tamper
step "guard mutation: a mirror that alters a byte must be caught"

# ⛔ Push DIFFERENT bytes to the mirror under the same tag, as a mirror that
# recompressed or rewrote content would effectively do.
cd work
printf 'payload bytes for the mirror demo TAMPERED\n' > "${PKG}"
oras push ${H} --disable-path-validation \
  --artifact-type "application/vnd.opk.package.v1+json" \
  "${DST_REPO}:${TAG}" \
  "${PKG}:application/vnd.opk.payload.v1" \
  "metadata.json:application/vnd.opk.metadata.v1+json" >/dev/null 2>&1
cd "${WORK}"

TAMPERED=$(oras manifest fetch ${H} --descriptor "${DST_REPO}:${TAG}" 2>/dev/null | jq -r '.digest')
[ "${TAMPERED}" != "${SUBJECT}" ] \
  && ok "the tampered manifest has a different digest (${TAMPERED:0:20}...)" \
  || bad "tampering did not change the digest, which cannot be right"

# ⭐ A client resolves the digest from the SIGNED INDEX, not from the tag, so
# it asks the mirror for the original digest and gets a 404 rather than
# different bytes. That is the whole protection.
CODE=$(curl -sS -o /dev/null -w '%{http_code}' \
  -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  "http://${DST}/v2/${NS}/${PKG}/manifests/${SUBJECT}" 2>/dev/null)
if [ "${CODE}" = "200" ]; then
  rm -rf pull2 && mkdir -p pull2 && cd pull2
  oras pull ${H} "${DST_REPO}@${SUBJECT}" >/dev/null 2>&1
  cd "${WORK}"
  H2=$(sha256sum "pull2/${PKG}" 2>/dev/null | cut -d' ' -f1)
  [ "${H2}" = "${SRC_HASH}" ] \
    && ok "⭐ fetching by DIGEST still returns the original bytes; the tag move is inert" \
    || bad "fetching by digest returned different bytes"
else
  ok "⭐ fetching the signed digest from the tampered mirror fails (HTTP ${CODE}), rather than returning substituted bytes"
fi

{
  echo "# mirror"
  echo
  echo "date_utc      $(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "source        ${SRC_REPO}:${TAG}"
  echo "mirror        ${DST_REPO}:${TAG}"
  echo "subject       ${SUBJECT}"
  echo "fallback tag  ${FB_TAG}"
  echo "referrers     source ${N_SRC}, mirror ${N_DST}"
  echo "signed        ${SIGNED}"
  echo
  echo "checks passed ${PASS}"
  echo "checks failed ${FAIL}"
} | tee "${OUT}/50-mirror.txt"

echo
echo "written: ${OUT}/50-mirror.txt"
[ "${FAIL}" -eq 0 ] || exit 1
exit 0
