# Quad-core RV32IMA architecture

This folder contains the presentation-ready block diagrams generated from the active RTL hierarchy.

| Diagram | Scope | RTL owner |
|---|---|---|
| `system_overview.svg` | Four cores, memory hierarchy and bus domains | `rtl/soc/` |
| `core_pipeline.svg` | RV32IMA five-stage pipeline and control | `rtl/core/` |
| `mmu.svg` | Per-core Sv32 translation, TLBs and PTW | `rtl/mmu/` |
| `cache_coherence.svg` | Private L1, shared L2 and MSI protocol | `rtl/cache/`, `rtl/coherence/` |
| `bus_domains.svg` | AHB-Lite core domain and AXI4 system boundary | `rtl/interconnect/ahb/`, `rtl/soc/` |
| `boot_flow.svg` | SD to DRAM boot and result writeback path | `rtl/boot/`, external Vivado IP |
| `verification.svg` | Self-checking RTL and FPGA verification flow | `sim/`, `scripts/` |
| `rtl_tree.svg` | Source-code organization by block | `rtl/` |

## Architectural boundaries

- `core` produces virtual instruction and data addresses and implements RV32IMA, CSR, trap and privilege behavior.
- `mmu` translates virtual addresses to physical addresses. The design uses separate instruction and data TLBs with one shared two-level PTW.
- `cache` contains private L1 caches and a shared L2 cache. Each D-cache stores MSI state per line.
- `coherence` serializes cache-miss traffic, tracks sharers, issues snoops and connects the cache hierarchy to external memory.
- `interconnect/ahb` translates cache-side requests to the AHB-Lite signal-level protocol used by the AHB-oriented SoC top.
- `soc` instantiates four core/cache subsystems and exposes the external memory interface through AXI4-facing wrappers.
- `boot` provides the control path required to load software into DRAM and release the processor at the selected entry point.
- `debug` contains optional circular trace buffers. Generate parameters remove them from the default board netlist.

## Data paths

1. Instruction fetch: `PC virtual address -> iTLB -> physical address -> L1 I-cache -> coherence manager/L2 on miss`.
2. Load/store: `data virtual address -> dTLB -> physical address -> L1 D-cache -> MSI request/snoop -> L2 -> external memory`.
3. Page-table walk: `TLB miss -> shared PTW -> page-table memory request -> optional A/D update -> TLB refill -> retry`.
4. FPGA boot: `SD/SPI -> DMA -> DRAM -> boot controller releases cores -> software executes -> DMA writes output back to SD`.

Run `generate_architecture_svgs.mjs` with the bundled Node.js runtime after changing the block boundaries or labels.
