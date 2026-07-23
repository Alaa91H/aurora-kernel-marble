#!/usr/bin/env bash
#
# scripts/toolchain.sh — set up the Clang/LLD toolchain for kernel builds
#
# Strategy: prefer the system clang installed via apt (most reliable), then
# fall back to a Proton-Clang download if one is explicitly requested.
# Ubuntu 22.04 ships clang-14 in the default repos; we install clang-15+17
# via the LLVM apt source for better kernel 6.18 support.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TC_DIR="${TC_DIR:-$ROOT/toolchains}"
PROTON_DIR="$TC_DIR/proton-clang"

log()  { printf "\033[1;34m[tc]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; }

mkdir -p "$TC_DIR"

# ---------------------------------------------------------------------------
# 1. Prefer a modern system clang (most reliable, no URL 404s)
# ---------------------------------------------------------------------------
CLANG_CANDIDATES=(clang-18 clang-17 clang-16 clang-15 clang-14 clang)
SYSTEM_CLANG=""
for c in "${CLANG_CANDIDATES[@]}"; do
  if command -v "$c" >/dev/null 2>&1; then
    SYSTEM_CLANG="$c"
    break
  fi
done

if [[ -n "$SYSTEM_CLANG" ]]; then
  log "using system clang: $SYSTEM_CLANG ($("$SYSTEM_CLANG" --version | head -1))"

  # resolve the bin dir so build scripts can use $TC_BIN/clang
  CLANG_REAL="$(readlink -f "$(command -v "$SYSTEM_CLANG")")"
  TC_BIN="$(dirname "$CLANG_REAL")"

  # ensure lld is available; if not, install it
  if ! command -v ld.lld >/dev/null 2>&1; then
    log "ld.lld not found; installing lld"
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get install -y lld || true
    fi
  fi

  # write a toolchain pointer file consumed by build scripts
  cat > "$TC_DIR/toolchain.env" <<EOF
TC_BIN=$TC_BIN
CC=$SYSTEM_CLANG
LD=ld.lld
EOF

  ok "toolchain ready (system clang: $SYSTEM_CLANG)"
  "$SYSTEM_CLANG" --version | head -1
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Fall back to Proton-Clang download (if explicitly requested)
# ---------------------------------------------------------------------------
if [[ "${USE_PROTON:-0}" == "1" ]]; then
  log "USE_PROTON=1: downloading Proton-Clang"
  URL="${PROTON_CLANG_URL:-https://github.com/kdrag0n/proton-clang/releases/download/20210522/proton-clang.tar.gz}"

  TARBALL="$TC_DIR/proton-clang.tar.gz"
  if ! curl -fL --retry 2 -o "$TARBALL" "$URL"; then
    err "Proton-Clang download failed (URL may be stale)"
    err "fix: install system clang instead (apt install clang lld)"
    exit 1
  fi

  mkdir -p "$PROTON_DIR"
  tar -xzf "$TARBALL" -C "$PROTON_DIR"
  rm -f "$TARBALL"

  cat > "$TC_DIR/toolchain.env" <<EOF
TC_BIN=$PROTON_DIR/bin
CC=clang
LD=ld.lld
EOF

  ok "Proton-Clang installed"
  "$PROTON_DIR/bin/clang" --version | head -1
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Last resort: try to install clang via apt
# ---------------------------------------------------------------------------
log "no clang found; attempting apt install"
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y clang lld llvm || true
  for c in clang-18 clang-17 clang-16 clang-15 clang-14 clang; do
    if command -v "$c" >/dev/null 2>&1; then
      SYSTEM_CLANG="$c"
      break
    fi
  done
fi

if [[ -n "$SYSTEM_CLANG" ]]; then
  CLANG_REAL="$(readlink -f "$(command -v "$SYSTEM_CLANG")")"
  TC_BIN="$(dirname "$CLANG_REAL")"
  cat > "$TC_DIR/toolchain.env" <<EOF
TC_BIN=$TC_BIN
CC=$SYSTEM_CLANG
LD=ld.lld
EOF
  ok "toolchain ready (installed clang: $SYSTEM_CLANG)"
  exit 0
fi

err "no clang toolchain available. Install: apt install clang lld llvm"
exit 1
