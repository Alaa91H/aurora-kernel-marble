#!/usr/bin/env bash
#
# scripts/abi-monitor.sh — enforce GKI KMI (Kernel Module Interface) stability
#
# GKI's promise: a vendor module built against ACK 6.18 must load on ANY
# ACK 6.18 device. This is enforced by the KMI symbol list
# (android/abi_gki_aarch64) — the set of exported symbols a module may use.
#
# This script:
#   1. Builds the GKI with KMI_ENFORCED
#   2. Extracts the actual exported symbol set from vmlinux
#   3. Diffs against the recorded symbol list
#   4. Reports regressions (removed symbols) and additions (new symbols)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_DIR="${OUT_DIR:-$ROOT/out}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
ABI_DIR="$ROOT/android"
SYMVERS="$DIST_DIR/vmlinux.symvers"
RECORDED_LIST="$ABI_DIR/abi_gki_aarch64"
EXTRACTED="$DIST_DIR/abi_gki_aarch64.extracted"

log()  { printf "\033[1;34m[abi]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; }

[[ -f "$SYMVERS" ]] || { err "vmlinux.symvers missing; build GKI first"; exit 1; }

mkdir -p "$ABI_DIR"

# ---------------------------------------------------------------------------
# 1. Extract current symbol set
# ---------------------------------------------------------------------------
log "extracting exported symbols from vmlinux.symvers"
# Module.symvers lines: 0xcrc  symbol_name  namespace  module_name  export_type
awk '{print $2}' "$SYMVERS" | sort -u > "$EXTRACTED"
ok "$(wc -l < "$EXTRACTED") symbols exported by GKI build"

# ---------------------------------------------------------------------------
# 2. Bootstrap a recorded list on first run
# ---------------------------------------------------------------------------
if [[ ! -f "$RECORDED_LIST" ]]; then
  warn "no recorded symbol list; bootstrapping from current build"
  cp "$EXTRACTED" "$RECORDED_LIST"
  ok "created baseline: $RECORDED_LIST"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Diff: removed (regression!) vs added (new)
# ---------------------------------------------------------------------------
REMOVED="$DIST_DIR/abi.removed"
ADDED="$DIST_DIR/abi.added"
comm -23 "$RECORDED_LIST" "$EXTRACTED" > "$REMOVED"
comm -13 "$RECORDED_LIST" "$EXTRACTED" > "$ADDED"

N_REMOVED=$(wc -l < "$REMOVED")
N_ADDED=$(wc -l < "$ADDED")

if [[ "$N_REMOVED" -gt 0 ]]; then
  err "KMI regression: $N_REMOVED symbols were REMOVED"
  err "these vendor modules will refuse to load:"
  head -20 "$REMOVED" | sed 's/^/    - /' >&2
  err "fix: re-add the symbols to the GKI defconfig, or update the symbol list"
  err "     if the removal is intentional: cp $EXTRACTED $RECORDED_LIST"
  exit 1
fi

if [[ "$N_ADDED" -gt 0 ]]; then
  warn "$N_ADDED new symbols exported (additions are allowed, not breaking)"
  warn "to record them: cp $EXTRACTED $RECORDED_LIST"
fi

ok "KMI stable: 0 regressions, $N_ADDED additions, $(wc -l < "$RECORDED_LIST") total symbols"
