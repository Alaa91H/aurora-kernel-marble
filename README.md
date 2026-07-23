# Aurora-Kernel

<p align="center">
  <b>Professional Android kernel for Xiaomi marble (POCO F5 / Redmi Note 12 Turbo)</b><br>
  <sub>Qualcomm Snapdragon 7+ Gen 2 · SM7475 · Android Common Kernel 6.18 LTS</sub>
</p>

---

## Overview

Aurora-Kernel is a performance- and battery-oriented Android kernel built from
**Android Common Kernel (ACK) 6.18 LTS** (Google AOSP `common-android17-6.18` branch)
for the `marble` device. ACK is the Google-maintained LTS track that already
contains all Android-specific patches (binderfs, ashmem, GKI module exports,
vendor hooks) on top of the stable 6.18 LTS base — no need to re-port Android
features manually.

It targets maximum CPU efficiency (EAS + schedutil), aggressive-but-safe
battery tuning, full modern feature set (WireGuard, KVM, zRAM-allocator,
fscrypt v2, USB networking), and seamless **KernelSU-Next** integration.

| Spec                  | Value                                 |
|-----------------------|---------------------------------------|
| Device codename       | `marble` (POCO F5 / Redmi Note 12 Turbo) |
| SoC                    | Qualcomm Snapdragon 7+ Gen 2 (SM7475) |
| Kernel base           | Android Common Kernel **6.18 LTS** (`common-android17-6.18`) |
| Toolchain              | Clang 18 + LD.lld (AOSP)              |
| Root solution          | KernelSU-Next                         |
| Flash method           | AnyKernel3                            |
| Scheduler              | EAS (schedutil + UCLAMP)              |
| I/O scheduler          | Flash-Friendly (maple)                |
| Compression            | zSTD                                  |
| Page size              | 4096 (4KiB)                           |

---

## Repository layout

```
aurora-kernel-marble/
├── build.sh                    # Full pipeline orchestrator
├── setup.sh                    # Fetches ACK 6.18 LTS + KSU + AnyKernel3
├── build.config.marble         # Google ACK build config (GKI/KMI/LTO)
├── scripts/
│   ├── toolchain.sh            # Proton-Clang bootstrap
│   ├── vendor-fetch.sh         # Fetch Qualcomm/Xiaomi msm-kernel (SoC drivers)
│   ├── build-gki.sh            # Build GKI core + vmlinux.symvers
│   ├── build-vendor-modules.sh # Build vendor .ko against GKI KMI
│   ├── pack-bootimg.sh         # boot/init_boot/vendor_boot/vendor_dlkm/dtbo + AVB
│   ├── abi-monitor.sh          # Enforce KMI symbol stability
│   ├── patch-apply.sh          # Apply patches/series (git am)
│   └── config-merge.sh         # Merge fragments into defconfig
├── configs/
│   ├── marble_defconfig        # Base optimized defconfig
│   ├── fragments/
│   │   ├── performance.config  # CPU governor + schedtune
│   │   ├── battery.config      # Idle + thermal + walt
│   │   ├── ksu.config          # KernelSU-Next hooks
│   │   ├── network.config      # WireGuard + USB-Net + BBR
│   │   ├── virtualization.config # KVM + virtio + containers
│   │   ├── display.config      # DSI panel + refresh + backlight + Adreno
│   │   └── audio.config        # WCD9375 hi-res 24/32-bit + SoundWire + DSD
│   ├── anykernel_marble.conf   # AnyKernel3 board config
│   └── vendor_boot.img.cmdline # Kernel cmdline
├── arch/arm64/boot/dts/qcom/   # SM7475 device-tree
│   ├── sm7475-marble.dtsi      # Board include (reserved memory)
│   ├── marble-board.dts        # CPU topology + OPP tables
│   └── marble-peripherals.dtsi # Panel/TS/haptics/audio/WiFi/BT
├── device/marble/              # Android device config
│   ├── BoardConfig.mk          # Partition layout + AVB + GKI v4
│   ├── fstab.marble            # UFS mount table + fscrypt
│   ├── init.marble.rc          # Module loading + Aurora tuning
│   └── manifest.xml            # VINTF vendor interface manifest
├── android/
│   └── abi_gki_aarch64         # KMI symbol list (GKI contract)
├── patches/                    # Drop-in patch queue (git am)
│   └── series
├── rootfs/                     # Runtime tuning (shipped in ramdisk)
│   ├── init.aurora.rc          # Boot-time sysctl + cpufreq apply
│   ├── aurora-tune.sh          # One-shot runtime tuner (3 profiles)
│   ├── 99-aurora-sysctl.conf
│   └── 99-aurora-thermald.rc
├── ci/
│   └── build.yml               # Reference CI
├── .github/workflows/build.yml # GitHub Actions (full pipeline)
└── README.md
```

---

## Prerequisites (Linux host)

Build must run on **Linux** (Ubuntu 22.04+ or Arch). Windows is not supported.

```bash
sudo apt update && sudo apt install -y \
    bc bison build-essential ccache cpio curl flex git \
    libelf-dev libncurses-dev libssl-dev lld llvm python3 \
    zip zlib1g-dev e2fsprogs device-tree-compiler openssl
```

## Quick start

```bash
git clone https://github.com/<you>/aurora-kernel-marble.git
cd aurora-kernel-marble

# Full pipeline — fetches everything + builds + packages
./build.sh
```

`build.sh` runs the complete professional pipeline automatically:
1. `setup.sh` — fetch ACK 6.18 LTS + KernelSU + AnyKernel3
2. `vendor-fetch.sh` — fetch Qualcomm marble vendor tree
3. `toolchain.sh` — fetch Proton-Clang
4. `build-gki.sh` — compile GKI core (`Image` + `vmlinux.symvers`)
5. `abi-monitor.sh` — enforce KMI stability
6. `build-vendor-modules.sh` — compile SoC `.ko` modules against GKI
7. `pack-bootimg.sh` — assemble `boot.img`, `init_boot.img`,
   `vendor_boot.img`, `vendor_dlkm.img`, `dtbo.img` (AVB-signed)

Individual stages:
```bash
./build.sh gki       # only GKI core
./build.sh vendor    # only vendor modules
./build.sh pack      # only packaging
./build.sh abi       # only KMI check
./build.sh clean     # full wipe
```

## Flash

### Option A — Custom recovery (AnyKernel3 zip)
```
TWRP / OrangeFox → Install → aurora-kernel-marble-*.zip
```

### Option B — fastboot (GKI split images, recommended)
```bash
fastboot flash boot         dist/boot.img
fastboot flash init_boot    dist/init_boot.img
fastboot flash vendor_boot  dist/vendor_boot.img
fastboot flash vendor_dlkm  dist/vendor_dlkm.img
fastboot flash dtbo         dist/dtbo.img
fastboot reboot
```

Outputs land in `dist/` (boot images) and repo root (AnyKernel3 zip).

---

## Optimization highlights

### CPU & scheduling
- **EAS** (Energy Aware Scheduling) + **schedutil** governor
- **UCLAMP** bounds to keep foreground tasks boosted and background clamped
- **WALT** (Window-Assisted Load Tracking) for bursty workloads
- Per-cluster scheduling domains tuned for 1+3+4 topology

### Battery
- Runtime PM auto-suspend on all leaf devices
- MSM ADSP/SLPI low-power modes enabled
- `snd_hrtimer` + audio low-latency without persistent wakeups
- zRAM writeback + zSTD for memory pressure relief

### Security
- Android FBE (fscrypt v2) with inline crypto on UFS
- KASLR + hardened usercopy + refcount hardening
- SELinux in enforcing mode (netfilter integration)

### Features
- **KernelSU-Next** (kprobe-based root)
- **KVM** virtualization (host-mode)
- **WireGuard** in-kernel
- **usb-f_fdl** + RNDIS/ECM adapters for USB networking
- **exFAT**, **NTFS3** (Paragon) filesystems
- **BPF trampolines** + **BTF** for modern observability

### CPU Undervolting (UV)
- **Real UV** via `opp-microvolt` in DTS OPP tables (not a magic patch)
- ~ -25mV across all clusters (silver/gold/prime), validated to tolerance ±5mV
- Lowers heat and battery drain at high clocks
- **Tune per-device:** silicon varies; raise voltage by 10mV if crashes occur

### Display
- 120Hz AMOLED via DSI command-mode + TE (tearing-effect) signalling
- Panel power-domain gating via RPMH
- Backlight PWM for AOD / DC-dimming path
- Adreno 725 DPU composition

### Audio (hi-res)
- WCD9375 codec over SoundWire
- 24/32-bit PCM up to 384kHz (native, no resampling)
- Q6DSPV2 AFE/ASM/ADM audio core
- Native DSD (Direct Stream Digital) support
- USB-C DAC / hi-res headset via USB audio

---

## Important: what a kernel can and cannot do

### Camera — Google Camera (GCam)
**The kernel does NOT enable Google Camera.** GCam compatibility is determined by:
- The **Camera HAL / vendor blobs** (the proprietary userspace camera library)
- The **Camera2 API** level exposed by the vendor
- Package-name whitelists enforced by the vendor

Installing GCam is a userspace task (GCam APK + a Camera2-enabled vendor +
a Magisk module for aux-camera), not a kernel patch. No kernel change can
make a non-compatible device run GCam. If your stock ROM already supports
Camera2 HAL3 (marble does), GCam ports will work regardless of kernel.

### "UV patches"
UV is real and is done via the `opp-microvolt` property in the device-tree
OPP table (see `arch/arm64/boot/dts/qcom/marble-board.dts`). cpufreq
selects an OPP; the PMIC regulator driver applies the voltage.

### Display refresh-rate at rest
The kernel does not idle the refresh rate by itself. Panel self-refresh /
low-fps idle is a panel + SurfaceFlinger concern. The kernel provides the
DSI command queue and TE interrupt that userspace uses to switch modes.

---

## Reality check on the 6.18 port

This repo builds on **Android Common Kernel 6.18 LTS** (`common-android17-6.18`).
That is the GKI core for **Android 17**, not Android 15/16.

Xiaomi's official marble kernel source (`MiCode/marble-s-oss`) is
**Android 12 / 5.10-class**. There is no official 6.18 marble tree.
Porting SoC drivers (UFS, display, audio, modem, camera) from 5.10 to 6.18
is **mainlining work** — the clock, pinctrl, iommu, and interconnect
bindings all changed between 5.10 and 6.18. This repo provides the full
build scaffolding + DTS + defconfig; the driver mainlining patches are
expected to be added under `patches/`.

---

## CI

Push to `main` triggers `.github/workflows/build.yml` which runs `setup.sh`
+ `build.sh` on `ubuntu-22.04` and uploads the AnyKernel3 zip as an artifact.

---

## Disclaimer

This kernel is provided "as is", without warranty. You alone are responsible
for anything that happens to your device. Keep a stock `boot.img` backup
before flashing. The Android Common Kernel is GPL-2.0-only; this repository's
tooling is Apache-2.0.

## Credits

- Google AOSP — Android Common Kernel (ACK) 6.18 LTS
- KernelSU-Next team
- AnyKernel3 (osm0sis)
- Proton-Clang toolchain
- Xiaomi for the marble device
