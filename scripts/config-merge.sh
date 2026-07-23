#!/usr/bin/env bash
#
# scripts/config-merge.sh — merge config fragments into marble_defconfig
# Uses the kernel's own scripts/merge_config.sh on a copy of the base defconfig.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_SRC="${KERNEL_SRC:-$ROOT/kernel-src}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
CFG_DIR="$ROOT/configs"
FRAG_DIR="$CFG_DIR/fragments"

log()  { printf "\033[1;34m[cfg]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }

[[ -d "$KERNEL_SRC" ]] || { echo "kernel source missing"; exit 1; }

mkdir -p "$OUT_DIR"

# 1. Start from the base defconfig
log "copying base defconfig -> $OUT_DIR/.config"
cp -f "$CFG_DIR/marble_defconfig" "$OUT_DIR/.config"

# 2. Gather fragments (skip if dir empty)
FRAGMENTS=()
if [[ -d "$FRAG_DIR" ]]; then
  for f in "$FRAG_DIR"/*.config; do
    [[ -f "$f" ]] && FRAGMENTS+=("$f")
  done
fi

if [[ ${#FRAGMENTS[@]} -eq 0 ]]; then
  log "no fragments found; using base defconfig only"
else
  log "merging ${#FRAGMENTS[@]} fragments:"
  for f in "${FRAGMENTS[@]}"; do printf "   - %s\n" "$(basename "$f")"; done

  MERGE="$KERNEL_SRC/scripts/merge_config.sh"
  if [[ -x "$MERGE" ]]; then
    ( cd "$OUT_DIR" && \
      bash "$MERGE" -m -n -O "$OUT_DIR" \
        "$CFG_DIR/marble_defconfig" "${FRAGMENTS[@]}" )
  else
    # fallback: naive append + olddefconfig
    log "merge_config.sh not present; naive append fallback"
    for f in "${FRAGMENTS[@]}"; do cat "$f" >> "$OUT_DIR/.config"; done
  fi
fi

# 3. Make sure KSU driver Kconfig stub exists (so defconfig picks it up)
KSU_KC="$KERNEL_SRC/drivers/kernelsu/Kconfig"
if [[ ! -f "$KSU_KC" ]] && [[ -d "$KERNEL_SRC/drivers/kernelsu" ]]; then
  cat > "$KSU_KC" <<'EOF'
config KSU
    tristate "KernelSU support"
    depends on KPROBES
    default y
    help
      KernelSU-Next kernel-side root solution.

config KSU_KPROBES
    bool "KernelSU kprobe backend"
    depends on KSU && KPROBES
    default y

config KSU_SUSFS
    bool "KernelSU SUSFS (sus path/mount)"
    depends on KSU
    default y

config KSU_DEBUG
    bool "KernelSU debug"
    depends on KSU
    default n

config KSU_INSTANCE_PASSWORDS
    bool "KernelSU per-instance passwords"
    depends on KSU
    default n
EOF
fi

# wire KSU into drivers/Makefile if not present
KSU_MK="$KERNEL_SRC/drivers/Makefile"
if ! grep -q "kernelsu" "$KSU_MK" 2>/dev/null; then
  echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "$KSU_MK"
fi

ok "config merged -> $OUT_DIR/.config"
