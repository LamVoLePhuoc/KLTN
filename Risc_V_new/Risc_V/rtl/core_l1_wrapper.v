`timescale 1ns / 1ps

// ============================================================
// core_l1_wrapper
//
// One "CORE N" box from the 4-CORE CPU WRAPPER diagram: RV32IMA +
// per-core MMU (mmu_core_wrapper.v, already built) + private L1
// I-Cache/D-Cache (l1_icache.v/l1_dcache.v, this session). This is
// what quad_core_soc.v instantiates x4.
//
// mmu_core_wrapper's PCF/InstrF/Instr_ValidF and Mem_*/Mem_ReadDataValidM/
// Mem_WriteDoneM ports -- built specifically to support a real,
// multi-cycle-latency memory system (see its header) -- are exactly
// the ports the L1s plug into: no further stalling logic needed
// here, l1_icache/l1_dcache's own cpu_valid outputs ARE the
// Instr_ValidF/Mem_ReadDataValidM/Mem_WriteDoneM signals.
//
// LR/SC note: l1_dcache's own INVALIDATE-type snoops (i.e. this
// core's D$ copy of some line was just invalidated because another
// core is writing it) are wired into the core's Snoop_Addr/Snoop_WE
// ports, which is what memory_stage.v's LR/SC reservation check
// already consumes. This is a strictly more accurate signal than
// the old round_robin_arbiter_2core's "any write commit, broadcast
// to the other core" scheme it replaces (it now fires exactly when
// coherence actually required invalidating this line, nothing more/
// less) -- but it does NOT fix the VA-vs-PA mismatch already flagged
// in mmu_core_wrapper.v's own NOTE: memory_stage.v's reservation_addr
// is captured from ALU_ResultM, which is a *virtual* address (inside
// RV32IMA, pre-MMU), while the snoop address here is physical
// (post-MMU, L1 layer). The two only compare correctly if this
// core's own VA->PA mapping happens to make them numerically equal.
// Fixing that for real needs memory_stage.v itself to compare in the
// physical domain, which is out of scope here (see Risc_V_new/README.md).
//
// MMU control: mmu_core_wrapper is instantiated below with
// MMU_CTRL_FROM_CSR=1 -- the core's own satp CSR (software-written via
// CSRRW, see csr_trap_unit.v) is the ONE real source of truth for
// whether translation is on and which page table root is active, same
// as real RISC-V hardware (there is no external "enable paging" pin on
// a real core). This is why there is no Mmu_Enable/Satp_PPN port here
// any more (there was, in an earlier version of this file, before the
// satp-CSR-to-MMU feedback loop was wired up) -- keeping them would
// have left two sources of truth that could disagree. Mmu_Flush
// remains a real external input: it is
// OR'd with the CSR's own sfence.vma-triggered flush (mmu_core_wrapper.v),
// which is safe (an extra TLB invalidate only costs a refill, never a
// correctness bug) and useful for a testbench that wants to force a
// flush without executing real supervisor code.
// ============================================================
module core_l1_wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_1000
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        Mmu_Flush,
    input  wire        Cache_Flush,   // sim/debug only -- drops all L1 lines with no writeback

    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug,
    output wire        Fetch_PageFault,
    output wire        Data_PageFault,
    output wire [1:0]  Fetch_PageFault_Cause,
    output wire [1:0]  Data_PageFault_Cause,

    // ---- I$ miss port (to coherence_manager.v) ----
    output wire         ibus_req_valid,
    output wire [31:0]  ibus_req_addr,
    input  wire         ibus_resp_valid,
    input  wire [255:0] ibus_resp_line,

    // ---- D$ request port (to coherence_manager.v) ----
    output wire         dbus_req_valid,
    output wire [1:0]   dbus_req_type,
    output wire [31:0]  dbus_req_addr,
    output wire [255:0] dbus_req_line,
    input  wire         dbus_resp_valid,
    input  wire [255:0] dbus_resp_line,
    input  wire [1:0]   dbus_resp_state,

    // ---- D$ snoop port (from coherence_manager.v) ----
    input  wire         dsnoop_valid,
    input  wire         dsnoop_type,
    input  wire [31:0]  dsnoop_addr,
    output wire         dsnoop_ack_valid,
    output wire         dsnoop_ack_hit,
    output wire         dsnoop_ack_dirty,
    output wire [255:0] dsnoop_ack_line
);

    wire [31:0] PCF;
    wire [31:0] InstrF;
    wire        Instr_ValidF;

    wire [31:0] Mem_AddrM;
    wire [31:0] Mem_WriteDataM;
    wire        Mem_WriteEnM;
    wire        Mem_ReadEnM;
    wire [2:0]  MemOpM;
    wire [31:0] Mem_ReadDataM;
    wire        Mem_DataValid;

    wire [31:0] snoop_addr_to_core;
    wire        snoop_we_to_core;

    mmu_core_wrapper #(
        .RESET_ADDR(RESET_ADDR),
        .MMU_CTRL_FROM_CSR(1)
    ) mmu_core (
        .clk                (clk),
        .rst                (rst),
        .Stall_Core_External(1'b0),

        // Ignored inside mmu_core_wrapper when MMU_CTRL_FROM_CSR=1 (see
        // its header) -- tied to the transparent-bypass/root-0 values
        // only so the port connection itself stays well-formed; satp
        // CSR state is what actually drives translation here.
        .Mmu_Enable         (1'b0),
        .Satp_PPN           (20'b0),
        .Mmu_Flush          (Mmu_Flush),

        .Snoop_Addr         (snoop_addr_to_core),
        .Snoop_WE           (snoop_we_to_core),

        .PCF                (PCF),
        .InstrF             (InstrF),
        .Instr_ValidF       (Instr_ValidF),

        .Mem_AddrM          (Mem_AddrM),
        .Mem_WriteDataM     (Mem_WriteDataM),
        .Mem_WriteEnM       (Mem_WriteEnM),
        .Mem_ReadEnM        (Mem_ReadEnM),
        .MemOpM             (MemOpM),
        .Mem_ReadDataM      (Mem_ReadDataM),
        .Mem_ReadDataValidM (Mem_DataValid),
        .Mem_WriteDoneM     (Mem_DataValid),

        .ResultW            (ResultW),
        .ALU_ResultE_Debug  (ALU_ResultE_Debug),

        .Fetch_PageFault       (Fetch_PageFault),
        .Data_PageFault        (Data_PageFault),
        .Fetch_PageFault_Cause (Fetch_PageFault_Cause),
        .Data_PageFault_Cause  (Data_PageFault_Cause)
    );

    l1_icache u_icache (
        .clk            (clk),
        .rst            (rst),
        .flush          (Cache_Flush),

        .cpu_addr       (PCF),
        .cpu_rdata      (InstrF),
        .cpu_valid      (Instr_ValidF),

        .bus_req_valid  (ibus_req_valid),
        .bus_req_addr   (ibus_req_addr),
        .bus_resp_valid (ibus_resp_valid),
        .bus_resp_line  (ibus_resp_line)
    );

    l1_dcache u_dcache (
        .clk            (clk),
        .rst            (rst),
        .flush          (Cache_Flush),

        .cpu_addr       (Mem_AddrM),
        .cpu_wdata      (Mem_WriteDataM),
        .cpu_we         (Mem_WriteEnM),
        .cpu_re         (Mem_ReadEnM),
        .cpu_memop      (MemOpM),
        .cpu_rdata      (Mem_ReadDataM),
        .cpu_valid      (Mem_DataValid),

        .bus_req_valid  (dbus_req_valid),
        .bus_req_type   (dbus_req_type),
        .bus_req_addr   (dbus_req_addr),
        .bus_req_line   (dbus_req_line),
        .bus_resp_valid (dbus_resp_valid),
        .bus_resp_line  (dbus_resp_line),
        .bus_resp_state (dbus_resp_state),

        .snoop_valid     (dsnoop_valid),
        .snoop_type      (dsnoop_type),
        .snoop_addr      (dsnoop_addr),
        .snoop_ack_valid (dsnoop_ack_valid),
        .snoop_ack_hit   (dsnoop_ack_hit),
        .snoop_ack_dirty (dsnoop_ack_dirty),
        .snoop_ack_line  (dsnoop_ack_line)
    );

    // See header NOTE: fires on an invalidate-type snoop, not a
    // downgrade (downgrade keeps the line readable, no reservation
    // needs to break; RISC-V's LR/SC semantics only require the
    // reservation to break when another agent's WRITE could have
    // touched the location).
    assign snoop_addr_to_core = dsnoop_addr;
    assign snoop_we_to_core   = dsnoop_valid & ~dsnoop_type;

endmodule
