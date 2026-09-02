#!/usr/bin/env bash
# 20-static-matrix.sh
#
# QUESTION: for each toolchain available here, does the documented "build a
# static binary" recipe actually produce a binary with no PT_INTERP, how big
# is it, and does it run?
#
# ⭐ Every row is checked with tools/elfprobe.py, which reads the artifact
# rather than asking the compiler. A toolchain claiming a static build and
# emitting a PT_INTERP is exactly the failure this table exists to catch, and
# it has happened here: see the `go` CGO row.
#
# ⚠ ABSENT is not a result about the language. It means this host has no such
# toolchain, and the docs say so rather than inferring anything from it.
#
# Inputs are pinned by whatever the host has; 10-probe-host.sh records the
# versions this ran against.
#
# Exit codes: 0 the matrix ran, 1 a toolchain present here failed its own
# recipe, 2 could not run.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${HERE}/out"; WORK="${HERE}/.work/static-matrix"
PROBE="${HERE}/../tools/elfprobe.py"
mkdir -p "${OUT}" "${WORK}" || exit 2
# Tools fetched by 00-fetch-tools.sh live here. Anything already on PATH
# wins, so a host with its own zig or oras uses that.
PATH="${PATH}:$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.tmp/bin"
export PATH

[ -f "${PROBE}" ] || { echo "missing ${PROBE}" >&2; exit 2; }

# Normalise everything that leaks a machine or a clock into an artifact.
export LC_ALL=C LANG=C TZ=UTC
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

ROWS="${WORK}/rows.tsv"; : > "${ROWS}"
FAILED=0

have() { command -v "$1" >/dev/null 2>&1; }

# row <lang> <recipe> <artifact> <run-output-or-->
row() {
  local lang="$1" recipe="$2" art="$3" ran="$4"
  if [ ! -f "${art}" ]; then
    printf '%s\t%s\tBUILD-FAILED\t-\t-\t-\t-\n' "${lang}" "${recipe}" >> "${ROWS}"
    FAILED=1; return
  fi
  local j
  j=$(python3 "${PROBE}" --json "${art}") || { FAILED=1; return; }
  local bytes interp arch bid
  bytes=$(printf '%s' "$j" | jq -r '.bytes')
  interp=$(printf '%s' "$j" | jq -r '.interp // "-"')
  arch=$(printf '%s' "$j" | jq -r '.machine')
  bid=$(printf '%s' "$j" | jq -r 'if .build_id then "yes" else "no" end')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${lang}" "${recipe}" "${bytes}" "${arch}" "${interp}" "${bid}" "${ran}" >> "${ROWS}"
  [ "${interp}" = "-" ] || FAILED=1
}

skip() { printf '%s\t%s\tABSENT\t-\t-\t-\t-\n' "$1" "$2" >> "${ROWS}"; }

cd "${WORK}" || exit 2

# ---------------------------------------------------------------- C
cat > hello.c <<'EOF'
#include <stdio.h>
int main(void) { printf("ok\n"); return 0; }
EOF

if have gcc; then
  gcc -O2 -static hello.c -o c-gcc-glibc 2>/dev/null
  row "C" "gcc -static (glibc)" c-gcc-glibc "$(./c-gcc-glibc 2>/dev/null || echo '-')"
  gcc -O2 -static-pie -fPIE hello.c -o c-gcc-staticpie 2>/dev/null
  row "C" "gcc -static-pie (glibc)" c-gcc-staticpie "$(./c-gcc-staticpie 2>/dev/null || echo '-')"
else skip "C" "gcc -static"; fi

if have musl-gcc; then
  musl-gcc -O2 -static hello.c -o c-musl 2>/dev/null
  row "C" "musl-gcc -static" c-musl "$(./c-musl 2>/dev/null || echo '-')"
  musl-gcc -O2 -static hello.c -o c-musl-stripped 2>/dev/null && strip --strip-all c-musl-stripped 2>/dev/null
  row "C" "musl-gcc -static, stripped" c-musl-stripped "$(./c-musl-stripped 2>/dev/null || echo '-')"
else skip "C" "musl-gcc -static"; fi

if have clang; then
  clang -O2 -static hello.c -o c-clang 2>/dev/null
  row "C" "clang -static (glibc)" c-clang "$(./c-clang 2>/dev/null || echo '-')"
else skip "C" "clang -static"; fi

# ---------------------------------------------------------------- C++
cat > hello.cpp <<'EOF'
#include <iostream>
#include <string>
int main() { std::string s = "ok"; std::cout << s << std::endl; return 0; }
EOF
if have g++; then
  g++ -O2 -static -static-libstdc++ -static-libgcc hello.cpp -o cpp-gcc 2>/dev/null
  row "C++" "g++ -static -static-libstdc++" cpp-gcc "$(./cpp-gcc 2>/dev/null || echo '-')"
else skip "C++" "g++ -static"; fi

# ---------------------------------------------------------------- Rust
if have cargo && rustup target list --installed 2>/dev/null | grep -q x86_64-unknown-linux-musl; then
  rm -rf rs && cargo new --quiet --bin rs >/dev/null 2>&1
  ( cd rs && RUSTFLAGS="-C target-feature=+crt-static" \
      cargo build --quiet --release --target x86_64-unknown-linux-musl >/dev/null 2>&1 )
  cp -f rs/target/x86_64-unknown-linux-musl/release/rs rust-musl 2>/dev/null
  row "Rust" "cargo --target *-musl, crt-static" rust-musl "$(./rust-musl 2>/dev/null || echo '-')"

  # The gnu target with crt-static: supported, and the reason it is not the
  # default recommendation is measured here rather than asserted.
  ( cd rs && RUSTFLAGS="-C target-feature=+crt-static" \
      cargo build --quiet --release --target x86_64-unknown-linux-gnu >/dev/null 2>&1 )
  cp -f rs/target/x86_64-unknown-linux-gnu/release/rs rust-gnu-static 2>/dev/null
  row "Rust" "cargo --target *-gnu, crt-static" rust-gnu-static "$(./rust-gnu-static 2>/dev/null || echo '-')"
else skip "Rust" "cargo --target *-musl"; fi

# ---------------------------------------------------------------- Go
if have go; then
  rm -rf gopkg && mkdir gopkg && cd gopkg
  cat > main.go <<'EOF'
package main

import "fmt"

func main() { fmt.Println("ok") }
EOF
  go mod init example.test >/dev/null 2>&1
  CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -buildid=" -o ../go-nocgo . 2>/dev/null
  cd "${WORK}"
  row "Go" "CGO_ENABLED=0 -trimpath -ldflags=-s -w" go-nocgo "$(./go-nocgo 2>/dev/null || echo '-')"

  # ⚠ The trap this row exists to show. net and os/user pull in cgo
  # resolvers, and with CGO_ENABLED=1 the result is a DYNAMIC binary even
  # though nothing in the source says so.
  rm -rf gocgo && mkdir gocgo && cd gocgo
  cat > main.go <<'EOF'
package main

import (
	"fmt"
	"net"
)

func main() {
	_, _ = net.LookupHost("localhost")
	fmt.Println("ok")
}
EOF
  go mod init example.cgo >/dev/null 2>&1
  CGO_ENABLED=1 go build -o ../go-cgo-net . 2>/dev/null
  cd "${WORK}"
  if [ -f go-cgo-net ]; then
    j=$(python3 "${PROBE}" --json go-cgo-net)
    b=$(printf '%s' "$j" | jq -r '.bytes'); i=$(printf '%s' "$j" | jq -r '.interp // "-"')
    a=$(printf '%s' "$j" | jq -r '.machine'); d=$(printf '%s' "$j" | jq -r 'if .build_id then "yes" else "no" end')
    # This row is EXPECTED to be dynamic, so it does not set FAILED.
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "Go" "CGO_ENABLED=1 + net (EXPECTED DYNAMIC)" "$b" "$a" "$i" "$d" \
      "$(./go-cgo-net 2>/dev/null || echo '-')" >> "${ROWS}"
  fi

  # And the fix: same source, cgo off.
  cd gocgo && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -buildid=" -o ../go-nocgo-net . 2>/dev/null
  cd "${WORK}"
  row "Go" "CGO_ENABLED=0 + net (the fix)" go-nocgo-net "$(./go-nocgo-net 2>/dev/null || echo '-')"
else skip "Go" "CGO_ENABLED=0"; fi

# ---------------------------------------------------------------- Zig
if have zig; then
  cat > hello.zig <<'EOF'
const std = @import("std");
pub fn main() !void {
    try std.io.getStdOut().writer().print("ok\n", .{});
}
EOF
  zig build-exe hello.zig -O ReleaseSmall -target x86_64-linux-musl \
      -femit-bin=zig-musl >/dev/null 2>&1
  row "Zig" "zig build-exe -target x86_64-linux-musl" zig-musl "$(./zig-musl 2>/dev/null || echo '-')"

  # zig cc as a C cross toolchain, which is the reason zig is in this project
  # even for projects with no zig source.
  zig cc -O2 -target x86_64-linux-musl hello.c -o zigcc-musl >/dev/null 2>&1
  row "C via zig" "zig cc -target x86_64-linux-musl" zigcc-musl "$(./zigcc-musl 2>/dev/null || echo '-')"
else skip "Zig" "zig build-exe -target *-musl"; fi

# ---------------------------------------------------------------- Fortran
if have gfortran; then
  cat > hello.f90 <<'EOF'
program hello
  print *, "ok"
end program hello
EOF
  gfortran -O2 -static hello.f90 -o fortran-static 2>/dev/null
  row "Fortran" "gfortran -static" fortran-static "$(./fortran-static 2>/dev/null | tr -d ' ' || echo '-')"
else skip "Fortran" "gfortran -static"; fi

# ---------------------------------------------------------------- Ada
if have gnatmake; then
  cat > hello.adb <<'EOF'
with Ada.Text_IO;
procedure Hello is
begin
   Ada.Text_IO.Put_Line ("ok");
end Hello;
EOF
  gnatmake -O2 hello.adb -bargs -static -largs -static >/dev/null 2>&1
  row "Ada" "gnatmake -largs -static" hello "$(./hello 2>/dev/null || echo '-')"
  mv -f hello ada-static 2>/dev/null
else skip "Ada" "gnatmake -largs -static"; fi

# ---------------------------------------------------------------- D
#
# ⛔ NEGATIVE RESULT, kept on purpose. `gdc -static` against glibc does not
# link here, and the reason is not a missing package:
#
#   libgphobos.a(elf.o): undefined reference to `__tls_get_addr'
#
# libgphobos resolves TLS ranges through the dynamic loader's
# `__tls_get_addr`, which a fully static link does not provide. The same link
# also warns that `dlopen` and `gethostbyname` in a static binary need the
# shared glibc it was linked against, which is the glibc-static NSS problem
# in another costume.
#
# The recommendation for D is therefore LDC against musl, not gdc against
# glibc. 21-container-langs.sh measures that; this row records why the
# obvious recipe is not the recommended one, so nobody re-derives it.
if have gdc; then
  cat > hello.d <<'EOF'
import std.stdio;
void main() { writeln("ok"); }
EOF
  gdc -O2 -static hello.d -o d-gdc-static 2>/dev/null
  if [ -f d-gdc-static ]; then
    row "D" "gdc -static (glibc)" d-gdc-static "$(./d-gdc-static 2>/dev/null || echo '-')"
  else
    # Expected: does not link. Recorded, and does not fail the experiment.
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "D" "gdc -static glibc (EXPECTED LINK FAILURE)" "-" "-" \
      "undefined __tls_get_addr" "-" "-" >> "${ROWS}"
  fi
else skip "D" "gdc -static"; fi

# ---------------------------------------------------------------- report
{
  echo "# static linkage matrix"
  echo
  echo "host      $(uname -srm)"
  echo "date_utc  $(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "epoch     SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}"
  echo "probe     tools/elfprobe.py (reads the artifact, not the compiler)"
  echo
  printf '%-11s | %-40s | %10s | %-8s | %-34s | %-8s | %s\n' \
    LANG RECIPE BYTES ARCH PT_INTERP BUILD-ID RUNS
  printf -- '------------|------------------------------------------|------------|----------|------------------------------------|----------|------\n'
  while IFS=$'\t' read -r l r b a i d o; do
    printf '%-11s | %-40s | %10s | %-8s | %-34s | %-8s | %s\n' "$l" "$r" "$b" "$a" "$i" "$d" "$o"
  done < "${ROWS}"
  echo
  echo "PT_INTERP '-' means no dynamic loader is named: the binary runs on a"
  echo "host that supplies none. Any other value is the exact path the host"
  echo "must provide."
} | tee "${OUT}/20-static-matrix.txt"

echo
echo "written: ${OUT}/20-static-matrix.txt"
exit "${FAILED}"
