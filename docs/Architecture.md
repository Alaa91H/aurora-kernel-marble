# Aurora Kernel: Architecture, Engineering & Governance Specification
# Definitive Master Reference (2026+)

## Aurora Design Identity

Aurora Kernel is engineered around a distinct, uncompromising
architectural philosophy that separates it from standard downstream
distributions:

- **Deterministic Latency Over Peak Benchmarks:** Prioritizes stable frame
  pacing, consistent low-latency response times, and predictable resource
  allocation over synthetic peak benchmark scores.
- **Upstream-First Engineering:** Adheres strictly to mainline Linux
  evolution and standard subsystem patterns, minimizing technical debt.
- **Zero Placebo Tuning:** Eliminates dead configurations, non-functional
  sysctls, and unverified parameters.
- **Android GKI Compliance by Default:** Enforces Android Generic Kernel
  Image (GKI) and Kernel Module Interface (KMI) stability contracts across
  all release targets.
- **Measured Optimization Only:** Validates scheduling, memory, and
  throughput enhancements via empirical tracing and real-world metrics.
- **Minimal Vendor Divergence:** Restricts modifications outside mainline
  Linux and Android Common Kernel (ACK) to tightly scoped, essential
  platform integration layers.
- **Reproducible Builds:** Guarantees deterministic compilation outputs
  through tightly controlled toolchain versions and build environment
  isolation.
- **Long-Term Maintainability:** Designs subsystem modifications to scale
  cleanly across upstream Linux kernel version increments.
- **Observable Behavior Through Tracing:** Mandates robust instrumentation
  via eBPF, ftrace, and perf for every core subsystem.
- **Production-First Stability:** Ensures all configurations undergo
  rigorous regression testing and stress validation prior to release.

## 1. Repository Structure & Architecture Layers

### Repository Layout

```
kernel/
├── drivers/
├── mm/
├── fs/
├── net/
├── security/
├── rust/
├── tools/
├── Documentation/
docs/
├── v1.0/
├── v1.5/
├── v2.0/
├── latest/
├── adr/
├── Architecture.md
└── ...
scripts/
ci/
build/
patches/
vendor/
android/
```

### Architectural & Android Integration Layers

```
[ Applications ]
        │
[ Android Framework ]
        │
[ HAL (Hardware Abstraction Layers) ]
        │
[ Vendor DLKM / KMI Modules ]
        │
[ Aurora Kernel Core Subsystems ]
        │
[ Android Common Kernel (ACK) ]
        │
[ Mainline Linux Core Infrastructure ]
        │
[ ARM64 Architecture & Hardware Extensions ]
        │
[ Underlying SoC Silicon & Hardware ]
```

## 2. Architecture Decision Records (ADR) Framework

Aurora Kernel maintains strict traceability for all architectural choices
within `docs/adr/`:

- `0001-upstream-first.md`: Mandating upstream mainline alignment.
- `0002-no-placebo-tuning.md`: Prohibition of non-functional sysctls and
  placebo settings.
- `0003-preempt-dynamic.md`: Adoption of dynamic preemption for
  responsiveness.
- `0004-enable-mglru.md`: Mandatory integration of Multi-Generational LRU.
- `0005-enable-kcfi.md`: Enforcing Kernel Control Flow Integrity (KCFI).

Each ADR strictly documents: Problem, Alternatives Considered, Decision,
Rationale, and Future Impact.

## 3. Kernel Version Matrix & Feature Lifecycles

### Supported Baselines

- Linux Kernel Baselines: Linux 6.6 LTS, Linux 6.12+ LTS, Linux 6.18 LTS
- Android Common Kernel Baselines: Android 15 ACK (6.6), Android 16 ACK
  (6.12), Android 17 ACK (6.18)
- Target Architecture: ARM64 (AArch64)

### Kernel Feature Lifecycle Matrix

| Feature / Subsystem     | Research | Experimental | Stable | Deprecated | Removed |
|-------------------------|----------|--------------|--------|------------|---------|
| MGLRU (CONFIG_LRU_GEN)  | -        | -            | Yes    | -          | -       |
| DAMON & DAMOS           | -        | -            | Yes    | -          | -       |
| sched_ext               | -        | Yes          | -      | -          | -       |
| Rust-for-Linux Drivers  | Yes      | Yes          | -      | -          | -       |
| Multi-size THP (mTHP)   | -        | -            | Yes    | -          | -       |
| Tasklets                | -        | -            | -      | Legacy     | -       |

## 4. Hardware Capability Matrix

| Hardware Feature / Capability          | Qualcomm (SM8550/8650/8750) | Google Tensor (G4/G5) | MediaTek Flagship |
|----------------------------------------|------------------------------|-----------------------|-------------------|
| Memory Tagging Extension (MTE)         | Yes                          | Yes                   | No                |
| pKVM Protected Virtualization          | Yes                          | Yes                   | No                |
| UFS MCQ (Multi-Circular Queue)          | Yes                          | Yes                   | Partial           |
| AV1 Hardware Decode (Vendor HAL)       | Vendor Supplied              | Vendor Supplied       | Vendor Supplied   |
| Intelligent Power Allocator (IPA)      | Yes                          | Yes                   | Yes               |

## 5. Compatibility, API Evolution & Deprecation Governance

### Compatibility Hierarchy

```
[ Kernel Internal API ]
         ↓
    [ Stable KMI ] (Governed by Android KMI Symbol Lists)
         ↓
  [ Vendor DLKM ]
         ↓
  [ Userspace ABI ]
```

- **Stable Userspace ABI Policy:** Absolute preservation of system call
  boundaries (sysfs, procfs, binder, ioctl). No breaking changes to
  existing userspace-facing interfaces without explicit upstream
  deprecation cycles.
- **Internal API Evolution Policy:** Core internal C functions evolve
  alongside mainline Linux releases. Downstream modules must utilize
  official exported interfaces.
- **Symbol Versioning Policy:** Android KMI contracts govern downstream
  driver linking. `CONFIG_MODVERSIONS` operates as an independent
  compile-time CRC verification safety layer rather than defining KMI
  boundaries directly.

### Deprecation Governance Workflow

```
Experimental → Stable → Deprecated → Hidden → Removed
```

Deprecated interfaces remain marked with `__deprecated` for a mandatory
window of one LTS release cycle before moving to hidden status and final
removal.

## 6. Branch Strategy & Release Engineering

```
main   (Active upstream sync & feature integration)
 │
 ├── next      (Staging integration & integration testing)
 │
 ├── staging   (Experimental features & exploratory drivers)
 │
 ├── rc        (Release Candidate stabilization & gate verification)
 │
 ├── stable    (Production-ready tagged releases)
 │
 └── lts       (Long-term support maintenance & security backports)
```

### Release Engineering & Lifecycle Stages

- **Alpha:** Initial feature-complete build for internal developer
  verification and basic boot validation.
- **Beta:** Broad testing phase deployed to internal validation pools.
- **RC1 / RC2:** Code-frozen candidate builds subjected to full automated
  regression gates, performance benchmarking, and stress testing.
- **Stable:** Production-signed build approved for public consumer
  distribution.
- **Hotfix / Emergency Patch:** Targeted emergency remediation for critical
  regressions or high-severity CVEs.

### Release Manifest Requirements

Every production release must be accompanied by a cryptographically signed
manifest detailing:

- Kernel Version & ACK Version
- Toolchain Version (LLVM/Clang) & KMI Version
- Supported Hardware Target List & DTBO Versions
- Vendor Modules Version & Security Patch Level
- Git Commit Hash & Deterministic Build Checksum (Image.gz hash)

## 7. Boot Architecture & Initialization Levels

### Boot Time Timeline

```
BootROM → Bootloader (UEFI/Fastboot) → Image Verification → Kernel
Decompression → start_kernel()
    ↓
mm_init() → sched_init() → driver_init() → late_initcall() → Init Process
```

### Kernel Initialization Subsystem Levels

- `early_initcall`: Earliest initialization for core architecture setup.
- `core_initcall`: Core kernel subsystems (scheduler, virtual filesystem).
- `postcore_initcall`: Subsystems dependent on core facilities.
- `subsys_initcall`: Bus architectures, power management frameworks.
- `fs_initcall`: Filesystem registration and caching initialization.
- `device_initcall`: Peripheral hardware drivers and platform probes.
- `late_initcall`: Final driver initialization and async init tasks.

## 8. Memory Architecture & Reclaim Pipeline

```
[ Page Fault ] → [ Page Allocator (Buddy) ] → [ Memory Pressure ]
    → [ kswapd Background Reclaim ]
    → [ Multi-Generational LRU (MGLRU) ]
    → [ DAMON / DAMOS Proactive Compaction ]
    → [ Memory Compaction ]
    → [ OOM Killer ]
```

- **Buddy System & SLUB:** Manages physical page frames and kernel object
  caching.
- **vmalloc & CMA:** Allocates non-contiguous virtual spaces and contiguous
  physical memory blocks for multimedia and camera pipelines.

## 9. CPU Topology Model, Concurrency & Locking

### CPU Topology & EAS Integration

```
CPU Core → Cluster → Perf vs Eff Core → CPU Capacity → Energy Model
```

- **NUMA / UMA Policy:** ARM64 mobile SoC as NUMA Neutral / UMA Supported,
  clean multi-cluster scheduling without artificial NUMA fragmentation.

### Concurrency Model

- **Interrupt Context (Hard IRQ):** Non-blocking; sleeping and blocking
  allocations strictly prohibited.
- **SoftIRQ / Workqueues / Threaded IRQs:** Deferred processing via CMWQ
  workqueues and dedicated threaded IRQs. Tasklets are legacy, phased out.
- **RCU Callbacks:** Asynchronous memory reclamation upon grace period
  completion.

### Locking Model

- **Mutex / RT-Mutex:** Sleepable process-context locking.
- **Spinlocks:** Non-blocking busy-wait for schedulers and hard-IRQ.
- **RW Semaphores & Seqlocks:** Read-write optimization.
- **RCU & Atomic Operations:** Lockless traversal and refcounting.

## 10. Interrupt Architecture & Observability

### IRQ Architecture

- **GICv3 & IRQ Domains:** ARM GIC v3 routing with hardware-to-virtual
  interrupt translation.
- **MSI-X & IPI:** Message Signaled Interrupts for PCIe/storage; IPI for
  core synchronization and TLB invalidation.
- **NAPI Polling:** Interrupt mitigation for networking under heavy load.

### Observability Pipeline

```
[ User Apps / Telemetry ] → [ bpftrace / perf ] → [ BPF LSM & Programs ]
    → [ eBPF JIT ] → [ perf Event Subsystem ] → [ ftrace / tracefs ]
    → [ Core Tracepoints ]
```

## 11. Security Governance, Threat Model & AI Policy

### Security Threat Model & Mitigations

- **Control Flow Integrity:** KCFI (`CONFIG_CFI_CLANG`) to mitigate ROP and
  branch target hijacking.
- **Memory Safety:** Hardware MTE (`CONFIG_ARM64_MTE`) and KFENCE for
  use-after-free and out-of-bounds detection.
- **Isolation & Hardening:** ARM SMMUv3 IOMMU isolation, SELinux MAC,
  PAN/EPAN execution prevention.

### Security Audit, Syzkaller & Bug Bounty Readiness

- **Continuous Fuzzing:** Automated kernel fuzzing via syzkaller / syzbot.
- **Crash Triage & Bisection:** Automated crash reporting and auto-bisection
  with cryptographically linked reproducer archives.
- **Responsible Disclosure:** Standard 90-day vulnerability disclosure SLA.

### AI-Assisted Development Policy

AI-assisted code generation is permitted for routine boilerplate,
documentation, and unit tests. All AI-generated code must:

- Undergo rigorous manual peer review by subsystem maintainers.
- Satisfy all CI compilation, KUnit, and kselftest verification gates.
- Conform strictly to the Linux Kernel Coding Style.
- Meet upstream quality and architectural design standards.

## 12. Coding Standards, Toolchains & Build Reproducibility

- **Style Guide:** Strict adherence to Linux Kernel Coding Style
  (`Documentation/process/coding-style.rst`).
- **Toolchain Policy:** Primary compilation via LLVM/Clang (Versions 21/22
  and AOSP Clang toolchain r612) with KCFI hardening. GNU GCC unsupported
  for production builds.
- **Build Verification Tools:** pahole (BTF), libbpf, bpftool, objtool.

### Build Reproducibility Policy

- `SOURCE_DATE_EPOCH` enforced to freeze build timestamps.
- Deterministic archive creation and BTF generation.
- Fixed LLVM and stable pahole version pinning.
- Reproducible DWARF generation and identical Image.gz checksum
  verification.

## 13. Testing Infrastructure & Regression Dashboards

### Testing Classification

- **Unit Testing:** KUnit (in-kernel unit testing).
- **Integration Testing:** kselftest (subsystem selftest suites).
- **Performance Testing:** perf, cyclictest, hwlatdetect.
- **Stress Testing:** stress-ng, hackbench, fio.
- **Security & Fuzzing:** LKDTM, syzkaller, syzbot.

### Regression Dashboard Gates

```
Build → Boot → Suspend → Memory → Scheduler → Networking → Thermals → Battery → Release
```

## 14. Vendor BSP Governance & Technical Debt Policy

### Vendor BSP Governance

- **Allowed:** SoC-specific drivers (`drivers/soc/qcom/`), DeviceTree files,
  firmware loaders, clock/power domain controllers.
- **Strict Rejection:** Out-of-tree modifications to core scheduling,
  virtual memory, VFS filesystems, or IPC mechanisms are systematically
  blocked.

### Technical Debt Policy

- No duplicated subsystems or downstream core replacements.
- Zero dead code, unreferenced sysctls, or abandoned orphan patches.

## 15. Rust Governance & Configuration Philosophy

### Rust Governance

- Staging adoption of Rust-for-Linux for isolated drivers where upstream
  bindings exist.
- All `unsafe` blocks must document memory safety invariants explicitly.
- FFI boundaries must maintain strict type safety.

### Configuration Decision Tree (CONFIG_*)

```
Should this configuration option be enabled?
├── Core security baseline / mandatory hardware feature? ─► [ =y ] (Built-in)
├── Optional modular component / specialized driver?      ─► [ =m ] (Module)
├── Diagnostic, KASAN, or debugging tool?                 ─► [ Debug Only ]
├── Specific to an external vendor SoC?                  ─► [ Vendor Only ]
└── Experimental or unverified?                           ─► [ =n ] (Disabled)
```

## 16. Formal Optimization Governance

Any proposed optimization patch must satisfy all ten governance criteria
before merging:

1. **Measurable:** Backed by empirical benchmark data.
2. **Reproducible:** Verifiable across multiple test runs and hardware.
3. **Upstream-Compatible:** Aligned with mainline design patterns.
4. **Maintainable:** Clear code structure, low debt, documented.
5. **No ABI Impact:** Zero unauthorized userspace or KMI changes.
6. **No Thermal Regression:** Verified under sustained loads.
7. **No Battery Regression:** Idle/active power within margin of error.
8. **No Scheduler Fairness Regression:** Does not starve background tasks.
9. **Verified on Two Platforms:** Tested on at least two hardware targets.
10. **Documented Before Merge:** Accompanied by architecture docs or ADR.

## 17. Versioned Roadmap

- **Aurora 1.0 (Baseline Foundation):** Linux 6.6 LTS core, MGLRU default,
  Android 15 GKI compliance, core security hardening (KCFI, MTE).
- **Aurora 1.5 (Advanced Optimization):** Linux 6.12 LTS features, mTHP
  tuning, UFS MCQ parallelism, expanded eBPF observability.
- **Aurora 2.0 (Next-Gen Scheduling & Isolation):** sched_ext policy
  evaluation, pKVM hardening, fine-grained power domain predictability.
- **Aurora 3.0 (Autonomous & Secure Core):** Full upstream sync, Rust
  drivers, AI-driven thermal-power balancing.

> **Current status:** Phase 1 (Aurora 1.0 baseline) — ACK 6.18 LTS fetch
> and Bazel/kleaf GKI build verified working on CI; vendor mainlining
> (5.10 → 6.18) is the active engineering task.

## 18. Features Outside Kernel Scope

Aurora Kernel intentionally excludes userspace frameworks and peripheral
firmware from the kernel image:

- Camera image processing / Camera HAL
- Audio HAL / Dolby Atmos / Dirac processing
- Display HAL / SurfaceFlinger / ART Runtime
- AI image enhancement / Vendor GPU userspace drivers
- Wi-Fi, Bluetooth, Modem, and Touch firmware

These are managed by Android userspace, proprietary vendor software, or
platform firmware. Aurora Kernel provides solely the foundational kernel
infrastructure.

## 19. Aurora Optimization Strategy

- **Latency Optimization:** Minimizes scheduler domain round-trip times,
  interrupt handling latency via thread IRQs, and RCU callback offloading.
- **Throughput Optimization:** High-performance blk-mq scheduling, UFS MCQ
  parallelism, asynchronous io_uring, multi-queue networking.
- **Energy Optimization:** EAS topologies, utilization clamping
  (`CONFIG_UCLAMP_TASK`), DVFS, granular subsystem power domains.
- **Thermal Stability:** Intelligent Power Allocator (IPA) thermal zones and
  adaptive frequency capping.
- **Memory Efficiency:** MGLRU (`CONFIG_LRU_GEN`), DAMON/DAMOS proactive
  compaction, zRAM compressed block storage.
- **Storage Efficiency:** F2FS garbage collection, inline encryption
  offloading, page cache writeback throttling.
- **Scheduler Fairness:** EEVDF with task latency weighting and core
  scheduling isolation.
- **Sustained Gaming Performance:** Thermal pressure inputs, interconnect
  bandwidth voting (ICC QoS, LLCC QoS), frequency governor tuning.
- **Battery Preservation:** Deep sleep (Suspend-to-Idle), network packet
  batching, idle CPU tick reduction.
- **Security-by-Default:** Hardware memory safety (MTE), CFI (KCFI), kernel
  lockdown, SELinux MAC.
