# Physical-address system behavioral test plan

## 1. Purpose

This plan is the pre-bitstream behavioral gate for the active thesis scope:
four RV32IMA cores, private L1 caches, point-to-point AHB-Lite links, shared
cache controller/L2 and the board-facing AXI4 wrapper. Sv32 translation, TLBs
and page-table walking are outside this gate and outside the active RTL manifest.

The organization follows the useful parts of the added VLSIT AI flow:
self-checking plain HDL tests, requirement IDs, an ordered verification ladder,
separate DUT/tool failure classification and reproducible per-test logs. Expected
behavior is taken from the active architecture documentation and interface
protocol, not copied from internal FSM state encodings.

## 2. Behavioral contract

| Requirement | Expected behavior |
|---|---|
| PHY-ADDR-01 | `RESET_ADDR0..3`, instruction addresses and data addresses are physical addresses with no translation. |
| PHY-ADDR-02 | The deprecated `Mmu_Flush` compatibility input has no functional effect and emits no page-walk traffic. |
| PHY-ADDR-03 | Fetch/data page-fault outputs remain low because no page-translation mechanism exists. |
| CACHE-COH-01 | Four cores may successively own and modify different words of one cache line without losing earlier dirty data. |
| CACHE-MAINT-01 | `Cache_Flush` drains private L1 caches first, then writes every dirty shared-L2 line to external memory and invalidates L2 before `Done`. |
| CACHE-ATOMIC-01 | A granted line is committed into the requesting L1 before the controller may issue a conflicting transaction/snoop for that line. |
| AHB-01 | L1 line and uncached requests cross the point-to-point AHB-Lite links without changing MSI semantics. |
| AXI-01 | AXI `VALID` and payload remain stable until the corresponding `READY` handshake. AW and W may complete independently. |
| BOARD-BOOT-01 | Four independent programs execute from `0x1000`, `0x2000`, `0x3000` and `0x4000`, matching the active Vivado Block Design parameters. |

## 3. Ordered ladder

| Level | Testbench | Main evidence |
|---|---|---|
| L0 core | `tb_core_rv32ima_isa.v` | RV32IMA instruction/datapath behavior independent of caches. |
| L1 core + private L1 | `tb_core_l1_physical_subsystem.v` | A real core executes through I$/D$, ignores `Mmu_Flush`, then cleans dirty physical data. |
| L2 cache/AHB | `tb_coherence_ahb.v` | MSI ownership, dirty forwarding, invalidate, eviction and AHB transport. |
| L3 four-core SoC | `tb_quad_core_soc_ahb_behavior.v` | Four real cores execute concurrently, modify one shared line, ignore `Mmu_Flush`, flush and expose correct memory. |
| L4 board AXI boundary | `tb_quad_core_axi_ahb_behavior.v` | Same four-core workload through `quad_core_axi_wrapper_ahb` with AXI backpressure and independent AW/W handshakes. |

The L2 and L3 programs intentionally write four different words in one cache
line. This is stronger than four unrelated private signatures: every ownership
transfer must preserve modifications made by the previous owner.

`Cache_Flush_Done` is a full-hierarchy completion event, not merely an L1
completion. This is required before and after a non-coherent DMA transfer:
L1 clean/invalidate -> L2 dirty writeback/invalidate -> external-memory visible.

## 4. Run command

From the Vivado Tcl Console:

```tcl
source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_behavior_hierarchy_xsim.tcl}
```

The script performs no synthesis. Results are written below
`reports/xsim-behavior-hierarchy-<timestamp>/` with separate compile,
elaboration and simulation logs. A test is PASS only when its self-checking
marker is present. Elaboration/tool failures are reported as `TOOL_ERROR`, not
as DUT failures. Before compilation, the script also rejects an active
`rtl/files.f` containing historical `mmu_top`, TLB, super-TLB, PTW, region
decoder, MMU core wrapper or MMU AXI wrapper sources. The cache-controller
module is intentionally allowed despite retaining `mmu` in its legacy name.

## 5. Board-release gate after behavior passes

Behavioral PASS authorizes moving to bitstream preparation, but does not prove
timing or board electrical integration. Before programming the FPGA, also check:

1. Block Design validation and wrapper generation complete.
2. The four reset addresses still match this test plan.
3. `Mmu_Flush` is tied low and `Cache_Flush` is connected or tied intentionally.
4. The BRAM/DDR image contains a valid program at every enabled reset address.
5. Clock/reset, memory map and XDC target the actual board.

DMA/SD-to-DDR boot and the generated Vivado IP Block Design remain separate
hardware-integration gates; they are not falsely claimed by these RTL tests.

## 6. Focused debug commands

Run one self-checking test without the full regression from the Vivado Tcl
Console:

```tcl
set ONE_TB_FILE tb_coherence.v
set ONE_TB_TOP tb_coherence
set ONE_TB_MARKER {MSI_COHERENCE_TB: PASS}
source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_one_xsim.tcl}
```

Run the four-core same-line ownership trace (L2 writes and snoop data are
printed to `reports/xsim-soc-coherence-trace/trace.log`):

```tcl
source {C:/Users/ADMIN/Documents/GitHub/KLTN/Risc_V_new/Risc_V/scripts/run_trace_soc_xsim.tcl}
```
