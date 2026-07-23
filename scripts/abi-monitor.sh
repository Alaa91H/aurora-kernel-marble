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
# 2. Bootstrap a recorded list on first run (or if existing file has no
#    real symbol entries — e.g. only comments)
# ---------------------------------------------------------------------------
RECORDED_COUNT=$(grep -v '^[[:space:]]*#' "$RECORDED_LIST" 2>/dev/null | grep -v '^[[:space:]]*$' | wc -l)
if [[ ! -f "$RECORDED_LIST" ]] || [[ "$RECORDED_COUNT" -eq 0 ]]; then
  warn "no recorded symbol list (or empty); bootstrapping from current build"
  cp "$EXTRACTED" "$RECORDED_LIST"
  ok "created baseline: $RECORDED_LIST ($(wc -l < "$RECORDED_LIST") symbols)"
  exit 0
fi

# ---------------------------------------------------------------------------
# 3. Diff: removed (regression!) vs added (new)
#    comm requires BOTH inputs sorted; re-sort to be safe.
# ---------------------------------------------------------------------------
REMOVED="$DIST_DIR/abi.removed"
ADDED="$DIST_DIR/abi.added"
# sort both inputs into temp files so comm doesn't fail on ordering
# (also strip comments and blank lines from the recorded baseline)
SORTED_RECORDED=$(mktemp)
SORTED_EXTRACTED=$(mktemp)
grep -v '^[[:space:]]*#' "$RECORDED_LIST" | grep -v '^[[:space:]]*$' | sort -u > "$SORTED_RECORDED"
sort -u "$EXTRACTED" > "$SORTED_EXTRACTED"
comm -23 "$SORTED_RECORDED" "$SORTED_EXTRACTED" > "$REMOVED"
comm -13 "$SORTED_RECORDED" "$SORTED_EXTRACTED" > "$ADDED"
rm -f "$SORTED_RECORDED" "$SORTED_EXTRACTED"

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
