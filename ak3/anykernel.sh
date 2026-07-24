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
'; }

## — block / slot —
# block=auto lets AK3 find the boot partition by name (/dev/block/by-name/boot)
block=boot;

# marble is an A/B slot device; auto detects and appends _a/_b
is_slot_device=auto;

# ramdisk compression: auto-detect from the existing boot image
ramdisk_compression=auto;

# GKI is bootable with verity ON as long as AVB isn't enforced for boot
patch_vbmeta_flag=auto;

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
  dd if=/dev/block/by-name/boot$(slotselect) of="$backup_img" 2>/dev/null;
  echo "[aurora] backed up current boot to ${backup_img}";
}

## — execute the patch flow —
# 1. dump_boot: unpack the existing boot partition using magiskboot
# 2. backup_current_boot: save a copy before we modify anything
# 3. write_boot: repack with the new Image (from zip root) and flash back
dump_boot;
backup_current_boot;
write_boot;
