# ADR 0003: Dynamic Preemption (PREEMPT_DYNAMIC)

**Status:** Accepted
**Date:** 2026-07-23

## Problem

Choosing a fixed preemption model at compile time (`PREEMPT_NONE` for
battery, `PREEMPT_FULL` for responsiveness) forces a trade-off that cannot
be adapted at runtime for different workloads (gaming vs. idle).

## Alternatives Considered

1. **`PREEMPT_NONE`** — best battery, worst latency; UI jank under load.
2. **`PREEMPT_FULL`** — best latency, higher battery drain at idle.
3. **`PREEMPT_VOLUNTARY`** — compromise, but fixed.

## Decision

Enable **`PREEMPT_DYNAMIC`**, which compiles the kernel with preemption
points that can be switched at runtime between `none`, `voluntary`, and
`full` via `/sys/kernel/debug/sched/preempt`.

## Rationale

- A single kernel image serves both battery (idle → `none`) and gaming
  (foreground → `full`) profiles without recompilation.
- The Aurora profile daemon (`aurora-tune.sh`) can switch preemption mode
  on `persist.aurora.profile` property changes.
- `PREEMPT_DYNAMIC` is upstream-supported since 5.12 and stable in 6.18.

## Future Impact

The runtime tuner must set `preempt` mode per profile. The build defconfig
enables `CONFIG_PREEMPT_DYNAMIC=y` and defaults to `voluntary` at boot.
