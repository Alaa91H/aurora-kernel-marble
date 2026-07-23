#!/usr/bin/env bash
#
# scripts/patch-apply.sh — apply the patch queue under patches/
# Uses `git am` style; each patch is a git format-patch.
# The order is defined by patches/series.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_SRC="${KERNEL_SRC:-$ROOT/kernel-src}"
PATCH_DIR="$ROOT/patches"
SERIES="$PATCH_DIR/series"

log()  { printf "\033[1;34m[patch]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }

if [[ ! -d "$KERNEL_SRC/.git" ]]; then
  log "kernel source not a git repo — initializing for patch tracking"
  ( cd "$KERNEL_SRC" && git init -q && git add -A && git commit -q -m "init: ACK 6.18 LTS" )
fi

if [[ ! -f "$SERIES" ]]; then
  log "no patches/series file; nothing to apply"
  exit 0
fi

cd "$KERNEL_SRC"
APPLIED=0
FAILED=0
while read -r p; do
  [[ -z "$p" ]] && continue
  [[ "$p" == \#* ]] && continue
  PATCH="$PATCH_DIR/$p"
  [[ -f "$PATCH" ]] || { log "missing patch: $p"; FAILED=$((FAILED+1)); continue; }
  if git am --show-current-patch >/dev/null 2>&1; then
    log "already mid-am, skipping $p"
    continue
  fi
  if git log --oneline -1 --grep="$p" >/dev/null 2>&1; then
    log "already applied: $p"
    APPLIED=$((APPLIED+1))
    continue
  fi
  log "applying: $p"
  if git am --3way --ignore-whitespace "$PATCH" 2>/dev/null; then
    ok "applied: $p"
    APPLIED=$((APPLIED+1))
  else
    git am --abort 2>/dev/null || true
    printf "\033[1;31m[fail]\033[0m %s\n" "$p"
    FAILED=$((FAILED+1))
  fi
done < "$SERIES"

ok "applied=$APPLIED failed=$FAILED"
[[ "$FAILED" -eq 0 ]]
