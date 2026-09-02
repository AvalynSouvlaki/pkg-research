#!/usr/bin/env bash
# 30-oci-pipeline.sh
#
# QUESTION: does the registry layout this project specifies actually work on a
# spec-conformant registry, end to end, with no privileged access?
#
# It runs the whole lifecycle against a local zot (OCI distribution-spec
# 1.1.0) on 127.0.0.1, so nothing here needs GHCR credentials:
#
#   build -> package -> push artifact -> attach SBOM, provenance and build log
#   as REFERRERS -> sign -> discover by referrers API -> verify -> install
#   -> reproduce -> inspect provenance -> read the build log back
#
# ⭐ Every assertion is made against what came BACK OUT of the registry, not
# against what went in. A pipeline that only checks its own inputs proves that
# the script ran, not that the registry stored anything.
#
# Exit codes: 0 the whole lifecycle passed, 1 a step failed its assertion,
# 2 could not run (a required tool or the registry is missing).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
OUT="${HERE}/out"; WORK="${HERE}/.work/oci"
BIN="${ROOT}/.tmp/bin"
export PATH="${BIN}:${PATH}"
mkdir -p "${OUT}" "${WORK}" || exit 2

export LC_ALL=C LANG=C TZ=UTC
# Pinned, not taken from the clock: two runs of this script must agree.
export SOURCE_DATE_EPOCH=1700000000

REG_PORT="${REG_PORT:-15000}"
REG="127.0.0.1:${REG_PORT}"
NS="opk"                       # registry namespace this project owns
PKG="hello"
VER="1.0.0"
REV="1"
HOST_TRIPLE="x86_64-linux"
REPO="${REG}/${NS}/${PKG}"
# The local registry is plain HTTP on loopback. A real deployment is HTTPS
# and this variable is empty, which is why it is a variable and not a flag
# repeated at every call site.
ORAS_HTTP="--plain-http"
TAG="${VER}-${REV}-${HOST_TRIPLE}"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }
step() { printf '\n== %s ==\n' "$1"; }

for t in oras jq python3 sha256sum; do
  command -v "$t" >/dev/null 2>&1 || { echo "missing required tool: $t" >&2; exit 2; }
done

# ⭐ BLAKE3 is the hash the client verifies (docs/decisions/0006-two-hashes.md),
# and until review pass 5 no experiment computed one: every check here was
# SHA-256, which is the hash the REGISTRY reports. A design whose load-bearing
# hash is never exercised has an untested spine.
#
# ⚠ Degrade, do not fail: b3sum is not on every host. When it is absent the
# BLAKE3 assertions are skipped and SAID to be skipped, rather than silently
# not running.
if [ -x "${BIN}/b3sum" ]; then B3SUM="${BIN}/b3sum"
elif command -v b3sum >/dev/null 2>&1; then B3SUM="$(command -v b3sum)"
else B3SUM=""
fi
[ -x "${BIN}/zot" ] || { echo "missing ${BIN}/zot" >&2; exit 2; }

cd "${WORK}" || exit 2
rm -rf registry stage pull* dist && mkdir -p registry stage dist

# ---------------------------------------------------------------- registry
step "start a spec-conformant registry on ${REG}"
cat > zot-config.json <<EOF
{
  "distSpecVersion": "1.1.0",
  "storage": { "rootDirectory": "${WORK}/registry", "dedupe": false },
  "http": { "address": "127.0.0.1", "port": "${REG_PORT}" },
  "log": { "level": "error" }
}
EOF
"${BIN}/zot" serve zot-config.json > zot.log 2>&1 &
ZOT_PID=$!
cleanup() { kill "${ZOT_PID}" 2>/dev/null; wait "${ZOT_PID}" 2>/dev/null; }
trap cleanup EXIT

# Wait on the condition, never on a guessed duration.
for _ in $(seq 1 100); do
  code=$(curl -sS -o /dev/null -w '%{http_code}' "http://${REG}/v2/" 2>/dev/null || echo 000)
  [ "${code}" = "200" ] && break
  sleep 0.2
done
[ "${code}" = "200" ] && ok "registry answers /v2/ with 200" || { bad "registry never came up (last ${code})"; exit 1; }

# ---------------------------------------------------------------- build
step "build the payload reproducibly"
cat > hello.c <<'EOF'
#include <stdio.h>
int main(void) { printf("hello from opk\n"); return 0; }
EOF
BUILD_LOG="${WORK}/stage/build.log"
{
  echo "opk build log"
  echo "package         ${PKG} ${VER}-${REV}"
  echo "host            ${HOST_TRIPLE}"
  echo "SOURCE_DATE_EPOCH ${SOURCE_DATE_EPOCH}"
  echo "compiler        $(musl-gcc --version 2>/dev/null | head -1 || gcc --version | head -1)"
  echo "--- compile ---"
} > "${BUILD_LOG}"

CC=musl-gcc; command -v musl-gcc >/dev/null 2>&1 || CC=gcc
# -ffile-prefix-map keeps the source path out of the object, which is one of
# the two things that make an otherwise identical build differ per machine.
${CC} -O2 -static -ffile-prefix-map="${WORK}=/build" -Wl,--build-id=none \
      hello.c -o stage/"${PKG}" >> "${BUILD_LOG}" 2>&1
strip --strip-all stage/"${PKG}" >> "${BUILD_LOG}" 2>&1
echo "--- done ---" >> "${BUILD_LOG}"

[ -f "stage/${PKG}" ] && ok "binary built" || { bad "build produced nothing"; exit 1; }

python3 "${ROOT}/tools/elfprobe.py" --expect-static "stage/${PKG}" >/dev/null 2>&1 \
  && ok "binary has no PT_INTERP (runs on a host with no matching loader)" \
  || bad "binary is dynamically linked"

# ---------------------------------------------------------------- metadata
step "generate metadata and checksums"
BIN_SHA=$(sha256sum "stage/${PKG}" | cut -d' ' -f1)
BIN_SIZE=$(stat -c %s "stage/${PKG}")
if [ -n "${B3SUM}" ]; then
  BIN_B3=$("${B3SUM}" --no-names "stage/${PKG}")
else
  BIN_B3=""
fi

cat > stage/CHECKSUMS <<EOF
${BIN_SHA}  ${PKG}
EOF

python3 - "$PKG" "$VER" "$REV" "$HOST_TRIPLE" "$BIN_SHA" "$BIN_SIZE" "$BIN_B3" > stage/metadata.json <<'PY'
import json, os, sys
pkg, ver, rev, host, sha, size, b3 = sys.argv[1:8]
print(json.dumps({
    "schemaVersion": 1,
    "name": pkg,
    "version": ver,
    "revision": int(rev),
    "host": host,
    "description": "opk pipeline demonstration package",
    "license": ["MIT"],
    "provides": [pkg],
    # ⛔ Both hashes, with the prefixes the schema specifies. The client
    # verifies blake3; sha256 is what a registry independently reports.
    "artifact": dict(
        [("path", pkg), ("sha256", "sha256:" + sha), ("size", int(size))]
        + ([("blake3", "b3:" + b3)] if b3 else [])
    ),
    "source": {"kind": "inline", "epoch": int(os.environ["SOURCE_DATE_EPOCH"])},
}, indent=2, sort_keys=True))
PY
jq -e . stage/metadata.json >/dev/null && ok "metadata.json is valid JSON" || bad "metadata.json is malformed"

# ---------------------------------------------------------------- SBOM
step "generate an SBOM"
if command -v syft >/dev/null 2>&1; then
  syft scan "file:stage/${PKG}" -o spdx-json > stage/sbom.spdx.json 2>/dev/null
else
  echo '{}' > stage/sbom.spdx.json
fi
if jq -e '.spdxVersion // .SPDXID' stage/sbom.spdx.json >/dev/null 2>&1; then
  ok "SBOM generated ($(jq -r '.spdxVersion // "unknown"' stage/sbom.spdx.json))"
else
  bad "SBOM is not recognisable SPDX"
fi

# ---------------------------------------------------------------- push
step "push the package artifact"
cd stage
# ⛔ artifactType is what makes this discoverable as an opk package rather
# than as an unlabelled blob. The empty config is the OCI 1.1 artifact shape.
oras push ${ORAS_HTTP} --disable-path-validation \
  --artifact-type "application/vnd.opk.package.v1+json" \
  --annotation "org.opencontainers.image.title=${PKG}" \
  --annotation "org.opencontainers.image.version=${VER}-${REV}" \
  --annotation "dev.opk.host=${HOST_TRIPLE}" \
  --annotation "dev.opk.provides=${PKG}" \
  --annotation "org.opencontainers.image.created=$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)" \
  "${REPO}:${TAG}" \
  "${PKG}:application/vnd.opk.payload.v1" \
  "metadata.json:application/vnd.opk.metadata.v1+json" \
  "CHECKSUMS:application/vnd.opk.checksums.v1" \
  > ../push.log 2>&1
PUSH_RC=$?
cd "${WORK}"
[ "${PUSH_RC}" = "0" ] && ok "package pushed to ${REPO}:${TAG}" || { bad "push failed"; cat push.log; exit 1; }

MANIFEST=$(oras manifest fetch ${ORAS_HTTP} "${REPO}:${TAG}" 2>/dev/null)
SUBJECT_DIGEST=$(oras manifest fetch ${ORAS_HTTP} --descriptor "${REPO}:${TAG}" 2>/dev/null | jq -r '.digest')
[ -n "${SUBJECT_DIGEST}" ] && ok "manifest digest ${SUBJECT_DIGEST}" || bad "could not resolve manifest digest"

printf '%s' "${MANIFEST}" | jq -e '.artifactType == "application/vnd.opk.package.v1+json"' >/dev/null \
  && ok "artifactType survived the round trip" || bad "artifactType was not stored"
printf '%s' "${MANIFEST}" > "${OUT}/30-manifest-package.json"

# ---------------------------------------------------------------- referrers
step "attach SBOM, provenance and build log as referrers of the package"

cat > provenance.json <<EOF
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{ "name": "${PKG}", "digest": { "sha256": "${BIN_SHA}" } }],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://opk.dev/buildtypes/container/v1",
      "externalParameters": { "package": "${PKG}", "version": "${VER}-${REV}", "host": "${HOST_TRIPLE}" },
      "internalParameters": { "SOURCE_DATE_EPOCH": "${SOURCE_DATE_EPOCH}", "LC_ALL": "C", "TZ": "UTC" }
    },
    "runDetails": {
      "builder": { "id": "https://opk.dev/builders/local-experiment" },
      "metadata": { "invocationId": "30-oci-pipeline" }
    }
  }
}
EOF

# ⚠ oras stores the path it is GIVEN as org.opencontainers.image.title, and
# the puller recreates that path. Attaching "stage/build.log" therefore lands
# at "stage/build.log" on pull, not "build.log". Attach from the file's own
# directory so the title is a basename and a client can predict the name.
attach() { # <file> <mediatype> <artifacttype>
  local d b; d="$(cd "$(dirname "$1")" && pwd)"; b="$(basename "$1")"
  ( cd "${d}" && oras attach ${ORAS_HTTP} --disable-path-validation \
      --artifact-type "$3" \
      --annotation "org.opencontainers.image.created=$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y-%m-%dT%H:%M:%SZ)" \
      "${REPO}@${SUBJECT_DIGEST}" "${b}:$2" ) >/dev/null 2>&1
}
attach "stage/sbom.spdx.json" "application/spdx+json" "application/vnd.opk.sbom.v1+json"  && ok "SBOM attached"       || bad "SBOM attach failed"
attach "provenance.json"      "application/vnd.in-toto+json" "application/vnd.opk.provenance.v1+json" && ok "provenance attached" || bad "provenance attach failed"
attach "stage/build.log"      "text/plain" "application/vnd.opk.buildlog.v1"             && ok "build log attached"  || bad "build log attach failed"

# refresh_referrers: ⛔ ALWAYS re-read after an attach. A cached listing is
# how a lookup for something just attached silently finds nothing, which then
# reads as a verification failure rather than as a stale variable.
refresh_referrers() {
  REFERRERS=$(curl -sS "http://${REG}/v2/${NS}/${PKG}/referrers/${SUBJECT_DIGEST}" 2>/dev/null)
  N_REF=$(printf '%s' "${REFERRERS}" | jq -r '.manifests | length' 2>/dev/null || echo 0)
}
refresh_referrers
[ "${N_REF}" -ge 3 ] && ok "referrers API returns ${N_REF} entries" || bad "referrers API returned ${N_REF}, expected >= 3"

[ "${N_REF}" -ge 3 ] || printf '%s\n' "${REFERRERS}" >&2
for want in application/vnd.opk.sbom.v1+json application/vnd.opk.provenance.v1+json application/vnd.opk.buildlog.v1; do
  if printf '%s' "${REFERRERS}" | jq -e --arg t "${want}" '.manifests[] | select(.artifactType == $t)' >/dev/null 2>&1; then
    ok "discoverable by artifactType ${want}"
  else
    bad "not discoverable: ${want}"
  fi
done

# ---------------------------------------------------------------- sign
step "sign the package by digest"
SIGNED=no
if [ -x "${BIN}/minisign" ]; then
  rm -f opk.key opk.pub
  # Empty passphrase: this is a throwaway experiment key, never a release key.
  printf '\n\n' | "${BIN}/minisign" -G -f -s opk.key -p opk.pub >/dev/null 2>&1
  # ⭐ The signature covers the DIGEST, not the tag. A tag can be moved; a
  # digest cannot.
  printf '%s' "${SUBJECT_DIGEST}" > digest.txt
  printf '\n' | "${BIN}/minisign" -S -s opk.key -m digest.txt -x digest.txt.minisig \
      -c "opk package signature" -t "opk ${PKG} ${VER}-${REV} ${HOST_TRIPLE}" >/dev/null 2>&1
  if [ -f digest.txt.minisig ]; then
    if attach "digest.txt.minisig" "application/vnd.opk.signature.minisign.v1" "application/vnd.opk.signature.v1"; then
      ok "minisign signature over the digest attached as a referrer"
      refresh_referrers
      SIGNED=yes
    else
      bad "signature attach failed"
    fi
  else
    bad "minisign produced no signature"
  fi
else
  echo "  (minisign absent; signature step skipped, NOT passed)"
fi

# ---------------------------------------------------------------- verify+install
step "verify and install from the registry, as a client would"
rm -rf pull && mkdir -p pull && cd pull
oras pull ${ORAS_HTTP} "${REPO}@${SUBJECT_DIGEST}" >/dev/null 2>&1 \
  && ok "pulled by immutable digest" || bad "pull by digest failed"
cd "${WORK}"

# ⛔ Assert against what came back, not against what was pushed.
GOT_SHA=$(sha256sum "pull/${PKG}" | cut -d' ' -f1)
[ "${GOT_SHA}" = "${BIN_SHA}" ] && ok "payload sha256 matches the metadata" \
  || bad "payload hash mismatch: want ${BIN_SHA} got ${GOT_SHA}"

META_SHA=$(jq -r '.artifact.sha256' pull/metadata.json)
[ "${META_SHA}" = "sha256:${GOT_SHA}" ] && ok "metadata.json agrees with the payload it describes" \
  || bad "metadata records ${META_SHA} but payload hashes sha256:${GOT_SHA}"

# ⭐ THE hash the specification says a client verifies.
if [ -n "${B3SUM}" ]; then
  GOT_B3=$("${B3SUM}" --no-names "pull/${PKG}")
  META_B3=$(jq -r '.artifact.blake3 // ""' pull/metadata.json)
  [ -n "${META_B3}" ] && ok "metadata carries a blake3 payload hash" \
    || bad "metadata has no blake3 field; the client would have nothing to verify"
  [ "${META_B3}" = "b3:${GOT_B3}" ] && ok "⭐ payload BLAKE3 matches the metadata (the hash the client verifies)" \
    || bad "blake3 mismatch: metadata ${META_B3}, payload b3:${GOT_B3}"
  # ⛔ The guard must be able to fail. A tampered byte must break it.
  cp "pull/${PKG}" tamper.bin && printf '\x00' >> tamper.bin
  TAMPER_B3=$("${B3SUM}" --no-names tamper.bin)
  [ "${TAMPER_B3}" != "${GOT_B3}" ] && ok "a modified payload produces a different BLAKE3" \
    || bad "blake3 did not change on a modified payload; the check is vacuous"
  rm -f tamper.bin
else
  printf '  ⚠  b3sum absent: BLAKE3 assertions SKIPPED (run 00-fetch-tools.sh)\n'
fi

if [ "${SIGNED}" = "yes" ]; then
  SIG_DIGEST=$(printf '%s' "${REFERRERS}" | jq -r '.manifests[] | select(.artifactType=="application/vnd.opk.signature.v1") | .digest')
  rm -rf pullsig && mkdir -p pullsig && cd pullsig
  oras pull ${ORAS_HTTP} "${REPO}@${SIG_DIGEST}" >/dev/null 2>&1
  cd "${WORK}"
  # ⛔ Prove the guard can run before believing what it says. A minisign
  # verify against a MISSING signature also exits non-zero, so without this
  # the tamper check below would "pass" having tested nothing.
  if [ -s pullsig/digest.txt.minisig ]; then
    ok "signature artefact retrieved from the registry"
  else
    bad "signature artefact missing; the checks below would pass vacuously"
  fi
  printf '%s' "${SUBJECT_DIGEST}" > verify-digest.txt
  if "${BIN}/minisign" -V -p opk.pub -m verify-digest.txt -x pullsig/digest.txt.minisig >/dev/null 2>&1; then
    ok "signature over the digest verifies with the published public key"
  else
    bad "signature did not verify"
  fi
  # Guard mutation: a tampered digest MUST fail.
  printf '%s' "sha256:0000000000000000000000000000000000000000000000000000000000000000" > tampered.txt
  if [ -s pullsig/digest.txt.minisig ]; then
    if "${BIN}/minisign" -V -p opk.pub -m tampered.txt -x pullsig/digest.txt.minisig >/dev/null 2>&1; then
      bad "GUARD IS THEATRE: signature verified against a tampered digest"
    else
      ok "guard mutation: a tampered digest is refused by a signature that DOES verify the real one"
    fi
  fi
fi

chmod +x "pull/${PKG}"
INSTALL_PREFIX="${WORK}/opt/opk"
mkdir -p "${INSTALL_PREFIX}/pkg/${PKG}/${VER}-${REV}" "${INSTALL_PREFIX}/bin"
cp -f "pull/${PKG}" "${INSTALL_PREFIX}/pkg/${PKG}/${VER}-${REV}/${PKG}"
ln -sfn "../pkg/${PKG}/${VER}-${REV}/${PKG}" "${INSTALL_PREFIX}/bin/${PKG}"
OUTPUT=$("${INSTALL_PREFIX}/bin/${PKG}" 2>/dev/null)
[ "${OUTPUT}" = "hello from opk" ] && ok "installed binary runs from the symlink farm" \
  || bad "installed binary printed '${OUTPUT}'"

# ---------------------------------------------------------------- reproduce
step "reproduce the build and compare bytes"
mkdir -p rebuild
${CC} -O2 -static -ffile-prefix-map="${WORK}=/build" -Wl,--build-id=none \
      hello.c -o rebuild/"${PKG}" 2>/dev/null
strip --strip-all rebuild/"${PKG}" 2>/dev/null
RE_SHA=$(sha256sum "rebuild/${PKG}" | cut -d' ' -f1)
[ "${RE_SHA}" = "${BIN_SHA}" ] && ok "rebuild is byte-identical (${RE_SHA:0:16}...)" \
  || bad "rebuild differs: ${BIN_SHA:0:16}... vs ${RE_SHA:0:16}..."

# ---------------------------------------------------------------- provenance + logs
step "inspect provenance and retrieve the build log, by referrer"
PROV_DIGEST=$(printf '%s' "${REFERRERS}" | jq -r '.manifests[] | select(.artifactType=="application/vnd.opk.provenance.v1+json") | .digest')
LOG_DIGEST=$(printf '%s' "${REFERRERS}" | jq -r '.manifests[] | select(.artifactType=="application/vnd.opk.buildlog.v1") | .digest')

rm -rf pullprov && mkdir -p pullprov && cd pullprov && oras pull ${ORAS_HTTP} "${REPO}@${PROV_DIGEST}" >/dev/null 2>&1; cd "${WORK}"
PROV_SUBJECT=$(jq -r '.subject[0].digest.sha256' pullprov/provenance.json 2>/dev/null)
[ "${PROV_SUBJECT}" = "${BIN_SHA}" ] && ok "provenance names the artifact it actually describes" \
  || bad "provenance subject ${PROV_SUBJECT} does not match payload ${BIN_SHA}"
jq -e '.predicate.buildDefinition.internalParameters.SOURCE_DATE_EPOCH' pullprov/provenance.json >/dev/null 2>&1 \
  && ok "provenance records the epoch a rebuild needs" || bad "provenance omits SOURCE_DATE_EPOCH"

rm -rf pulllog && mkdir -p pulllog && cd pulllog && oras pull ${ORAS_HTTP} "${REPO}@${LOG_DIGEST}" >/dev/null 2>&1; cd "${WORK}"
[ -s pulllog/build.log ] && ok "build log retrieved from the registry ($(wc -l < pulllog/build.log) lines)" \
  || bad "build log could not be retrieved"

# ---------------------------------------------------------------- failed build
step "a failed build must publish its log and NOT its artifact"
FAILREPO="${REG}/${NS}/brokenpkg"
cat > broken.c <<'EOF'
int main(void) { this_function_does_not_exist(); }
EOF
mkdir -p faillog
${CC} -O2 -static broken.c -o faillog/brokenpkg > faillog/build.log 2>&1
BUILD_RC=$?
[ "${BUILD_RC}" != "0" ] && ok "the broken build failed, as intended (rc=${BUILD_RC})" \
  || bad "the broken build unexpectedly succeeded"
rm -f faillog/brokenpkg
cd faillog
oras push ${ORAS_HTTP} --disable-path-validation \
  --artifact-type "application/vnd.opk.buildfailure.v1+json" \
  --annotation "dev.opk.build.status=failed" \
  "${FAILREPO}:${TAG}" "build.log:text/plain" >/dev/null 2>&1
cd "${WORK}"
FAILMAN=$(oras manifest fetch ${ORAS_HTTP} "${FAILREPO}:${TAG}" 2>/dev/null)
printf '%s' "${FAILMAN}" | jq -e '.artifactType == "application/vnd.opk.buildfailure.v1+json"' >/dev/null \
  && ok "failure is published under a distinct artifactType a client will not install" \
  || bad "failure record not stored correctly"
printf '%s' "${FAILMAN}" | jq -e '[.layers[].mediaType] | index("application/vnd.opk.payload.v1") == null' >/dev/null \
  && ok "failure record carries no payload layer" || bad "failure record carries a payload"

# ---------------------------------------------------------------- report
step "summary"
{
  echo "# oci pipeline"
  echo
  echo "date_utc   $(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "registry   zot $(${BIN}/zot --version 2>&1 | jq -r '."distribution-spec" // "?"' 2>/dev/null || echo '?') on ${REG}"
  echo "oras       $(oras version 2>/dev/null | awk '/^Version/{print $2}')"
  echo "subject    ${REPO}:${TAG}"
  echo "digest     ${SUBJECT_DIGEST}"
  echo "payload    sha256:${BIN_SHA} (${BIN_SIZE} bytes)"
  echo "referrers  ${N_REF}"
  echo
  echo "checks passed ${PASS}"
  echo "checks failed ${FAIL}"
} | tee "${OUT}/30-oci-pipeline.txt"

echo
printf '%s' "${REFERRERS}" > "${OUT}/30-referrers.json"
echo "artifacts: ${OUT}/30-manifest-package.json ${OUT}/30-referrers.json"
[ "${FAIL}" -eq 0 ] || exit 1
exit 0
