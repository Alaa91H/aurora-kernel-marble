# AGENTS.md — Aurora-Kernel

## Build environment
- **Host OS:** Linux only (Ubuntu 22.04+). Windows is unsupported.
- **Toolchain:** Proton-Clang (auto-fetched by `scripts/toolchain.sh`).
- **Kernel base:** Android Common Kernel (ACK) 6.18 LTS — Google AOSP
  `common-android17-6.18` branch (fetched by `setup.sh`).
- **Vendor tree:** Qualcomm/Xiaomi `msm-kernel` for marble (fetched by
  `scripts/vendor-fetch.sh`). Provides SoC drivers as loadable modules.

## Architecture (GKI split + Flavor system)
The build follows Google's GKI (Generic Kernel Image) model with a
hierarchical flavor merge for platform/root/profile variants:

### GKI layers
1. **GKI core** — built from ACK 6.18 via Bazel/kleaf, produces `Image` +
   `vmlinux.symvers`.
2. **Vendor modules** — built from the msm-kernel tree *against* the GKI
   `Module.symvers` (expected to fail until mainlining patches are done).
3. **AnyKernel3 zip** — patches the existing `boot` partition on-device
   using magiskboot (preserves ramdisk, Magisk, cmdline, AVB).

### Flavor system
`FLAVOR="platform-root-profile"` controls 3 config fragment layers:
- **Platform:** `configs/flavors/platform/{aosp,hyperos}.config`
- **Root:** `configs/flavors/root/{noroot,ksu,ksunext,apatch}.config`
- **Profile:** `configs/flavors/profile/{production,gaming,battery,development}.config`

Default: `FLAVOR=aosp-noroot-production`

## Commands
```bash
./build.sh                            # full pipeline (default flavor)
FLAVOR=aosp-ksunext-production ./build.sh
FLAVOR=hyperos-noroot-battery ./build.sh
./build.sh gki                        # only GKI core
./build.sh pack                       # only package
./build.sh clean                      # full wipe

# individual sources (build.sh runs these on demand):
./setup.sh                 # fetch ACK 6.18 LTS + KSU + AnyKernel3
./scripts/vendor-fetch.sh  # fetch Qualcomm marble vendor tree
./scripts/toolchain.sh     # fetch Proton-Clang
./scripts/build-gki.sh     # build GKI core
./scripts/abi-monitor.sh    # enforce KMI stability
./scripts/build-vendor-modules.sh  # build SoC .ko
./scripts/pack-bootimg.sh  # assemble boot.img + vendor_boot + dtbo + AVB
./scripts/config-merge.sh  # merge configs/fragments/* into marble_defconfig
./scripts/patch-apply.sh  # apply patches/series
```

## Lint / typecheck
No JS/TS in this repo. For shell scripts:
```bash
shellcheck setup.sh build.sh scripts/*.sh rootfs/aurora-tune.sh
```

## Layout
See README.md → "Repository layout".

## Defconfig editing
- Edit `configs/marble_defconfig` for permanent base options.
- Put profile-specific options in `configs/fragments/*.config`.
- Never edit `out/.config` directly — re-run `config-merge.sh`.

## Device
- codename: `marble` (POCO F5 / Redmi Note 12 Turbo)
- SoC: SM7475 (Snapdragon 7+ Gen 2)
- Topology: 1× A715 prime + 3× A715 gold + 4× A510 silver

## KernelSU
- Integrated as `drivers/kernelsu/` (copied from KernelSU-Next/kernel by setup.sh).
- Toggle with `KSU=0 ./build.sh`.
- Requires `CONFIG_KPROBES=y` (set in ksu.config fragment).

## KMI / ABI
- Symbol list: `android/abi_gki_aarch64`.
- Enforced by `scripts/abi-monitor.sh` — a removed symbol breaks vendor modules.
- To accept an intentional change: `cp dist/abi_gki_aarch64.extracted android/abi_gki_aarch64`.
