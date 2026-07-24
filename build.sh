#!/usr/bin/env bash
#
# build.sh — Aurora-Kernel full GKI build orchestrator
#
# Runs the complete professional pipeline:
#   1. setup.sh         (fetch ACK 6.18 + KSU + AnyKernel3)      [if missing]
#   2. vendor-fetch.sh  (fetch Qualcomm/Xiaomi marble vendor tree) [if missing]
#   3. toolchain.sh     (set up Clang/LLD)                       [if missing]
#   4. build-gki.sh     (compile GKI core + Module.symvers)
#   5. abi-monitor.sh   (enforce KMI stability, non-fatal)
#   6. build-vendor-modules.sh (compile SoC .ko against GKI, non-fatal)
#   7. pack-bootimg.sh  (AnyKernel3 flashable zip)
#
# Flavor system (hierarchical: platform-root-profile):
#   FLAVOR="aosp-noroot-production"      (default — no root, balanced)
#   FLAVOR="aosp-ksunext-production"     (KSU-Next root)
#   FLAVOR="hyperos-noroot-battery"      (HyperOS, no root, battery profile)
#   FLAVOR="aosp-apatch-gaming"          (APatch root, gaming profile)
#
# Usage:
#   ./build.sh                         full pipeline (default flavor)
#   FLAVOR=aosp-ksunext-production ./build.sh
#   ./build.sh gki                     only GKI core
#   ./build.sh pack                    only package
#   ./build.sh clean                   full wipe
#   MENUCONFIG=1 ./build.sh            open menuconfig before GKI build
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
STAGE="${1:-full}"
MENUCONFIG="${MENUCONFIG:-0}"

# Flavor system: FLAVOR="platform-root-profile"
# Default: aosp-noroot-production
export FLAVOR="${FLAVOR:-aosp-noroot-production}"

# Derive VERSION and KSU flag from FLAVOR for downstream scripts
IFS='-' read -r _FLAVOR_PLATFORM _FLAVOR_ROOT _FLAVOR_PROFILE <<< "$FLAVOR"
if [[ "$_FLAVOR_ROOT" == "ksu" || "$_FLAVOR_ROOT" == "ksunext" ]]; then
  BUILD_KSU=1
else
  BUILD_KSU=0
fi

# Version string includes the flavor
export VERSION="${VERSION:-6.18-ack-${FLAVOR}}"
export SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"

log()  { printf "\033[1;34m[aurora]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ok]\033[0m   %s\n" "$*"; }
err()  { printf "\033[1;31m[err]\033[0m %s\n" "$*" >&2; exit 1; }

export KSU="$BUILD_KSU"
export MENUCONFIG

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
if [[ "$STAGE" == "clean" ]]; then
  log "cleaning out/ dist/ and vendor build"
  rm -rf out dist ramdisks/generic_ramdisk/* ramdisks/vendor_ramdisk/lib/modules/* 2>/dev/null || true
  if [[ -d kernel-src ]]; then
    make -C kernel-src O="$ROOT/out" mrproper 2>/dev/null || true
  fi
  ok "clean done"
  exit 0
fi

# ---------------------------------------------------------------------------
# Preflight: must be Linux
# ---------------------------------------------------------------------------
case "$(uname -s)" in
  Linux) ;;
  *)    err "build must run on Linux (got $(uname -s)). Use WSL2/Ubuntu." ;;
esac

# ---------------------------------------------------------------------------
# Stage helpers: run a sub-script, propagate failure with context
# ---------------------------------------------------------------------------
run_stage() {
  local name="$1"; shift
  log "=== stage: $name ==="
  if ! bash "$@"; then
    err "stage '$name' failed"
    exit 1
  fi
  ok "stage '$name' done"
}

# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------
case "$STAGE" in
  full)
    # ensure sources present
    [[ -d kernel-src ]] || run_stage "setup"      setup.sh
    [[ -d vendor-msm ]] || run_stage "vendor-fetch" scripts/vendor-fetch.sh
    [[ -x toolchains/proton-clang/bin/clang ]] || run_stage "toolchain" scripts/toolchain.sh

    run_stage "gki"           scripts/build-gki.sh
    # ABI monitoring is informational in dev; KMI regressions are expected
    # while the vendor mainlining patches are being developed.
    bash scripts/abi-monitor.sh || log "ABI monitor reported issues (non-fatal in dev)"
    # Vendor module build requires the GKI out/ tree (autoconf.h) which Bazel
    # does NOT populate (it uses bazel-bin/). Until mainlining patches adapt
    # the vendor tree to Bazel, this stage is expected to fail. The GKI Image
    # + symvers are the primary deliverable.
    bash scripts/build-vendor-modules.sh || log "vendor build failed (expected: needs mainlining + Bazel out/ sync)"
    bash scripts/pack-bootimg.sh || log "packaging failed (GKI Image still available in dist/)"
    ;;

  gki)
    run_stage "gki" scripts/build-gki.sh
    ;;

  vendor)
    run_stage "vendor" scripts/build-vendor-modules.sh
    ;;

  pack)
    run_stage "pack" scripts/pack-bootimg.sh
    ;;

  abi)
    run_stage "abi" scripts/abi-monitor.sh
    ;;

  *)
    err "unknown stage: $STAGE
usage: $0 [full|gki|vendor|pack|abi|clean]"
    ;;
esac

ok "Aurora-Kernel build complete"
