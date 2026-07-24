# ADR 0006: AnyKernel3 Patch Model (Not mkbootimg)

**Status:** Accepted
**Date:** 2026-07-24

## Problem

For a GKI device like marble, the kernel lives in the `boot` partition
alongside a ramdisk, cmdline, and AVB signatures. When distributing a
custom kernel, the builder must decide whether to:

1. Build a full `boot.img` with mkbootimg and flash it via fastboot, OR
2. Ship only the bare `Image` and patch the existing `boot` partition
   on-device using AnyKernel3.

## Alternatives Considered

1. **mkbootimg full boot.img** — requires harvesting a ramdisk from a
   stock boot.img; overwrites Magisk/KernelSU root; can't adapt across
   ROM updates; must hardcode OS version and patch level.
2. **AnyKernel3 patch model** — ships only `Image`; unpacks the device's
   existing boot with magiskboot; replaces the kernel; repacks preserving
   ramdisk, root, cmdline, AVB flags.

## Decision

Adopt the **AnyKernel3 patch model** for all Aurora-Kernel marble releases.

## Rationale

- Verified against real marble kernel projects
  (mohdakil2426/marble-kernel-builder, Pzqqt/melt-kernel): all use AK3.
- AK3 preserves Magisk/KernelSU root automatically ("detect and retain
  Magisk root" per osm0sis/AnyKernel3 README).
- AK3 adapts to any ROM ("regardless of ramdisk") — critical for users
  on different HyperOS/AOSP ROM versions.
- AK3 handles A/B slot detection automatically (`is_slot_device=auto`).
- The `boot` partition is the only one touched; `vendor_boot`, `dtbo`,
  `vendor_dlkm`, `system_dlkm` remain intact (GKI kernel-only update).
- mkbootimg is only used by OEMs for factory boot.img builds, not by
  community kernel distributors.

## Future Impact

- The flashable zip contains: `Image` + `anykernel.sh` + `banner` +
  `tools/` (magiskboot, busybox, ak3-core.sh).
- No `boot.img`, `init_boot.img`, or `vendor_boot.img` is produced.
- Users flash via Kernel Flasher / TWRP / OrangeFox, not fastboot.
