# RTL organization

> Current status: the full inventory in [`files.f`](files.f) compiles with
> QuestaSim 10.2c after the directory reorganization. `tb_coherence.v` and
> `tb_coherence_ahb.v` both pass. Full MMU/cache/CSR regression and Vivado
> synthesis still need to be rerun; see [`../../README.md`](../../README.md).

The active quad-core design is grouped by architectural block. Module names and interfaces are unchanged; only source locations changed.

```text
rtl/
├── core/             RV32IMA pipeline, execution units, CSR, trap and privilege logic
├── mmu/              iTLB, dTLB, superpage TLB, PTW, address policy and core/MMU wrappers
├── cache/            Per-core L1 I/D caches, shared L2 cache and the core-L1 subsystem wrapper
├── coherence/        Shared MSI coherence manager, directory, snoop control and memory transaction engine
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
- `files.f`: canonical relative source inventory for static checks and simulator setup.

The Vivado scripts resolve source files recursively below `rtl/`, so adding another block folder does not require flattening the tree again.

The Vivado project file has also been updated to the new paths. Add future RTL to
the appropriate block folder and to `files.f`; do not restore a flat `rtl/` layout.

## Dependency direction

```text
soc -> cache/core subsystem -> mmu -> core
soc -> interconnect/ahb -> coherence -> cache/L2
soc -> boot
mmu, coherence -> debug (optional generate blocks)
legacy_2core -> core
```

Avoid dependencies in the opposite direction. In particular, the core must remain independent of cache and SoC wrappers, and the MMU must not instantiate a cache.
