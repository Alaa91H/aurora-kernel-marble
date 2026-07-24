#!/usr/bin/env bash
#
# scripts/config-merge.sh — merge base defconfig + vendor + fragments + flavors
#
# Hierarchical merge order (each layer builds on the previous):
#   1. Core:       configs/marble_defconfig
#   2. Vendor:     configs/vendor/marble_GKI.config + marble_consolidate.config
#   3. Fragments:  configs/fragments/*.config   (always applied)
#   4. Capabilities: configs/capabilities/*.config (always applied)
#   5. Platform:   configs/flavors/platform/<platform>.config
#   6. Root:       configs/flavors/root/<root>.config
#   7. Profile:    configs/flavors/profile/<profile>.config
#
# The FLAVOR env var controls layers 5-7: FLAVOR="platform-root-profile"
# Default: FLAVOR="aosp-noroot-production"
#
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

KERNEL_SRC="${KERNEL_SRC:-$ROOT/kernel-src}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
CFG_DIR="$ROOT/configs"
VENDOR_DIR="$CFG_DIR/vendor"
FRAG_DIR="$CFG_DIR/fragments"
CAP_DIR="$CFG_DIR/capabilities"
FLAVOR_DIR="$CFG_DIR/flavors"

log()  { printf "\033[1;34m[cfg]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }

[[ -d "$KERNEL_SRC" ]] || { echo "kernel source missing"; exit 1; }

# ---------------------------------------------------------------------------
# Parse FLAVOR="platform-root-profile" into 3 components
# ---------------------------------------------------------------------------
FLAVOR="${FLAVOR:-aosp-noroot-production}"
IFS='-' read -r FLAVOR_PLATFORM FLAVOR_ROOT FLAVOR_PROFILE <<< "$FLAVOR"

# defaults if missing
FLAVOR_PLATFORM="${FLAVOR_PLATFORM:-aosp}"
FLAVOR_ROOT="${FLAVOR_ROOT:-noroot}"
FLAVOR_PROFILE="${FLAVOR_PROFILE:-production}"

log "flavor: $FLAVOR"
log "  platform: $FLAVOR_PLATFORM"
log "  root:     $FLAVOR_ROOT"
log "  profile:  $FLAVOR_PROFILE"

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# 1. Start from the base defconfig
# ---------------------------------------------------------------------------
log "copying base defconfig -> $OUT_DIR/.config"
cp -f "$CFG_DIR/marble_defconfig" "$OUT_DIR/.config"

# ---------------------------------------------------------------------------
# 2. Gather all config files to merge (in hierarchical order)
# ---------------------------------------------------------------------------
MERGE_FILES=()

# 2a. Vendor configs (marble_GKI.config + marble_consolidate.config)
# These are the AUTHORITATIVE Xiaomi vendor configs from marble-s-oss.
if [[ -d "$VENDOR_DIR" ]]; then
  for f in "$VENDOR_DIR"/*.config; do
    [[ -f "$f" ]] && MERGE_FILES+=("$f")
  done
  log "  + vendor: $(ls "$VENDOR_DIR"/*.config 2>/dev/null | wc -l) files"
fi

# 2b. Core fragments (always applied — scheduler, battery, network, etc.)
if [[ -d "$FRAG_DIR" ]]; then
  for f in "$FRAG_DIR"/*.config; do
    [[ -f "$f" ]] && MERGE_FILES+=("$f")
  done
fi

# 2c. Capabilities layer (always applied — 300+ verified kernel features)
if [[ -d "$CAP_DIR" ]]; then
  for f in "$CAP_DIR"/*.config; do
    [[ -f "$f" ]] && MERGE_FILES+=("$f")
  done
  log "  + capabilities: $(ls "$CAP_DIR"/*.config 2>/dev/null | wc -l) files"
fi

# 2d. Platform flavor
PLATFORM_CFG="$FLAVOR_DIR/platform/${FLAVOR_PLATFORM}.config"
if [[ -f "$PLATFORM_CFG" ]]; then
  MERGE_FILES+=("$PLATFORM_CFG")
  log "  + platform: $PLATFORM_CFG"
else
  log "  WARNING: platform config not found: $PLATFORM_CFG"
fi

# 2e. Root flavor
ROOT_CFG="$FLAVOR_DIR/root/${FLAVOR_ROOT}.config"
if [[ -f "$ROOT_CFG" ]]; then
  MERGE_FILES+=("$ROOT_CFG")
  log "  + root: $ROOT_CFG"
else
  log "  WARNING: root config not found: $ROOT_CFG"
fi

# 2f. Profile flavor
PROFILE_CFG="$FLAVOR_DIR/profile/${FLAVOR_PROFILE}.config"
if [[ -f "$PROFILE_CFG" ]]; then
  MERGE_FILES+=("$PROFILE_CFG")
  log "  + profile: $PROFILE_CFG"
else
  log "  WARNING: profile config not found: $PROFILE_CFG"
fi

# ---------------------------------------------------------------------------
# 3. Merge via kernel's merge_config.sh (or naive fallback)
# ---------------------------------------------------------------------------
if [[ ${#MERGE_FILES[@]} -gt 0 ]]; then
  log "merging ${#MERGE_FILES[@]} config files (hierarchical):"
  for f in "${MERGE_FILES[@]}"; do printf "   - %s\n" "$(basename "$f")"; done

  MERGE="$KERNEL_SRC/scripts/merge_config.sh"
  if [[ -x "$MERGE" ]]; then
    ( cd "$OUT_DIR" && \
      bash "$MERGE" -m -n -O "$OUT_DIR" \
        "$CFG_DIR/marble_defconfig" "${MERGE_FILES[@]}" )
  else
    log "merge_config.sh not present; naive append fallback"
    for f in "${MERGE_FILES[@]}"; do cat "$f" >> "$OUT_DIR/.config"; done
  fi
else
  log "no flavor files found; using base defconfig only"
fi

# ---------------------------------------------------------------------------
# 4. KernelSU driver Kconfig stub (if KSU root flavor + driver present)
# ---------------------------------------------------------------------------
if [[ "$FLAVOR_ROOT" == "ksu" || "$FLAVOR_ROOT" == "ksunext" ]]; then
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
    log "created KSU Kconfig stub at drivers/kernelsu/Kconfig"
  fi

  # wire KSU into drivers/Makefile if not present
  KSU_MK="$KERNEL_SRC/drivers/Makefile"
  if ! grep -q "kernelsu" "$KSU_MK" 2>/dev/null; then
    echo 'obj-$(CONFIG_KSU) += kernelsu/' >> "$KSU_MK"
    log "wired KSU into drivers/Makefile"
  fi
else
  # NoRoot/APatch: ensure KSU is disabled even if driver present
  log "root flavor '$FLAVOR_ROOT' does not use KSU; ensuring disabled"
  if [[ -f "$OUT_DIR/.config" ]]; then
    sed -i 's/CONFIG_KSU=y/# CONFIG_KSU is not set/' "$OUT_DIR/.config" 2>/dev/null || true
  fi
fi

ok "config merged -> $OUT_DIR/.config (flavor: $FLAVOR)"
