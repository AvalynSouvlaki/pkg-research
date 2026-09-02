#!/usr/bin/env bash
# 10-probe-host.sh
#
# QUESTION: what can this machine actually prove, and which gates can it pass?
#
# Every later experiment quotes numbers. A number with no host behind it cannot
# be compared to anything, so this runs first and prints the conditions the
# rest of the directory is measured under.
#
# Exit codes: 0 the probe ran, 2 it could not run.
# Read the exit code from this process, unpiped.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${HERE}/out"
mkdir -p "${OUT}" || exit 2

have() { command -v "$1" >/dev/null 2>&1; }

# Not every tool answers --version. go and oras take a bare `version`
# subcommand and exit non-zero on the flag, which would otherwise be reported
# as an error rather than as the version it is.
ver() {
  case "$1" in
    go|oras) "$1" version 2>&1 | head -1 ;;
    *)       "$1" --version 2>&1 | head -1 ;;
  esac
}

{
  echo "# host probe"
  echo
  echo "date_utc      $(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "kernel        $(uname -srm)"
  echo "os            $(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
  echo "nproc         $(nproc)"
  echo "mem_total_kb  $(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo -)"
  echo "uid           $(id -u)"
  echo "cwd_fs        $(df -PT . 2>/dev/null | awk 'NR==2{print $2" "$5" used of "$3}')"
  echo

  echo "## toolchains"
  for t in gcc clang musl-gcc go rustc cargo zig python3 node java dotnet \
           nim crystal ldc2 gdc dmd gnatmake gfortran swiftc ghc; do
    if have "$t"; then
      printf '%-12s present   %s\n' "$t" "$(ver "$t" --version | cut -c1-72)"
    else
      printf '%-12s ABSENT\n' "$t"
    fi
  done
  echo

  echo "## rust targets installed"
  if have rustup; then rustup target list --installed 2>/dev/null | sed 's/^/  /'; else echo "  (no rustup)"; fi
  echo

  echo "## supply-chain and registry tooling"
  for t in podman docker oras skopeo crane cosign syft grype minisign age b3sum zstd xz jq; do
    if have "$t"; then
      printf '%-12s present   %s\n' "$t" "$(ver "$t" --version | cut -c1-72)"
    else
      printf '%-12s ABSENT\n' "$t"
    fi
  done
  echo

  echo "## container capability"
  # A client binary with no daemon answers --version happily and then every
  # real command fails, so probe the daemon, not the binary.
  if have podman && podman info --format '{{.Version.Version}}' >/dev/null 2>&1; then
    echo "podman_daemon ok        $(podman info --format '{{.Version.Version}} rootless={{.Host.Security.Rootless}}' 2>/dev/null)"
  else
    echo "podman_daemon UNAVAILABLE"
  fi
  if have docker && docker info >/dev/null 2>&1; then
    echo "docker_daemon ok        $(docker info --format '{{.ServerVersion}}' 2>/dev/null)"
  else
    echo "docker_daemon UNAVAILABLE"
  fi
  echo "max_user_ns   $(cat /proc/sys/user/max_user_namespaces 2>/dev/null || echo -)"
  printf 'unshare_userns '
  if unshare -Ur --map-root-user true 2>/dev/null; then echo "ok"; else echo "REFUSED"; fi
  echo

  echo "## network"
  for probe in https://ghcr.io/v2/ https://raw.githubusercontent.com https://api.github.com; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 25 "$probe" 2>/dev/null || echo "000")
    printf '%-40s HTTP %s\n' "$probe" "$code"
  done
} | tee "${OUT}/10-probe-host.txt"

echo
echo "written: ${OUT}/10-probe-host.txt"
exit 0
