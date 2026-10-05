# RTL organization

> Current status: the full inventory in [`files.f`](files.f) compiles with
> QuestaSim 10.2c after the directory reorganization. All 26 self-checking
> MMU/cache/coherence/CSR/AHB/AXI testbenches pass. Vivado synthesis and board
> validation still need to be run; see [`../../README.md`](../../README.md).

The active quad-core design is grouped by architectural block. Module names and interfaces are unchanged; only source locations changed.

```text
rtl/
├── core/             RV32IMA pipeline, execution units, CSR, trap and privilege logic
├── mmu/              Per-core Sv32 translation plus the shared cache-controller MMU facade
├── cache/            Per-core L1 I/D caches, shared L2 cache and the core-L1 subsystem wrapper
├── coherence/        MSI policy engine, round-robin arbitration, snoop and memory transactions
├── interconnect/ahb/ AHB-Lite adapters used at the L1/coherence boundary
├── soc/              Four-core integration and AXI4-facing wrappers
├── boot/             Boot control register block used by bootable wrappers
├── debug/            Optional MMU and cache trace buffers
└── legacy_2core/     Retained two-core FPGA baseline; not part of the active quad-core hierarchy
```

## Build entry points

- `soc/quad_core_soc.v`: native request/response path.
- `soc/quad_core_soc_ahb.v`: AHB-Lite adapter path.
- `soc/quad_core_axi_wrapper_ahb.v`: AXI4-facing wrapper for the AHB-Lite quad-core SoC.
- `soc/quad_core_axi_wrapper_ahb_bootable.v`: bootable AXI4-facing system wrapper.
- `docs/BOOT_DMA_PROTOCOL.md`: AXI4-Lite register map and the required pre/post-DMA cache-maintenance sequence.
- `files.f`: canonical relative source inventory for static checks and simulator setup.

The Vivado scripts resolve source files recursively below `rtl/`, so adding another block folder does not require flattening the tree again.

The Vivado project file has also been updated to the new paths. Add future RTL to
the appropriate block folder and to `files.f`; do not restore a flat `rtl/` layout.

The quad-core SoC and every AXI/bootable wrapper expose
`Cache_Flush_Busy`, `Cache_Flush_Done`, and sticky `Cache_Flush_Error` beside the
existing `Cache_Flush` request. External DMA/boot logic must wait for `Done` and
reject the transfer on `Error`; software must keep the target buffer quiescent
until the pre/post-DMA maintenance sequence completes.

## Dependency direction

```text
soc -> cache/core subsystem -> mmu -> core
soc -> cache_controller_mmu -> coherence policy engine
soc -> cache/L2 (peer of cache_controller_mmu)
soc -> interconnect/ahb -> cache_controller_mmu
soc -> boot
mmu, coherence -> debug (optional generate blocks)
legacy_2core -> core
```

Avoid dependencies in the opposite direction. In particular, the core must remain independent of cache and SoC wrappers. `mmu_top` (Sv32 translation) must not instantiate a cache; `cache_controller_mmu` is a separately named system-level controller and communicates with the peer L2 only through its command/status interface.

The two meanings of "MMU" used in the project are documented in
[`docs/architecture/MMU_CACHE_CONTROLLER_REDESIGN.md`](../docs/architecture/MMU_CACHE_CONTROLLER_REDESIGN.md).
