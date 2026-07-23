#!/usr/bin/env bash
#
# scripts/toolchain.sh — bootstrap Proton-Clang toolchain
# Downloads a prebuilt clang+lld tarball into toolchains/proton-clang.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TC_DIR="$ROOT/toolchains"
PROTON_DIR="$TC_DIR/proton-clang"

log()  { printf "\033[1;34m[tc]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }

# Latest Proton-Clang release URL (kdrag0n/proton-clang)
URL="${PROTON_CLANG_URL:-https://github.com/kdrag0n/proton-clang/releases/latest/download/proton-clang.tar.gz}"

mkdir -p "$TC_DIR"

if [[ -x "$PROTON_DIR/bin/clang" ]]; then
  log "Proton-Clang already present"
  "$PROTON_DIR/bin/clang" --version | head -1
  exit 0
fi

log "downloading Proton-Clang"
TARBALL="$TC_DIR/proton-clang.tar.gz"
curl -fL --retry 3 -o "$TARBALL" "$URL"

log "extracting"
mkdir -p "$PROTON_DIR"
tar -xzf "$TARBALL" -C "$PROTON_DIR"
rm -f "$TARBALL"

ok "Proton-Clang installed"
"$PROTON_DIR/bin/clang" --version | head -1
