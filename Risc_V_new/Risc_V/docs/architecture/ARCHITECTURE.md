# Quad-core RV32IMA architecture

This folder contains the presentation-ready block diagrams generated from the active RTL hierarchy.

| Diagram | Scope | RTL owner |
|---|---|---|
| `system_overview.svg` | Four cores, memory hierarchy and bus domains | `rtl/soc/` |
| `core_pipeline.svg` | RV32IMA five-stage pipeline and control | `rtl/core/` |
| `mmu.svg` | Legacy Sv32 work, excluded from the active hierarchy | `rtl/files_sv32_legacy.f` |
| `cache_coherence.svg` | Private L1, shared cache controller (MMU), peer L2 and MSI | `rtl/mmu/cache_controller_mmu.v`, `rtl/cache/`, `rtl/coherence/` |
| `cache_controller_fsm.svg` | Active arbitration, L2, snoop, refill/writeback and response FSM | `rtl/mmu/cache_controller_mmu.v` |
| `bus_domains.svg` | AHB-Lite core domain and AXI4 system boundary | `rtl/interconnect/ahb/`, `rtl/soc/` |
| `boot_flow.svg` | SD to DRAM boot and result writeback path | `rtl/boot/`, external Vivado IP |
| `verification.svg` | Self-checking RTL and FPGA verification flow | `sim/`, `scripts/` |
| `rtl_tree.svg` | Source-code organization by block | `rtl/` |

## Architectural boundaries

- `core` produces direct 32-bit physical instruction and data addresses and implements RV32IMA, CSR, trap and privilege behavior.
- `physical_core_wrapper` handles cache back-pressure and access-fault timing without a TLB or page-table walker.
- `cache_controller_mmu` is the shared Cache/Memory Management Unit for the four-core CPU. It performs round-robin arbitration, block movement, MSI and external-memory sequencing, and is a peer of `l2_cache`.
- `cache` contains private L1 caches and a shared L2 cache. Each D-cache stores MSI state per line.
- `cache_controller_mmu` owns the arbitration, MSI transaction FSM, parallel-snoop scoreboard and external-memory line engine. `coherence/` now contains only the legacy facade that selects the internal-L2 compatibility mode.
- `interconnect/ahb` translates cache-side requests to the AHB-Lite signal-level protocol used by the AHB-oriented SoC top.
- `soc` instantiates four core/cache subsystems and exposes the external memory interface through AXI4-facing wrappers.
- `boot` provides the control path required to load software into DRAM and release the processor at the selected entry point.
- `debug` contains optional circular trace buffers. Generate parameters remove them from the default board netlist.

## Data paths

1. Instruction fetch: `physical PC -> L1 I-cache -> cache controller/L2 on miss`.
2. Cached load/store: `physical address -> L1 D-cache -> shared cache controller (MMU) -> MSI request/snoop <-> peer L2 -> external memory`.
3. Device load/store: `physical 0xC000_0000..0xFFFF_FFFF -> D-cache uncached selector -> one-word coherence bypass -> AHB HPROT/HSIZE -> AXI WSTRB -> peripheral`; no L1/L2 allocation or snoop is performed.
4. FPGA boot: `SD/SPI -> DMA -> DRAM -> boot controller releases cores -> software executes -> DMA writes output back to SD`.
5. Non-coherent DMA maintenance: `quiesce buffer -> Cache_Flush -> wait Busy=0/Done=1 -> check Error=0 -> DMA -> repeat maintenance -> CPU consumes buffer`.

Run `generate_architecture_svgs.mjs` with the bundled Node.js runtime after changing the block boundaries or labels.
