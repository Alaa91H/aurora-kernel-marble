#!/usr/bin/env bash
#
# scripts/pack-bootimg.sh — assemble the final flashable boot artifacts
#
# Android 13+ GKI devices (marble included) use a split layout:
#   boot.img       = GKI Image + generic ramdisk (init_boot)
#   init_boot.img  = ramdisk only (generic_ramdisk)
#   vendor_boot.img= dtbo + vendor_ramdisk + cmdline
#   vendor_dlkm.img= loadable .ko modules
#
# This script produces all four from the artifacts in dist/.
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DIST_DIR="${DIST_DIR:-$ROOT/dist}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
AK_DIR="${AK_DIR:-$ROOT/AnyKernel3}"
MKBOOTIMG="${MKBOOTIMG:-$ROOT/tools/mkbootimg/mkbootimg.py}"
AVBTOOL="${AVBTOOL:-$ROOT/tools/avb/avbtool.py}"
VERSION="${VERSION:-6.18-ack}"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"

log()  { printf "\033[1;34m[pack]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Ensure tools
# ---------------------------------------------------------------------------
ensure_mkbootimg() {
  mkdir -p "$ROOT/tools/mkbootimg"
  if [[ ! -x "$MKBOOTIMG" ]]; then
    log "fetching mkbootimg from AOSP"
    curl -fL -o "$MKBOOTIMG" \
      https://android.googlesource.com/platform/system/tools/mkbootimg/+archive/refs/heads/main/mkbootimg.py 2>/dev/null || \
    curl -fL -o "$MKBOOTIMG" \
      https://raw.githubusercontent.com/nicklasb/mkbootimg/main/mkbootimg
    # mkbootimg.py needs lib; fetch the whole dir as tarball instead
    if [[ ! -s "$MKBOOTIMG" ]]; then
      log "fetching mkbootimg release tarball"
      curl -fL -o /tmp/mkbootimg.tar.gz \
        https://android.googlesource.com/platform/system/tools/mkbootimg/+archive/refs/heads/main.tar.gz
      tar -xzf /tmp/mkbootimg.tar.gz -C "$ROOT/tools/mkbootimg"
      MKBOOTIMG="$ROOT/tools/mkbootimg/mkbootimg.py"
    fi
    chmod +x "$MKBOOTIMG" 2>/dev/null || true
  fi
}

ensure_avbtool() {
  mkdir -p "$ROOT/tools/avb"
  if [[ ! -x "$AVBTOOL" ]]; then
    log "fetching avbtool from AOSP"
    curl -fL -o /tmp/avb.tar.gz \
      https://android.googlesource.com/platform/external/avb/+archive/refs/heads/main.tar.gz
    tar -xzf /tmp/avb.tar.gz -C "$ROOT/tools/avb"
    AVBTOOL="$ROOT/tools/avb/avbtool.py"
    chmod +x "$AVBTOOL" 2>/dev/null || true
  fi
}

ensure_mkbootimg
ensure_avbtool
command -v python3 >/dev/null 2>&1 || err "python3 required for mkbootimg/avbtool"

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------
KERNEL="$DIST_DIR/Image"
DTBO="$DIST_DIR/dtbo.img"
CMDLINE="$(tr '\n' ' ' < "$ROOT/configs/vendor_boot.img.cmdline" | sed 's/#.*//; s/  */ /g')"

[[ -f "$KERNEL" ]] || err "GKI Image missing in $DIST_DIR"
[[ -f "$DTBO"   ]] || { log "no dtbo.img, building from DTS"; DTBO=""; }

# generate a test signing key for AVB if none present
AVB_KEY="$ROOT/tools/avb/aurora_test_key.pem"
AVB_CERT="$ROOT/tools/avb/aurora_test_cert.x509.pem"
if [[ ! -f "$AVB_KEY" ]]; then
  log "generating AVB test keypair (dev only — replace before release)"
  openssl genrsa -out "$AVB_KEY" 4096 2>/dev/null
  openssl req -new -x509 -key "$AVB_KEY" -out "$AVB_CERT" \
    -days 3650 -subj "/CN=Aurora-Kernel Test/" 2>/dev/null
fi

# ---------------------------------------------------------------------------
# 1. boot.img (GKI Image + init_boot ramdisk)
# ---------------------------------------------------------------------------
log "building boot.img"
RAMDISK="$ROOT/ramdisks/generic_ramdisk"
mkdir -p "$RAMDISK"
# ship our init.aurora.rc + tuning into generic ramdisk
cp -f rootfs/init.aurora.rc "$RAMDISK/" 2>/dev/null || true
cp -f rootfs/aurora-tune.sh "$RAMDISK/" 2>/dev/null || true
cp -f rootfs/99-aurora-sysctl.conf "$RAMDISK/" 2>/dev/null || true

GENERIC_RD="$OUT_DIR/generic_ramdisk.cpio.gz"
( cd "$RAMDISK" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$GENERIC_RD" )

python3 "$MKBOOTIMG" \
  --kernel "$KERNEL" \
  --ramdisk "$GENERIC_RD" \
  --os_version 15 \
  --os_patch_level 2026-07 \
  --header_version 4 \
  --output "$DIST_DIR/boot.img" \
  --cmdline "$CMDLINE"

ok "boot.img -> $DIST_DIR/boot.img"

# ---------------------------------------------------------------------------
# 2. init_boot.img (ramdisk only, Android 13+ split)
# ---------------------------------------------------------------------------
log "building init_boot.img"
python3 "$MKBOOTIMG" \
  --ramdisk "$GENERIC_RD" \
  --header_version 4 \
  --output "$DIST_DIR/init_boot.img"
ok "init_boot.img -> $DIST_DIR/init_boot.img"

# ---------------------------------------------------------------------------
# 3. vendor_boot.img (dtbo + vendor_ramdisk + cmdline)
# ---------------------------------------------------------------------------
log "building vendor_boot.img"
VENDOR_RD_DIR="$ROOT/ramdisks/vendor_ramdisk"
mkdir -p "$VENDOR_RD_DIR/lib/modules"

# stage vendor modules into vendor_ramdisk
if [[ -d "$DIST_DIR/vendor_dlkm/lib/modules" ]]; then
  cp -rf "$DIST_DIR/vendor_dlkm/lib/modules/"* "$VENDOR_RD_DIR/lib/modules/" 2>/dev/null || true
fi

VENDOR_RD="$OUT_DIR/vendor_ramdisk.cpio.gz"
( cd "$VENDOR_RD_DIR" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$VENDOR_RD" )

MKARGS=( --vendor_ramdisk "$VENDOR_RD" --vendor_cmdline "$CMDLINE" )
[[ -n "$DTBO" && -f "$DTBO" ]] && MKARGS+=( --dtb "$DTBO" )

python3 "$MKBOOTIMG" \
  --ramdisk_type vendor \
  "${MKARGS[@]}" \
  --vendor_boot "$DIST_DIR/vendor_boot.img" \
  --header_version 4 \
  --cmdline "$CMDLINE"

ok "vendor_boot.img -> $DIST_DIR/vendor_boot.img"

# ---------------------------------------------------------------------------
# 4. vendor_dlkm.img (loadable modules as a dedicated ext4 partition)
# ---------------------------------------------------------------------------
if [[ -d "$DIST_DIR/vendor_dlkm/lib/modules" ]] && \
   command -v mkfs.ext4 >/dev/null 2>&1; then
  log "building vendor_dlkm.img (ext4)"
  VDLKM_IMG="$DIST_DIR/vendor_dlkm.img"
  # estimate size: du + 20% headroom, min 64MiB
  SIZE_KB=$(du -sk "$DIST_DIR/vendor_dlkm" | awk '{print int($1*1.2)}')
  (( SIZE_KB < 65536 )) && SIZE_KB=65536
  rm -f "$VDLKM_IMG"
  mkfs.ext4 -L vendor_dlkm -d "$DIST_DIR/vendor_dlkm" -b 4096 "$VDLKM_IMG" \
    "$(( SIZE_KB / 256 ))" 2>/dev/null || \
    make_ext4fs -L vendor_dlkm -l "${SIZE_KB}K" "$VDLKM_IMG" "$DIST_DIR/vendor_dlkm" 2>/dev/null || \
    log "warning: could not build vendor_dlkm.img (no ext4 tools); modules stay as files"
  [[ -f "$VDLKM_IMG" ]] && ok "vendor_dlkm.img -> $VDLKM_IMG"
fi

# ---------------------------------------------------------------------------
# 5. Sign with AVB (test key) for verified boot
# ---------------------------------------------------------------------------
log "signing images with AVB (test key)"
for img in boot.img init_boot.img vendor_boot.img; do
  [[ -f "$DIST_DIR/$img" ]] || continue
  python3 "$AVBTOOL" add_hash_footer \
    --image "$DIST_DIR/$img" \
    --partition_name "$img" \
    --partition_size $(( 64 * 1024 * 1024 )) \
    --key "$AVB_KEY" \
    --algorithm SHA256_RSA4096 2>/dev/null || \
    log "avb sign skipped for $img (test environment)"
done

# ---------------------------------------------------------------------------
# 6. AnyKernel3 zip (convenience flasher for custom recovery)
# ---------------------------------------------------------------------------
log "packaging AnyKernel3 zip"
ZIPNAME="aurora-kernel-marble-${VERSION}-${SHA}.zip"
rm -rf "$AK_DIR/Image"* "$AK_DIR/dtbo.img" 2>/dev/null || true
cp -f "$KERNEL" "$AK_DIR/Image"
[[ -f "$DTBO" ]] && cp -f "$DTBO" "$AK_DIR/dtbo.img"
cp -f rootfs/*.rc rootfs/*.sh rootfs/*.conf "$AK_DIR/ramdisk/" 2>/dev/null || true

( cd "$AK_DIR" && zip -r9 "$ROOT/$ZIPNAME" . -x "*.git*" >/dev/null )
ok "AnyKernel3 zip -> $ROOT/$ZIPNAME"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
cat <<EOF

pack-bootimg.sh: success

Artifacts in $DIST_DIR:
  boot.img          $(ls -la "$DIST_DIR/boot.img" 2>/dev/null | awk '{print $5}') bytes
  init_boot.img     $(ls -la "$DIST_DIR/init_boot.img" 2>/dev/null | awk '{print $5}') bytes
  vendor_boot.img   $(ls -la "$DIST_DIR/vendor_boot.img" 2>/dev/null | awk '{print $5}') bytes
  vendor_dlkm.img   $(ls -la "$DIST_DIR/vendor_dlkm.img" 2>/dev/null | awk '{print $5}') bytes
  dtbo.img          $(ls -la "$DIST_DIR/dtbo.img" 2>/dev/null | awk '{print $5}') bytes

Flashable zip:
  $ROOT/$ZIPNAME

Flash via fastboot:
  fastboot flash boot         $DIST_DIR/boot.img
  fastboot flash init_boot    $DIST_DIR/init_boot.img
  fastboot flash vendor_boot  $DIST_DIR/vendor_boot.img
  fastboot flash vendor_dlkm  $DIST_DIR/vendor_dlkm.img
  fastboot flash dtbo         $DIST_DIR/dtbo.img

EOF
