# Aurora Kernel — Architecture & Engineering Specification

> **Status:** Governing document. This spec defines the target architecture.
> Implementation is incremental; each subsystem is added only when it
> genuinely exists (no placeholder stubs). See `ROADMAP.md` for phases.
>
> **Repository:** https://github.com/Alaa91H/aurora-kernel-marble

---

## Vision

Aurora Kernel is **not** a traditional custom Android kernel.

Aurora is a next-generation Android Kernel Platform designed around:

- Linux 6.18 LTS
- Android Common Kernel (ACK)
- Generic Kernel Image (GKI)
- Upstream-first development
- Enterprise-grade architecture
- Long-term maintainability
- Modular engineering
- Production stability
- Security-first design
- Vendor-independent architecture
- High scalability
- Automated engineering

The objective is to create a kernel platform that can be maintained and
expanded for many years while minimizing technical debt and simplifying
migration to future Linux LTS releases.

---

## Engineering Principles

Every subsystem must satisfy:

- Upstream First
- Modular Design
- Layered Architecture
- Stable Internal APIs
- Clean Code
- Minimal Patchset
- Zero Vendor Pollution
- High Test Coverage
- Security by Default
- Performance by Measurement
- Documentation Driven Development
- Continuous Integration
- Continuous Benchmarking
- Continuous Security Auditing
- Backward Compatibility where practical
- Forward Compatibility planning

---

## Aurora Platform Architecture

```
Aurora Platform
├── Aurora Core
├── Aurora Android Layer
├── Aurora Vendor Framework
├── Aurora Device Framework
├── Aurora Performance Framework
├── Aurora Security Framework
├── Aurora Memory Framework
├── Aurora Power Framework
├── Aurora Scheduler Framework
├── Aurora Filesystem Framework
├── Aurora Networking Framework
├── Aurora Build Framework
├── Aurora Testing Framework
├── Aurora Benchmark Framework
├── Aurora Documentation Framework
├── Aurora SDK
├── Aurora Toolchain
└── Aurora CI/CD
```

---

## Layered Design

```
Layer 1 — Linux 6.18 LTS
Layer 2 — Android Common Kernel
Layer 3 — Aurora Core
Layer 4 — Vendor Support Packages
Layer 5 — Device Support Packages
Layer 6 — User Build Profiles
```

No subsystem may bypass its designated layer.

---

## Aurora Core

Aurora Core contains only generic kernel functionality. Must remain
vendor-neutral.

Subsystems: Scheduler, Memory Management, Process Management, Virtual
Memory, Security, Networking, Block Layer, Filesystems, Power Management,
ARM64 Architecture, Interrupt Management, Synchronization, Kernel
Infrastructure, eBPF, io_uring, Workqueues, Timers, Tracing, Debug
Infrastructure.

---

## Android Layer

Complete Android compatibility: Binder, BinderFS, Android ABI, GKI,
Incremental FS, dm-verity, fs-verity, SELinux, Android Tracepoints,
Android Memory Hooks, Android Boot Requirements, Vendor Module Interface.

---

## Vendor Framework

Independent vendor packages. Supported: Qualcomm, MediaTek, Samsung
Exynos, Google Tensor, Unisoc, future vendors. Vendor-specific code must
never be placed inside Aurora Core.

---

## Device Framework

Each device is an isolated package: Device Tree, Panel, Touch, Camera,
Sensors, Battery, Charging, Thermal, Fingerprint, Audio. No generic
logic here.

Examples: marble, mondrian, houji, garnet, future devices.

---

## Plugin Architecture

Every feature should be loadable, replaceable, or configurable through a
modular subsystem whenever feasible. Categories: Scheduler, Memory,
Filesystem, Networking, Security, Power, Thermals, Debug, Tracing,
Vendor Extensions, Performance, AI Optimizations.

---

## Stable Internal APIs

Scheduler API, Memory API, Filesystem API, Vendor API, Security API,
Power API, Driver API, Device API, Benchmark API, Telemetry API.

---

## Feature Registry

Every feature includes: Feature ID, Version, Owner, Subsystem,
Dependencies, Kernel Compatibility, Android Compatibility, ABI Status,
Security Impact, Performance Impact, Power Impact, Documentation, Review
Status, Test Coverage.

---

## Capability Framework

Centralized capability declarations replacing scattered `#ifdef`:
Supports GKI, Rust, MGLRU, DAMON, io_uring, WireGuard, eBPF,
PREEMPT_DYNAMIC, BTF, KCFI.

---

## Scheduler Framework

EEVDF, Energy-Aware Scheduling, CPU Topology Awareness, Load Balancing,
IRQ Affinity, Latency Optimizations, Background Task Optimization,
Foreground Priority Optimization, Gaming Optimizations, Power Efficient
Scheduling.

---

## Memory Framework

MGLRU, DAMON, zram, zswap, Memory Compaction, Memory Tiering, Page
Reclaim Improvements, Page Cache Optimizations, Huge Pages, Transparent
Huge Pages, CMA Optimizations, NUMA (where applicable), Readahead
Optimizations.

---

## Filesystem Framework

EXT4, F2FS, EROFS, OverlayFS, Incremental FS, fs-verity, dm-verity,
Inline Encryption, Compression Optimizations, Storage Integrity.

---

## Storage Framework

UFS, Block Layer, I/O Scheduler, io_uring, Queue Management, Read
Ahead, Writeback, Low Latency Storage.

---

## Networking Framework

WireGuard, eBPF, BTF, XDP (where supported), Modern TCP Stack, IPv6,
Congestion Control Algorithms (Linux 6.18), Socket Optimizations,
Network Namespaces, QoS Hooks.

---

## Power Framework

Suspend, Resume, cpufreq, cpuidle, Devfreq, Thermal Framework, Battery
Efficiency, Charging Policies, Idle States, Energy-Aware Scheduling.

---

## Security Framework

SELinux, Kernel Lockdown, KASLR, Stack Protector Strong, Hardened
Usercopy, CFI/KCFI (where supported), Shadow Call Stack (where
supported), Init Stack, PAN, BTI (ARM64), Pointer Authentication (where
hardware supports), Speculative Execution Mitigations, Latest CVE Fixes,
Security Auditing, Runtime Integrity.

> **Never disable security features solely for benchmark gains.**

---

## Performance Framework

Monitor: CPU, GPU, Memory, Storage, Network, Battery, Thermals,
Scheduler, Latency, Frame Time, Boot Time, Power Consumption.

---

## Benchmark Framework

Run automatically after each merge: Micro, Macro, Gaming, Compilation,
Filesystem, Network, Power, Thermals, Boot, Memory. Regression Detection.

> Reject merges that introduce measurable regressions unless explicitly
> approved.

---

## Testing Framework

KUnit, LKDTM, KASAN, KFENCE, KCSAN, UBSAN, Lockdep, Sparse, Smatch,
Clang Static Analyzer, ABI Validation, Boot Verification, Stress
Testing, Long Duration Testing.

---

## Build Profiles

Minimal, Standard, Balanced, Performance, Gaming, Battery Saver,
Enterprise, Development, Debug, Benchmark.

---

## Device Profiles

Phone, Tablet, Foldable, TV, Automotive, Wearable, Embedded, Virtual
Device.

---

## Rust Framework

Support Rust incrementally where it improves safety and
maintainability. Keep Rust isolated. Avoid unnecessary rewrites.

---

## Toolchain

Latest stable LLVM/Clang. Enable when stable: ThinLTO, LTO, PGO,
AutoFDO, BOLT (where applicable).

---

## CI/CD

Continuous: Build, Boot, Static Analysis, Security, Benchmark, Regression
Detection, Documentation, Release Validation, ABI Validation.

---

## Automatic Patch Management

Every patch includes: Patch ID, Author, Subsystem, Dependencies, Review
Status, Upstream Status, Risk Level, Rollback Strategy, Documentation.

---

## Developer SDK

Tooling for: New Driver, Vendor Package, Device Package, Scheduler
Module, Filesystem Module, Benchmark, Testing, Documentation Generation.

---

## Documentation

Auto-generated: Architecture, API, Dependency Graph, Subsystem Diagrams,
ABI Documentation, Build Guide, Contribution Guide, Coding Standards,
Release Notes, Changelog, Migration Guides.

---

## Repository Organization

Clean, modular areas: Core, Android Integration, Vendor Support, Device
Packages, Frameworks, Tools, SDK, CI, Documentation, Benchmarks, Tests,
Scripts.

---

## Long-Term Roadmap

- **Phase 1** — Linux 6.18 LTS, ACK Integration, Aurora Core
- **Phase 2** — Qualcomm Support Framework, GKI Compliance
- **Phase 3** — MediaTek, Tensor, Exynos
- **Phase 4** — Advanced Performance, AI-assisted Scheduling Research,
  Power Intelligence
- **Phase 5** — Multi-device Production Platform, Enterprise Stability,
  Long-term LTS Maintenance

> **Current status:** Phase 1 — ACK 6.18 fetch works; GKI core build
> in progress; vendor mainlining (5.10 → 6.18) is the active blocker.

---

## Success Criteria

Every contribution must answer:

- Does it improve maintainability?
- Does it reduce technical debt?
- Is it upstream-friendly?
- Is it modular?
- Is it measurable?
- Does it preserve Android compatibility?
- Does it improve security?
- Does it improve power efficiency?
- Does it improve performance without sacrificing stability?
- Will it simplify future Linux LTS migrations?

If any answer is **No**, the implementation must be redesigned before
merging.

> Aurora Kernel prioritizes correctness, maintainability, stability,
> security, and long-term evolution over short-term optimizations or
> device-specific hacks.
