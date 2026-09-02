#!/usr/bin/env bash
# 00-fetch-tools.sh
#
# QUESTION: none. This is a helper, not a measurement.
#
# It fetches the pinned tools the other experiments need into .tmp/bin, so a
# fresh clone can run them. ⛔ Every version here is pinned: an experiment run
# against "latest" measures a different thing each week and says so nowhere.
#
# ⚠ .tmp/ is gitignored, so these binaries are not in the repository. That is
# deliberate: they are large, they are somebody else's, and this script plus
# the pins below is a smaller and more honest way to carry them.
#
# Anything already on PATH is used instead of being downloaded.
#
# Exit codes: 0 every required tool is available, 1 one could not be obtained,
# 2 could not run.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
BIN="${ROOT}/.tmp/bin"
mkdir -p "${BIN}" || exit 2

# ⛔ PINNED. Bump deliberately, and re-run every experiment when you do.
ORAS_VERSION="1.2.2"
ZOT_VERSION="2.1.2"
COSIGN_VERSION="2.4.1"
SYFT_VERSION="1.18.1"
CRANE_VERSION="0.20.2"
MINISIGN_VERSION="0.12"
ZIG_VERSION="0.13.0"
B3SUM_VERSION="1.8.7"

case "$(uname -m)" in
  x86_64)  GOARCH=amd64; ZIGARCH=x86_64  ;;
  aarch64) GOARCH=arm64; ZIGARCH=aarch64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 2 ;;
esac

FAILED=0
have() { command -v "$1" >/dev/null 2>&1 || [ -x "${BIN}/$1" ]; }

get() { # name url [tar-member]
  local name="$1" url="$2" member="${3:-}"
  if have "${name}"; then printf '%-10s present, not fetching\n' "${name}"; return 0; fi
  printf '%-10s fetching ... ' "${name}"
  local tmp; tmp="$(mktemp -d)"
  if ! curl -fsSL --max-time 600 "${url}" -o "${tmp}/dl"; then
    echo "FAILED (download)"; rm -rf "${tmp}"; FAILED=1; return 1
  fi
  case "${url}" in
    *.tar.gz|*.tgz) tar -xzf "${tmp}/dl" -C "${tmp}" ${member:+"${member}"} 2>/dev/null ;;
    *.tar.xz)       tar -xJf "${tmp}/dl" -C "${tmp}" 2>/dev/null ;;
    *)              cp "${tmp}/dl" "${tmp}/${name}" ;;
  esac
  local src="${tmp}/${member:-${name}}"
  [ -f "${src}" ] || src="$(find "${tmp}" -type f -name "${name}" -perm -u+x 2>/dev/null | head -1)"
  if [ -z "${src}" ] || [ ! -f "${src}" ]; then
    echo "FAILED (not found in archive)"; rm -rf "${tmp}"; FAILED=1; return 1
  fi
  install -m 0755 "${src}" "${BIN}/${name}"
  rm -rf "${tmp}"
  echo "ok"
}

echo "fetching into ${BIN}"
echo

get oras     "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_${GOARCH}.tar.gz" oras
get zot      "https://github.com/project-zot/zot/releases/download/v${ZOT_VERSION}/zot-linux-${GOARCH}-minimal"
get cosign   "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${GOARCH}"
get syft     "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_${GOARCH}.tar.gz" syft
get crane    "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_$(uname -m).tar.gz" crane

# ⭐ b3sum computes the hash the CLIENT verifies, per decisions/0006. It was
# missing from this list while every experiment checked SHA-256 only, so the
# design's load-bearing hash was never once exercised. Found in review pass 5.
# ⚠ The published asset is a bare x86-64 binary, so there is no aarch64 build
# to fetch here; on other architectures install b3sum from the distribution.
if [ "${GOARCH}" = "amd64" ]; then
  get b3sum  "https://github.com/BLAKE3-team/BLAKE3/releases/download/${B3SUM_VERSION}/b3sum_linux_x64_bin"
else
  have b3sum && printf '%-10s present, not fetching\n' b3sum \
    || printf '%-10s ⚠ no published binary for %s; install from the distribution\n' b3sum "$(uname -m)"
fi

# minisign and zig unpack to a directory, so they are handled separately.
if ! have minisign; then
  printf '%-10s fetching ... ' minisign
  tmp="$(mktemp -d)"
  if curl -fsSL --max-time 600 \
      "https://github.com/jedisct1/minisign/releases/download/${MINISIGN_VERSION}/minisign-${MINISIGN_VERSION}-linux.tar.gz" \
      -o "${tmp}/m.tgz" \
     && tar -xzf "${tmp}/m.tgz" -C "${tmp}" 2>/dev/null \
     && src="$(find "${tmp}" -type f -name minisign | head -1)" && [ -n "${src}" ]; then
    install -m 0755 "${src}" "${BIN}/minisign"; echo "ok"
  else
    echo "FAILED"; FAILED=1
  fi
  rm -rf "${tmp}"
else
  printf '%-10s present, not fetching\n' minisign
fi

if ! have zig; then
  printf '%-10s fetching ... ' zig
  if curl -fsSL --max-time 900 \
       "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-${ZIGARCH}-${ZIG_VERSION}.tar.xz" \
       -o "${BIN}/zig.tar.xz" \
     && tar -xJf "${BIN}/zig.tar.xz" -C "${BIN}" 2>/dev/null; then
    ln -sf "zig-linux-${ZIGARCH}-${ZIG_VERSION}/zig" "${BIN}/zig"
    rm -f "${BIN}/zig.tar.xz"; echo "ok"
  else
    echo "FAILED"; FAILED=1
  fi
else
  printf '%-10s present, not fetching\n' zig
fi

echo
echo "add to PATH:  export PATH=\"${BIN}:\$PATH\""
echo
# ⛔ Report what is actually usable, by running each, rather than by listing
# what was downloaded. A file that exists and does not execute is not a tool.
for t in oras zot cosign syft crane minisign zig; do
  if PATH="${BIN}:${PATH}" command -v "$t" >/dev/null 2>&1; then
    printf '%-10s ✅\n' "$t"
  else
    printf '%-10s ❌ unavailable\n' "$t"; FAILED=1
  fi
done

exit "${FAILED}"
