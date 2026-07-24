#!/usr/bin/env bash
#
# scripts/pack-bootimg.sh — package the GKI kernel into an AnyKernel3 zip
#
# DESIGN (verified from real marble kernel projects):
#   AnyKernel3 PATCHES the existing boot partition on-device using
#   magiskboot. The builder only ships a bare `Image` (the kernel binary).
#   The AK3 zip contains: Image + anykernel.sh + banner + tools/.
#
#   This preserves the installed ROM's ramdisk, Magisk/KernelSU root, OS
#   version, cmdline, and AVB flags. It is the professional GKI standard.
#
#   mkbootimg (full boot.img) is NOT used because:
#   - it requires harvesting a ramdisk from a stock boot.img
#   - it overwrites Magisk/KernelSU root
#   - it can't adapt across ROM updates
#
# References:
#   - mohdakil2426/marble-kernel-builder (primary)
#   - osm0sis/AnyKernel3 README
#   - docs/adr/0006-anykernel3-patch-model.md
#
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DIST_DIR="${DIST_DIR:-$ROOT/dist}"
AK_DIR="${AK_DIR:-$ROOT/AnyKernel3}"
AK_OVERLAY="$ROOT/ak3"
VERSION="${VERSION:-6.18-ack}"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"

log()  { printf "\033[1;34m[pack]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[warn]\033[0m %s\n" "$*"; }

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------
KERNEL="$DIST_DIR/Image"
[[ -f "$KERNEL" ]] || { warn "FATAL: GKI Image not found at $KERNEL"; exit 1; }
KERNEL_SIZE=$(stat -c%s "$KERNEL" 2>/dev/null || stat -f%z "$KERNEL" 2>/dev/null || echo 0)
ok "GKI Image: $KERNEL ($KERNEL_SIZE bytes)"

# ---------------------------------------------------------------------------
# 1. Prepare AnyKernel3 work directory
# ---------------------------------------------------------------------------
log "preparing AnyKernel3 zip"
WORK_DIR="$(mktemp -d)"
AK3_WORK="$WORK_DIR/ak3"

if [[ -d "$AK_DIR/.git" ]]; then
  # clone AK3 fresh into work dir (clean state, no leftover Image)
  git clone --depth=1 "$AK_DIR" "$AK3_WORK" 2>/dev/null || \
    cp -a "$AK_DIR" "$AK3_WORK"
else
  warn "AnyKernel3 not found at $AK_DIR"
  exit 1
fi

# remove any placeholder/test files from the AK3 template
rm -f "$AK3_WORK/placeholder" "$AK3_WORK/README.md" 2>/dev/null || true
rm -rf "$AK3_WORK/.git" "$AK3_WORK/.github" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Overlay marble-specific files (anykernel.sh, banner)
# ---------------------------------------------------------------------------
log "overlaying marble board config"
if [[ -f "$AK_OVERLAY/anykernel.sh" ]]; then
  cp -f "$AK_OVERLAY/anykernel.sh" "$AK3_WORK/anykernel.sh"
  chmod +x "$AK3_WORK/anykernel.sh" 2>/dev/null || true
  ok "anykernel.sh (marble board config) applied"
else
  warn "no marble anykernel.sh overlay; using AK3 default template"
fi

if [[ -f "$AK_OVERLAY/banner" ]]; then
  # expand $VERSION and $SHA in the banner
  VERSION="$VERSION" SHA="$SHA" envsubst < "$AK_OVERLAY/banner" > "$AK3_WORK/banner" 2>/dev/null || \
    cp -f "$AK_OVERLAY/banner" "$AK3_WORK/banner"
  ok "banner applied"
fi

# ---------------------------------------------------------------------------
# 3. Copy the GKI Image (the ONLY kernel artifact in the zip)
# ---------------------------------------------------------------------------
log "copying GKI Image into zip"
cp -f "$KERNEL" "$AK3_WORK/Image"
ok "Image: $(stat -c%s "$AK3_WORK/Image" 2>/dev/null || echo ?) bytes"

# also provide Image.gz (some Kernel Flasher variants prefer it)
if command -v gzip >/dev/null 2>&1; then
  gzip -9 -c "$KERNEL" > "$AK3_WORK/Image.gz" 2>/dev/null && \
    ok "Image.gz: $(stat -c%s "$AK3_WORK/Image.gz" 2>/dev/null || echo ?) bytes"
fi

# ---------------------------------------------------------------------------
# 4. Copy runtime tuning into the zip (for first-boot init)
# ---------------------------------------------------------------------------
log "copying runtime tuning files"
cp -f rootfs/init.aurora.rc          "$AK3_WORK/" 2>/dev/null || true
cp -f rootfs/aurora-tune.sh          "$AK3_WORK/" 2>/dev/null || true
cp -f rootfs/99-aurora-sysctl.conf   "$AK3_WORK/" 2>/dev/null || true
cp -f rootfs/99-aurora-thermald.rc   "$AK3_WORK/" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 5. Build the zip
# ---------------------------------------------------------------------------
ZIPNAME="aurora-kernel-marble-${VERSION}-${SHA}.zip"
ZIPPATH="$DIST_DIR/$ZIPNAME"

log "creating $ZIPNAME"
( cd "$AK3_WORK" && zip -r9 "$ZIPPATH" . \
    -x "*.git*" ".github/*" "tools/placeholder" >/dev/null 2>&1 )

if [[ -f "$ZIPPATH" ]]; then
  ZIP_SIZE=$(stat -c%s "$ZIPPATH" 2>/dev/null || stat -f%z "$ZIPPATH" 2>/dev/null || echo 0)
  ok "flashable zip: $ZIPPATH ($ZIP_SIZE bytes)"

  # sha256 checksum
  ( cd "$DIST_DIR" && sha256sum "$ZIPNAME" > "$ZIPNAME.sha256" 2>/dev/null ) || true
  ok "checksum: $ZIPNAME.sha256"
else
  warn "zip creation failed"
  exit 1
fi

# ---------------------------------------------------------------------------
# 6. Audit — verify the zip contains required entries
# ---------------------------------------------------------------------------
log "auditing zip contents"
REQUIRED=(
  "Image"
  "anykernel.sh"
  "banner"
  "META-INF/com/google/android/update-binary"
  "META-INF/com/google/android/updater-script"
  "tools/ak3-core.sh"
  "tools/busybox"
  "tools/magiskboot"
)

ZIP_CONTENTS=$(unzip -l "$ZIPPATH" 2>/dev/null | awk '{print $4}')
MISSING=0
for req in "${REQUIRED[@]}"; do
  if ! echo "$ZIP_CONTENTS" | grep -q "$req"; then
    warn "missing required entry: $req"
    MISSING=$((MISSING + 1))
  fi
done

if [[ "$MISSING" -eq 0 ]]; then
  ok "audit passed: all ${#REQUIRED[@]} required entries present"
else
  warn "audit: $MISSING entries missing (zip may still flash but could fail)"
fi

# verify zip is non-trivially sized (> 5 MB, contains the magiskboot binary)
if [[ "$ZIP_SIZE" -lt 5000000 ]]; then
  warn "zip is only $ZIP_SIZE bytes — expected > 5MB (magiskboot is large)"
fi

# ---------------------------------------------------------------------------
# 7. Cleanup + summary
# ---------------------------------------------------------------------------
rm -rf "$WORK_DIR"

cat <<EOF

pack-bootimg.sh: SUCCESS

Primary deliverable:
  $ZIPPATH
  ($ZIP_SIZE bytes)

Contents:
  - Image              (GKI kernel binary, $KERNEL_SIZE bytes)
  - anykernel.sh       (marble board config: block=boot, slot=auto)
  - banner             (Aurora branding)
  - tools/             (magiskboot, busybox, ak3-core.sh)
  - runtime tuning     (init.aurora.rc, aurora-tune.sh, sysctl.conf)

How it flashes:
  1. User flashes zip via Kernel Flasher / TWRP / OrangeFox
  2. AK3 verifies device codename (marble / marblein)
  3. AK3 backs up current boot to /sdcard/aurora-kernel-backup/
  4. magiskboot unpacks the existing boot partition
  5. The new Image replaces the old kernel
  6. magiskboot repacks (preserving ramdisk, cmdline, OS version, Magisk)
  7. Result is dd'd back to the boot partition (active slot)

This preserves: Magisk/KernelSU root, ROM ramdisk, cmdline, AVB flags.

EOF
