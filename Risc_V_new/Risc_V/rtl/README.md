# RTL organization

> Last verified pre-scope-change baseline: the then-current inventory compiled
> with QuestaSim 10.2c after the directory reorganization and all 26 then-present
> self-checking testbenches passed. New RV32IMA legality/execution and DMA tests
> have since been added and require a fresh regression. The active
> `quad_core_axi_wrapper_ahb` hierarchy and the complete `soc_4core_trial` Block
> Design also synthesize successfully in Vivado 2022.2. The full BD uses 248/265
> BRAM tiles with 0 error/0 critical warning; its 100 MHz post-synthesis timing
> estimate is not yet met (WNS -5.308 ns). Implementation and board validation remain, see
> [`../../README.md`](../../README.md).

The active quad-core design is grouped by architectural block. It uses direct
physical addresses; TLB/PTW/Sv32 sources are excluded from `files.f` and kept in
`files_sv32_legacy.f` only for reproducing historical tests.

```text
rtl/
├── core/             RV32IMA pipeline, execution units, CSR, trap and privilege logic
├── mmu/              Active shared cache-controller MMU plus legacy Sv32 source files
├── cache/            Per-core L1 I/D caches, shared L2 cache and the core-L1 subsystem wrapper
├── coherence/        Backward-compatible facade for legacy integrated-L2 tests
├── interconnect/ahb/ AHB-Lite adapters used at the L1/coherence boundary
├── soc/              Four-core integration and AXI4-facing wrappers
├── boot/             Boot control register block used by bootable wrappers
├── dma/              Historical custom-DMA reference; excluded from active source set
├── debug/            Optional MMU and cache trace buffers
└── legacy_2core/     Retained two-core FPGA baseline; not part of the active quad-core hierarchy
```

## Build entry points

- `soc/quad_core_soc.v`: native request/response path.
- `soc/quad_core_soc_ahb.v`: AHB-Lite adapter path.
- `soc/quad_core_axi_wrapper_ahb.v`: AXI4-facing wrapper for the AHB-Lite quad-core SoC.
- `soc/quad_core_axi_wrapper_ahb_bootable.v`: bootable AXI4-facing system wrapper.
- `files.f`: canonical relative source inventory for static checks and simulator setup.
- `files_sv32_legacy.f`: optional translation-source inventory; never add it to an active build.

The active Vivado build registers an explicit four-core source list. Platform
DMA and memory are instantiated from the Vivado IP Catalog and must not be added
to `files.f` as custom RTL.

The Vivado project file has also been updated to the new paths. Add future RTL to
the appropriate block folder and to `files.f`; do not restore a flat `rtl/` layout.

The L1 cache data/tag/state arrays use synchronous XPM Block RAM. The shared L2
data store is eight 32-bit banks so its 512 KiB capacity maps to RAMB36 instead
of one 4,194,304-bit asynchronous variable. D-cache and L2 invalidate metadata
sequentially for 512 and 4096 cycles after reset respectively; request logic must
honor their busy/response handshakes rather than assuming immediate reset access.
The Block Design's 64 KiB AXI BRAM is only a compact stand-in for external DDR;
it does not change the 512 KiB shared-L2 capacity.

The quad-core SoC and every AXI/bootable wrapper expose
`Cache_Flush_Busy`, `Cache_Flush_Done`, and sticky `Cache_Flush_Error` beside the
existing `Cache_Flush` request. External DMA/boot logic must wait for `Done` and
reject the transfer on `Error`; software must keep the target buffer quiescent
until the pre/post-DMA maintenance sequence completes.

## Dependency direction

```text
soc -> cache/core subsystem -> physical_core_wrapper -> core
soc -> interconnect/ahb/ahb_lite_arbiter_8m1s (owns active request arbitration)
soc -> cache_controller_mmu (owns MSI FSM, snoop and memory transactions)
soc -> cache/L2 (peer of cache_controller_mmu)
soc -> interconnect/ahb adapters + arbiter -> cache_controller_mmu
soc -> boot
soc/external AXI fabric -> dma -> global cache-maintenance handshake
cache_controller_mmu -> debug (optional generate blocks)
legacy_2core -> core
```

Avoid dependencies in the opposite direction. In particular, the core remains
independent of cache and SoC wrappers. `cache_controller_mmu` is the only active
MMU-named block and communicates with peer L2 only through command/status ports.
