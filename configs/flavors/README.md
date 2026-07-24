# configs/flavors/README.md
#
# Aurora-Kernel Flavor System — Hierarchical Build Variants
#
# Instead of maintaining separate branches per variant, Aurora uses a
# 3-layer flavor matrix merged on top of the GKI core defconfig:
#
#   Core (marble_defconfig + fragments/*.config)
#     ↓
#   Platform Layer  (aosp | hyperos)
#     ↓
#   Root Layer      (noroot | ksu | ksunext | apatch)
#     ↓
#   Profile Layer   (production | gaming | battery | development)
#     ↓
#   Final .config
#
# Usage:
#   FLAVOR="aosp-ksunext-production" ./build.sh
#   FLAVOR="hyperos-noroot-battery"  ./build.sh
#
# The build script parses FLAVOR into 3 components and merges:
#   configs/flavors/platform/<platform>.config
#   configs/flavors/root/<root>.config
#   configs/flavors/profile/<profile>.config
# on top of the base defconfig + core fragments.
#
# If FLAVOR is not set, defaults to: aosp-noroot-production

## Directory layout:
#
# configs/flavors/
# ├── platform/
# │   ├── aosp.config
# │   └── hyperos.config
# ├── root/
# │   ├── noroot.config
# │   ├── ksu.config
# │   ├── ksunext.config
# │   └── apatch.config
# └── profile/
#     ├── production.config
#     ├── gaming.config
#     ├── battery.config
#     └── development.config
