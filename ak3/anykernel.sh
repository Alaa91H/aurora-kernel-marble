# anykernel.sh — Aurora-Kernel AnyKernel3 board config for marble
#
# This file is placed at the root of the AnyKernel3 zip and sourced by
# tools/ak3-core.sh at flash time.
#
# Design: AnyKernel3 PATCHES the existing boot partition on-device using
# magiskboot. It does NOT flash a pre-built boot.img. This preserves the
# installed ROM's ramdisk, Magisk/KernelSU root, OS version, patch level,
# cmdline, and AVB flags.
#
# This is the professional GKI standard — see ADR-0006 in docs/adr/.
#
# Verified against:
#   - POCO F5 (codename: marblein)
#   - Redmi Note 12 Turbo (codename: marble)
#   - SM7475 / Snapdragon 7+ Gen 2
#   - Android 12-5.10 GKI base (marble ships android12-5.10 GKI kernel)
#

## — properties (read by the AK3 UI / Kernel Flasher) —
properties() { '
kernel.string=Aurora-Kernel 6.18 LTS for marble (POCO F5 / Redmi Note 12 Turbo)
kernel.author=Aurora-Kernel Contributors
kernel.version=6.18-ack

do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0

device.name1=marble
device.name2=marblein

supported.versions=
supported.patchlevels=
'; } # end properties

## — boot files attributes (permissions for the ramdisk overlay) —
boot_attributes() {
  set_perm_recursive 0 0 755 644 $RAMDISK/*;
  set_perm_recursive 0 0 750 750 $RAMDISK/init* $RAMDISK/sbin;
} # end attributes

## — block / slot —
# BLOCK=boot tells AK3 to locate the boot partition by name
# (/dev/block/by-name/boot), appending the active slot suffix on A/B.
BLOCK=boot;

# marble is an A/B slot device; auto detects and appends _a/_b
IS_SLOT_DEVICE=auto;

# ramdisk compression: auto-detect from the existing boot image
RAMDISK_COMPRESSION=auto;

# GKI is bootable with verity ON as long as AVB isn't enforced for boot
PATCH_VBMETA_FLAG=auto;

## — main flash routine —
# Source the AK3 core (provides dump_boot, write_boot, backup helpers)
. tools/ak3-core.sh;

## — backup the current boot before patching —
backup_current_boot() {
  local backup_dir="/sdcard/aurora-kernel-backup";
  local slot_name="${SLOT:-noslot}";
  local stamp;
  stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || date +%s)";
  local backup_img="${backup_dir}/boot-marble-${slot_name}-${stamp}.img";

  mkdir -p "$backup_dir";
  # SLOT is exported by ak3-core.sh for A/B devices; use it instead of a
  # nonexistent $(slotselect) helper
  dd if=/dev/block/by-name/boot${SLOT} of="$backup_img" 2>/dev/null;
  echo "[aurora] backed up current boot to ${backup_img}";
}

## — execute the patch flow —
# 1. dump_boot: unpack the existing boot partition using magiskboot
# 2. backup_current_boot: save a copy before we modify anything
# 3. append the init.aurora.rc import into the UNPACKED ramdisk's init.rc
#    (AK3 file-edit helpers only touch the unpacked ramdisk, so this must
#    come after dump_boot; patch/init.rc supplies the import line)
# 4. write_boot: repack with the new Image (from zip root) and flash back
dump_boot;
backup_current_boot;
# init.aurora.rc (overlaid into ramdisk/ by pack-bootimg.sh) must be imported
# by the stock init.rc or its triggers never fire.
backup_file init.rc;
append_file init.rc "import /init.aurora.rc" init.rc;
write_boot;
