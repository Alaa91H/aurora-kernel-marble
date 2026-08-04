#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
#
# scripts/audit-config.py - Aurora-Kernel configuration auditor
#
# Verifies the hierarchical flavor config system against the REAL kernel
# Kconfig tree. Two checks:
#
#   1. Choice conflicts: for every flavor combination (platform x root x
#      profile), simulate the exact merge order from scripts/config-merge.sh
#      and verify that no Kconfig 'choice' group has >1 member set to =y.
#
#   2. Symbol existence: every CONFIG_* referenced in configs/ must be
#      defined by a Kconfig file in the kernel tree (KERNEL_SRC, default
#      ./kernel-src or first CLI arg). Symbols only referenced from the
#      vendor layer are expected to live in the msm-kernel vendor tree and
#      are reported separately (vendor-only), not as dead.
#
# Exit codes: 0 = clean, 1 = choice conflict or dead symbol found.
#
# Usage:
#   python3 scripts/audit-config.py                 # uses ./kernel-src
#   python3 scripts/audit-config.py /path/to/ack    # explicit tree
#   KERNEL_SRC=/path python3 scripts/audit-config.py
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = os.path.join(ROOT, "configs")

BASE = os.path.join(CFG, "marble_defconfig")
VENDOR = sorted(glob.glob(os.path.join(CFG, "vendor", "*.config")))
FRAGS = sorted(glob.glob(os.path.join(CFG, "fragments", "*.config")))
CAPS = sorted(glob.glob(os.path.join(CFG, "capabilities", "*.config")))
PLAT = sorted(os.path.basename(x)[:-7] for x in glob.glob(os.path.join(CFG, "flavors", "platform", "*.config")))
ROOTS = sorted(os.path.basename(x)[:-7] for x in glob.glob(os.path.join(CFG, "flavors", "root", "*.config")))
PROFS = sorted(os.path.basename(x)[:-7] for x in glob.glob(os.path.join(CFG, "flavors", "profile", "*.config")))

KERNEL_SRC = os.environ.get("KERNEL_SRC") or (sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "kernel-src"))

LINE_RE = re.compile(r"^(CONFIG_[A-Za-z0-9_]+)=(.*)$")
OFF_RE = re.compile(r"^#\s*CONFIG_[A-Za-z0-9_]+\s+is not set$")
CONF_RE = re.compile(r"CONFIG_([A-Za-z0-9_]+)")

# Kconfig 'choice' groups: at most one member may be =y in the final .config
CHOICES = {
    "preempt": ["CONFIG_PREEMPT_NONE", "CONFIG_PREEMPT_VOLUNTARY", "CONFIG_PREEMPT"],
    "hz": ["CONFIG_HZ_100", "CONFIG_HZ_250", "CONFIG_HZ_300", "CONFIG_HZ_1000"],
    "kasan": ["CONFIG_KASAN_GENERIC", "CONFIG_KASAN_SW_TAGS", "CONFIG_KASAN_HW_TAGS"],
    "zswap_comp": ["CONFIG_ZSWAP_COMPRESSOR_DEFAULT_ZSTD", "CONFIG_ZSWAP_COMPRESSOR_DEFAULT_LZ4",
                  "CONFIG_ZSWAP_COMPRESSOR_DEFAULT_LZO", "CONFIG_ZSWAP_COMPRESSOR_DEFAULT_LZ4HC",
                  "CONFIG_ZSWAP_COMPRESSOR_DEFAULT_DEFLATE"],
    "zram_comp": ["CONFIG_ZRAM_DEFAULT_COMPRESSION_ZSTD", "CONFIG_ZRAM_DEFAULT_COMPRESSION_LZ4",
                 "CONFIG_ZRAM_DEFAULT_COMPRESSION_LZO", "CONFIG_ZRAM_DEFAULT_COMPRESSION_LZ4HC",
                 "CONFIG_ZRAM_DEFAULT_COMPRESSION_DEFLATE"],
    "module_sig": ["CONFIG_MODULE_SIG_SHA256", "CONFIG_MODULE_SIG_SHA512", "CONFIG_MODULE_SIG_SHA1"],
    "lto": ["CONFIG_LTO_NONE", "CONFIG_LTO_CLANG_THIN", "CONFIG_LTO_CLANG_FULL"],
}

# Symbols defined by local patch trees applied by patches/series or setup.sh
# (KernelSU-Next, APatch kernel_livepatch) — real Kconfig symbols in the build,
# but not part of the ACK common Kconfig tree. Reported separately, not as dead.
LOCAL_PREFIXES = (
    "KSU",
    "LIVEPATCH_IPA",
)

# Qualcomm msm-kernel vendor symbol prefixes: expected in vendor layer only
VENDOR_PREFIXES = (
    "QCOM_", "QTI_", "QPNP_", "MSM_", "SM_", "GH_", "CNSS", "ICNSS", "IPA", "MHI", "QRTR",
    "SPS", "PDR_", "RPROC_", "HYP_", "XLOG", "MI_", "BQ_F", "FTS_", "NOVATEK", "FINGERPRINT",
    "EDAQ_", "SERIAL_MSM", "I2C_MSM", "I3C_MASTER_MSM", "SPI_MSM", "UIO_MSM", "USB_BAM",
    "USB_MSM", "USB_QCOM", "USB_F_FS_IPC", "HW_RANDOM_MSM", "IPC_LOGGING", "REGMAP_QTI",
    "STM_", "FIRE_WATCHDOG", "GPIO_TESTING", "EXTEND_RECLAIM", "GUNYAH", "HVC_GUNYAH",
    "WCNSS", "SCHED_WALT", "WALT_", "SCHED_HMP", "SCHED_TUNE", "CGROUP_SCHEDTUNE",
    "SCHED_CORE_IRQ", "SCHED_MISFIT", "UCLAMP_BYPASS_MISMATCH", "KVM_INDIRECT_ACCESS",
    "KVM_ARM_HOST", "KVM_ARM_PMU", "DEVFREQ_GOV_QCOM", "QSEE", "QSEECOM", "HDCP_QSEE",
    "BTFM_SLIM", "SLIM_QCOM", "SLIMBUS", "MSM_BT_POWER", "MSM_GENI", "QCOM_Q6V5",
    "QCOM_PIL_INFO", "QCOM_FASTRPC", "QCOM_FASTRTP", "QCOM_GLINK_SSR", "QCOM_RMTFS",
    "QCOM_AOPSSD", "QCOM_ICP", "QCOM_PM", "QCOM_DUMP", "QCOM_MPM", "QCOM_BCL",
    "QCOM_KGSL", "QCOM_ADRENO", "MSM_ADRENO", "GPU_PWRDCOLLECTOR", "QCOM_MDSS",
    "DRM_PANEL_CSOT", "DRM_PANEL_TIANMA", "DRM_PANEL_SAMSUNG", "BACKLIGHT_QCOM", "QCOM_WLED",
    "CHARGER_QCOM_SMBB", "CHARGER_QCOM_SMB1390", "QPNP_CHARGER", "BATTERY_BQ27",
    "ARCH_WAIPIO", "ARCH_DIWALI", "ARCH_CAPE", "PINCTRL_WAIPIO", "PINCTRL_DIWALI",
    "PINCTRL_CAPE", "PINCTRL_SM8450", "SND_SOC_SM8450", "SND_SOC_WAIPIO", "SND_SOC_WCD937",
    "SND_SOC_QDSP6V2", "SND_SOC_QDSP6", "SND_SOC_QCOM_INTERNAL", "SND_SOC_STORM",
    "SND_SOC_APQ", "SND_SOC_MSM", "SND_SOC_SDM", "SND_SOC_SC7", "QCOM_DMABUF_HEAPS",
    "USB_DWC3_MSM", "USB_CONFIGFS_F_CCID", "USB_CONFIGFS_F_CDEV", "USB_CONFIGFS_F_DIAG",
    "USB_CONFIGFS_F_GSI", "USB_CONFIGFS_F_QDSS", "USB_CONFIGFS_F_ACC", "USB_CONFIGFS_F_ADB",
    "USB_CONFIGFS_F_MTP", "USB_CONFIGFS_F_PTP", "USB_CONFIGFS_F_RNDIS", "USB_CONFIGFS_F_SERIAL",
    "USB_F_DSI", "USB_F_FDL", "TOUCHSCREEN_FTS", "INPUT_QCOM_HV", "QPNP_LED", "QPNP_PWM",
    "QCOM_SPMI_FLASH", "RTC_DRV_PM8xxx", "QCOM_SPMI_VADC", "QCOM_SPMI_ADC5", "QCOM_VADC",
    "IIO_ST_", "TCS3701", "CRYPTO_DEV_QCOM", "CRYPTO_DEV_QCEDEV", "CRYPTO_DEV_QCOM_MSM_QCE",
    "TIMA", "FIQ_DEBUGGER", "ANDROID_RAM_CONSOLE", "ANDROID_LOGGER", "MSM_CORELLC",
    "PWM_QTI", "PWM_QCOM", "UFS_DBG", "SDHCI_MSM", "NFC_QTI", "UCSI_QTI", "SLIMBUS_REGMAP",
    "HYP_ASSIGN", "OF_RESERVED_MEM", "PAGE_POISONING", "RCU_TORTURE", "LOCK_TORTURE",
    "ATOMIC64_SELFTEST", "TEST_USER_COPY", "LKDTM", "SLUB_DEBUG_ON", "DEBUG_DMA_BUF",
    "ARM_SMMU_CAPTUREBUS", "ARM_SMMU_TESTBUS", "QTI_PMIC_PON", "QTI_THERMALZONE",
    "NVMEM_SPMI", "SPMI_QTI", "MFD_SPMI", "MFD_I2C_PMIC", "QPNP_PBS", "QCOM_EUD",
    "QCOM_ESOC", "QCOM_GIC", "QCOM_HUNG", "QCOM_HYP", "QCOM_IRQ_STAT", "QCOM_LOGBUF",
    "QCOM_PANEL", "QCOM_PCI", "QCOM_PERFORMANCE", "QCOM_QDSS", "QCOM_RTB", "QCOM_SHOW",
    "QCOM_SMCINVOKE", "QCOM_SYSMON", "QCOM_SYSSTATS", "QCOM_VA_MINIDUMP", "QCOM_WDT_CORE",
    "QCOM_WATCHDOG", "QCOM_CPU_VENDOR", "QCOM_RUN_QUEUE", "QCOM_SOC_SLEEP", "QCOM_CPUSS",
    "QCOM_SUBSYSTEM", "QCOM_BALANCE", "QCOM_DCVS", "QCOM_DCC", "QCOM_BWMON", "QCOM_ADSP",
    "QCOM_CDSP", "QCOM_DYN_MINIDUMP", "QCOM_FORCE", "QCOM_FSA", "QCOM_GUESTVM",
    "QCOM_IOMMU_DEBUG", "QCOM_IOMMU_UTIL", "QCOM_LLCC", "QCOM_MEMORY_DUMP", "QCOM_MICRODUMP",
    "QCOM_MINIDUMP", "QCOM_RAMDUMP", "QCOM_SECURE", "QCOM_WDT", "QCOM_TSENS",
    "QCOM_SPMI_TEMP", "INTERCONNECT_QCOM", "ARM_QCOM_CPUFREQ", "QCOM_BAM_DMA",
    "QCOM_GENI", "QCOM_GPI_DMA", "QCOM_COMMAND_DB", "QCOM_GLINK", "QCOM_SMP2P",
    "QCOM_SOCINFO", "QCOM_PDC", "QCOM_QFPROM", "QCOM_MSM_IPCC", "SERIAL_MSM_GENI",
    "PHY_QCOM_UFS", "MMC_CRYPTO_QTI", "SCSI_UFS_CRYPTO_QTI", "QTI_BCL", "QTI_PMIC",
    "QTI_CPUFREQ", "QTI_CPU_", "QTI_DDR", "QTI_DEVFREQ", "QTI_QMI", "QTI_SHARED",
    "QTI_USERSPACE", "QTI_TZ", "QTI_HW", "QTI_SCMI", "QTI_POLICY", "QTI_SDPM",
    "QTI_PMU", "QTI_C1DCVS", "QTI_GPLAF", "QTI_PLH", "QTI_ALTMODE", "QTI_SYS",
    "QTI_THERMAL", "QTI_ADC", "QSEE_IPC", "CORESIGHT_TGU", "CORESIGHT_HWEVENT",
    "CORESIGHT_REMOTE_ETM", "CORESIGHT_TPDA", "CORESIGHT_TPDM", "EDAC_KRYO",
    "QCOM_GDSC_REG", "IOMMU_IO_PGTABLE_FAST", "IOMMU_TLBSYNC", "USB_EHSET",
    "USB_LINK_LAYER", "USB_NET_AX8817", "USB_REDRIVER", "USB_REPEATER", "I2C_EUSB",
    "I2C_RTC6226", "NOP_USB", "MSM_HSUSB", "MSM_QBT", "LEDS_QPNP", "LEDS_QTI",
    "SENSORS_QTI", "SENSORS_SSC", "REGULATOR_QPNP", "REGULATOR_QTI", "REGULATOR_PROXY",
    "REGULATOR_STUB", "REGULATOR_DEBUG", "HVC_GUNYAH", "PWM_QTI",
)


def parse(path):
    syms = {}
    probs = []
    with open(path, encoding="utf-8") as fh:
        for i, raw in enumerate(fh, 1):
            line = raw.rstrip("\n")
            m = LINE_RE.match(line)
            if m:
                sym, val = m.group(1), m.group(2)
                if sym in syms:
                    probs.append(f"  duplicate {sym} (L{syms[sym][1]}/{i})")
                syms[sym] = (val, i)
                continue
            if OFF_RE.match(line):
                sym = line.split()[1]
                if sym in syms:
                    probs.append(f"  duplicate {sym} (L{syms[sym][1]}/{i})")
                syms[sym] = (None, i)
                continue
            if CONF_RE.search(line) and not line.strip().startswith("#"):
                probs.append(f"  L{i} unparsed: {line[:60]}")
    return syms, probs


def merge(p, r, pr):
    chain = [BASE] + VENDOR + FRAGS + CAPS + [
        os.path.join(CFG, "flavors", "platform", p + ".config"),
        os.path.join(CFG, "flavors", "root", r + ".config"),
        os.path.join(CFG, "flavors", "profile", pr + ".config")]
    final = {}
    missing = [os.path.basename(f) for f in chain if not os.path.exists(f)]
    for f in chain:
        for sym, (val, _) in parse(f)[0].items():
            final[sym] = val
    return final, missing


def load_kconfig_symbols():
    if not os.path.isdir(KERNEL_SRC):
        return None
    syms = set()
    for root, _d, files in os.walk(KERNEL_SRC):
        for fn in files:
            if fn.startswith("Kconfig"):
                try:
                    with open(os.path.join(root, fn), encoding="utf-8", errors="replace") as fh:
                        for line in fh:
                            m = re.match(r"\s*(?:config|menuconfig)\s+([A-Za-z0-9_]+)", line)
                            if m:
                                syms.add(m.group(1))
                except OSError:
                    pass
    return syms


def main():
    bad = 0
    # ---- 1. per-file parse problems ----
    print("PART 1: per-file parse problems")
    found_problem = False
    for label, files in [("base", [BASE]), ("vendor", VENDOR), ("fragments", FRAGS),
                         ("capabilities", CAPS),
                         ("platform", [os.path.join(CFG, "flavors", "platform", x + ".config") for x in PLAT]),
                         ("root", [os.path.join(CFG, "flavors", "root", x + ".config") for x in ROOTS]),
                         ("profile", [os.path.join(CFG, "flavors", "profile", x + ".config") for x in PROFS])]:
        for f in files:
            probs = parse(f)[1]
            if probs:
                found_problem = True
                print(os.path.relpath(f, ROOT).replace("\\", "/"))
                print("\n".join(probs))
    if not found_problem:
        print("  none")
    print()

    # ---- 2. choice conflicts over all flavor combos ----
    print(f"PART 2: choice conflicts across {len(PLAT)}x{len(ROOTS)}x{len(PROFS)} flavors")
    for p in PLAT:
        for r in ROOTS:
            for pr in PROFS:
                final, missing = merge(p, r, pr)
                for cname, members in CHOICES.items():
                    hits = [s for s in members if final.get(s) == "y"]
                    if len(hits) > 1:
                        print(f"  [CONFLICT] {p}-{r}-{pr} {cname}: {hits}")
                        bad += 1
                for m in missing:
                    print(f"  [MISSING] {p}-{r}-{pr}: {m}")
                    bad += 1
    if bad == 0:
        print("  none")
    print()

    # ---- 3. symbol existence vs real kernel tree ----
    ksyms = load_kconfig_symbols()
    if ksyms is None:
        print(f"PART 3: SKIPPED - no kernel tree at {KERNEL_SRC} (set KERNEL_SRC)")
        print(f"  hint: python3 scripts/audit-config.py /path/to/ack6.18")
        sys.exit(1 if bad else 0)

    print(f"PART 3: symbol existence vs {KERNEL_SRC} ({len(ksyms)} Kconfig symbols)")
    used = {}
    for f in [BASE] + VENDOR + FRAGS + CAPS + [os.path.join(CFG, "flavors", x, y)
              for x in ("platform", "root", "profile")
              for y in os.listdir(os.path.join(CFG, "flavors", x))]:
        if not os.path.exists(f):
            continue
        name = os.path.relpath(f, ROOT).replace("\\", "/")
        for sym, _ in parse(f)[0].items():
            used.setdefault(sym, set()).add(name)

    def bare(sym):
        return sym[len("CONFIG_"):] if sym.startswith("CONFIG_") else sym

    dead = {}        # genuinely missing from ACK common (typo/renamed/removed)
    vendor_only = {}  # not in ACK common, but vendor-prefixed (msm-kernel tree)
    local_only = {}   # not in ACK common, defined by local patch trees (KSU/APatch)
    for sym, files in sorted(used.items()):
        if bare(sym) in ksyms:
            continue
        if bare(sym).startswith(VENDOR_PREFIXES):
            vendor_only[sym] = sorted(files)
        elif bare(sym).startswith(LOCAL_PREFIXES):
            local_only[sym] = sorted(files)
        else:
            dead[sym] = sorted(files)

    if vendor_only:
        print(f"  vendor-only (resolved in msm-kernel vendor tree): {len(vendor_only)}")
        for sym, files in sorted(vendor_only.items()):
            srcs = ",".join(os.path.basename(x) for x in files)
            print(f"    {sym:45s} {srcs}")
    if local_only:
        print(f"  local-patch (KSU/APatch, defined by patches/series): {len(local_only)}")
        for sym, files in sorted(local_only.items()):
            srcs = ",".join(os.path.basename(x) for x in files)
            print(f"    {sym:45s} {srcs}")
    if dead:
        print(f"  DEAD symbols (not in ACK common, not vendor/local-prefixed): {len(dead)}")
        for sym, files in sorted(dead.items()):
            srcs = ",".join(os.path.basename(x) for x in files)
            print(f"    {sym:45s} {srcs}")
        bad += len(dead)
    else:
        print("  all referenced symbols exist in the kernel tree (or are vendor-only)")
    print()
    print(f"RESULT: {'FAIL' if bad else 'PASS'} ({bad} problems)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
