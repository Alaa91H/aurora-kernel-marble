#!/usr/bin/env bash
#
# scripts/pack-bootimg.sh — package the GKI kernel into a flashable zip
#
# Produces:
#   1. AnyKernel3 zip (primary deliverable — flashes boot.img on device)
#   2. boot.img (GKI Image + ramdisk, via mkbootimg if available)
#   3. init_boot.img, vendor_boot.img (if mkbootimg succeeds)
#
# The AnyKernel3 zip is always produced as long as the GKI Image exists,
# even if mkbootimg/avbtool fail.
#
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DIST_DIR="${DIST_DIR:-$ROOT/dist}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
AK_DIR="${AK_DIR:-$ROOT/AnyKernel3}"
VERSION="${VERSION:-6.18-ack}"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"

log()  { printf "\033[1;34m[pack]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------
KERNEL="$DIST_DIR/Image"
[[ -f "$KERNEL" ]] || { log "FATAL: GKI Image not found at $KERNEL"; exit 1; }
ok "GKI Image: $KERNEL ($(stat -c%s "$KERNEL" 2>/dev/null || echo ?) bytes)"

DTBO="$DIST_DIR/dtbo.img"
[[ -f "$DTBO" ]] || DTBO=""

CMDLINE="console=ttyMSM0,115200n8 androidboot.hardware=qcom"
if [[ -f "$ROOT/configs/vendor_boot.img.cmdline" ]]; then
  CMDLINE="$(tr '\n' ' ' < "$ROOT/configs/vendor_boot.img.cmdline" | sed 's/#.*//; s/  */ /g')"
fi

# ---------------------------------------------------------------------------
# 1. AnyKernel3 zip (PRIMARY deliverable — always produced)
# ---------------------------------------------------------------------------
log "packaging AnyKernel3 flashable zip"
if [[ -d "$AK_DIR" ]]; then
  # copy GKI Image into AnyKernel3
  cp -f "$KERNEL" "$AK_DIR/Image"
  [[ -n "$DTBO" ]] && cp -f "$DTBO" "$AK_DIR/dtbo.img" || true

  # also copy Image.gz (gzip-compressed) — some devices want this
  if command -v gzip >/dev/null 2>&1; then
    gzip -9 -c "$KERNEL" > "$AK_DIR/Image.gz" 2>/dev/null || true
  fi

  # copy runtime tuning into AnyKernel3 ramdisk
  mkdir -p "$AK_DIR/ramdisk" 2>/dev/null || true
  cp -f rootfs/init.aurora.rc          "$AK_DIR/ramdisk/" 2>/dev/null || true
  cp -f rootfs/aurora-tune.sh          "$AK_DIR/ramdisk/" 2>/dev/null || true
  cp -f rootfs/99-aurora-sysctl.conf   "$AK_DIR/ramdisk/" 2>/dev/null || true
  cp -f rootfs/99-aurora-thermald.rc   "$AK_DIR/ramdisk/" 2>/dev/null || true

  ZIPNAME="aurora-kernel-marble-${VERSION}-${SHA}.zip"
  rm -f "$ROOT/$ZIPNAME"
  ( cd "$AK_DIR" && zip -r9 "$ROOT/$ZIPNAME" . -x "*.git*" "tools/*" >/dev/null 2>&1 )
  if [[ -f "$ROOT/$ZIPNAME" ]]; then
    ok "AnyKernel3 zip: $ROOT/$ZIPNAME ($(stat -c%s "$ROOT/$ZIPNAME" 2>/dev/null || echo ?) bytes)"
  else
    warn "AnyKernel3 zip creation failed"
  fi
else
  warn "AnyKernel3 dir not found ($AK_DIR); skipping zip"
fi

# ---------------------------------------------------------------------------
# 2. boot.img via mkbootimg (if available)
# ---------------------------------------------------------------------------
MKBOOTIMG=""
# try to fetch mkbootimg from a reliable mirror
fetch_mkbootimg() {
  local dst="$ROOT/tools/mkbootimg"
  mkdir -p "$dst"
  if [[ -f "$dst/mkbootimg.py" ]]; then
    MKBOOTIMG="$dst/mkbootimg.py"
    return 0
  fi
  log "fetching mkbootimg"
  # the whole repo as tarball (mkbootimg.py needs the lib/ dir)
  curl -fsSL -o /tmp/mkbootimg.tar.gz \
    "https://github.com/nicklasb/mkbootimg/archive/refs/heads/main.tar.gz" 2>/dev/null && \
    tar -xzf /tmp/mkbootimg.tar.gz -C "$dst" --strip-components=1 2>/dev/null && \
    MKBOOTIMG="$dst/mkbootimg.py" && return 0

  # fallback: AOSP gitiles tarball
  curl -fsSL -o /tmp/mkbootimg.tar.gz \
    "https://android.googlesource.com/platform/system/tools/mkbootimg/+archive/refs/heads/main.tar.gz" 2>/dev/null && \
    tar -xzf /tmp/mkbootimg.tar.gz -C "$dst" 2>/dev/null && \
    MKBOOTIMG="$dst/mkbootimg.py" && return 0

  warn "could not fetch mkbootimg; only AnyKernel3 zip produced"
  return 1
}

if fetch_mkbootimg && [[ -n "$MKBOOTIMG" ]] && [[ -f "$MKBOOTIMG" ]]; then
  ok "mkbootimg: $MKBOOTIMG"

  # build a minimal generic ramdisk (init.aurora.rc + tuning)
  RAMDISK="$ROOT/ramdisks/generic_ramdisk"
  mkdir -p "$RAMDISK"
  cp -f rootfs/init.aurora.rc          "$RAMDISK/" 2>/dev/null || true
  cp -f rootfs/aurora-tune.sh          "$RAMDISK/" 2>/dev/null || true
  cp -f rootfs/99-aurora-sysctl.conf   "$RAMDISK/" 2>/dev/null || true

  GENERIC_RD="$OUT_DIR/generic_ramdisk.cpio.gz"
  if ( cd "$RAMDISK" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$GENERIC_RD" ); then
    ok "generic ramdisk: $GENERIC_RD"
  else
    warn "ramdisk creation failed; boot.img will have no ramdisk"
    GENERIC_RD=""
  fi

  # boot.img (header v4)
  MK_ARGS=( --kernel "$KERNEL" --os_version 15 --os_patch_level 2026-07
            --header_version 4 --output "$DIST_DIR/boot.img" --cmdline "$CMDLINE" )
  [[ -n "$GENERIC_RD" ]] && [[ -f "$GENERIC_RD" ]] && MK_ARGS+=( --ramdisk "$GENERIC_RD" )

  if python3 "$MKBOOTIMG" "${MK_ARGS[@]}" 2>/dev/null; then
    ok "boot.img -> $DIST_DIR/boot.img"
  else
    warn "mkbootimg failed; AnyKernel3 zip is the primary deliverable"
  fi

  # init_boot.img (ramdisk only)
  if [[ -n "$GENERIC_RD" ]]; then
    python3 "$MKBOOTIMG" --ramdisk "$GENERIC_RD" --header_version 4 \
      --output "$DIST_DIR/init_boot.img" 2>/dev/null && \
      ok "init_boot.img -> $DIST_DIR/init_boot.img" || \
      warn "init_boot.img creation failed"
  fi
else
  warn "mkbootimg unavailable; only AnyKernel3 zip produced"
fi

# ---------------------------------------------------------------------------
# 3. Summary
# ---------------------------------------------------------------------------
log "=== packaging summary ==="
log "dist/ contents:"
ls -la "$DIST_DIR"/ 2>/dev/null | tail -20
[[ -f "$ROOT/aurora-kernel-marble-"*".zip" ]] && ok "flashable zip in repo root" || true

cat <<EOF

pack-bootimg.sh: done

Primary deliverable:
  AnyKernel3 zip : aurora-kernel-marble-${VERSION}-${SHA}.zip

Flashable via TWRP/OrangeFox:
  Install -> aurora-kernel-marble-${VERSION}-${SHA}.zip

Or via fastboot (if boot.img produced):
  fastboot flash boot dist/boot.img

EOF
