# ADR 0004: Mandatory MGLRU Integration

**Status:** Accepted
**Date:** 2026-07-23

## Problem

The legacy active/inactive LRU list does not distinguish between
frequently-used and rarely-used pages effectively on memory-constrained
mobile devices, leading to premature eviction of warm pages and excessive
swapping.

## Alternatives Considered

1. **Legacy LRU (default before 6.1)** — simpler, but thrashes under
   memory pressure on 8GB devices with zRAM.
2. **DAMON-only proactive reclaim** — helps, but does not replace the
   page eviction policy itself.
3. **MGLRU + DAMON** — both, complementary.

## Decision

Mandate **Multi-Generational LRU** (`CONFIG_LRU_GEN=y`) as the default
page reclaim policy across all Aurora builds.

## Rationale

- MGLRU tracks page generations, evicting the coldest generations first.
- Google's own testing (Pixel 6+) showed ~40% fewer cold page refaults and
  measurable battery improvement under memory pressure.
- It is upstream since 6.1 and marked stable in the 6.18 feature matrix.
- Pairs well with DAMON for proactive compaction.

## Future Impact

The defconfig must set `CONFIG_LRU_GEN=y` and `CONFIG_LRU_GEN_ENABLED=y`.
The runtime tuner must ensure `echo y > /sys/kernel/mm/lru_gen/enabled`.
