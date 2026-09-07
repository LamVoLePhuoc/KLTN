`timescale 1ns / 1ps

// ============================================================
// mmu_core_wrapper
//
// Wraps one RV32IMA core with a per-core MMU (mmu_top: iTLB +
// dTLB + shared PTW), placed exactly where address_mapping's
// diagram puts it: between the core's pipeline (VA) and
// whatever sits downstream on the memory side (today: the
// shared-bus arbiter / RAM model; later: an L1 cache).
//
// External port shape matches RV32IMA (drop-in replacement):
// PCF/InstrF and the Mem_* bus now carry physical addresses
// instead of virtual ones. RV32IMA.v itself was not touched.
//
// The core's own Stall_Core_External input (already used for
// the MDU and for AXI store waits in RV32_IP_Wrapper.v) is
// reused to freeze the whole pipeline while the PTW walks the
// page table, so no pipeline-internal file needed to change.
//
// mmu_enable=0 is a fully transparent VA=PA bypass: behaviour
// is then byte-for-byte identical to instantiating RV32IMA
// directly.
//
// NOTE (flagged, not fixed here): memory_stage's LR/SC
// reservation match compares Snoop_Addr (physical, coming from
// another core) against ALU_ResultM, which above the MMU is a
// *virtual* address. Cross-core atomics are only guaranteed
// correct today if every core maps shared atomic locations
// through an identical VA->PA mapping. Making LR/SC fully safe
// under independent per-core page tables needs changes to
// memory_stage / the arbiter's snoop path, which this task did
// not ask for and is not done here.
//
// NOTE (flagged): there is no trap/exception unit in this core
// to deliver a page fault into, so a faulting fetch is forced
// to a NOP and a faulting data access is blocked (store
// suppressed, load returns 0); Fetch_PageFault/Data_PageFault
// pulse for one cycle so a future trap unit can observe them,
// but nothing actually traps today.
// ============================================================
module mmu_core_wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_1000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        Stall_Core_External,

    // MMU control
    input  wire        Mmu_Enable,
    input  wire [19:0] Satp_PPN,     // physical page number of the root page table
    input  wire        Mmu_Flush,    // pulse to invalidate both TLBs (only when idle, see NOTE above)

    // Snoop for LR/SC (see NOTE above: physical domain)
    input  wire [31:0] Snoop_Addr,
    input  wire        Snoop_WE,

    // IF (physical address out)
    output wire [31:0] PCF,
    input  wire [31:0] InstrF,

    // Memory bus (physical address out)
    output wire [31:0] Mem_AddrM,
    output wire [31:0] Mem_WriteDataM,
    output wire        Mem_WriteEnM,
    output wire        Mem_ReadEnM,
    output wire [2:0]  MemOpM,
    input  wire [31:0] Mem_ReadDataM,

    // Debug / WB
    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug,

    // MMU status
    output wire        Fetch_PageFault,
    output wire        Data_PageFault,
    output wire [1:0]  Fetch_PageFault_Cause,
    output wire [1:0]  Data_PageFault_Cause
);

    // ------------------------------------------------------
    // Core-side (virtual-address) bus
    // ------------------------------------------------------
    wire [31:0] pcf_va;
    wire [31:0] instrf_to_core;

    wire [31:0] mem_addr_va;
    wire [31:0] mem_wdata_core;
    wire        mem_we_core;
    wire        mem_re_core;
    wire [2:0]  memop_core;
    wire [31:0] mem_rdata_to_core;

    wire mem_req_core = mem_re_core | mem_we_core;

    // ------------------------------------------------------
    // MMU
    // ------------------------------------------------------
    wire [31:0] pa_fetch;
    wire [31:0] pa_mem;
    wire        fetch_fault;
    wire        mem_fault;
    wire        mmu_busy;

    wire        ptw_mem_req;
    wire [31:0] ptw_mem_addr;

    mmu_top mmu (
        .clk(clk), .rst(rst),

        .mmu_enable(Mmu_Enable),
        .satp_ppn(Satp_PPN),
        .flush(Mmu_Flush),

        .va_fetch(pcf_va),
        .pa_fetch(pa_fetch),

        .va_mem(mem_addr_va),
        .mem_req(mem_req_core),
        .mem_is_store(mem_we_core),
        .pa_mem(pa_mem),

        .fetch_fault(fetch_fault),
        .mem_fault(mem_fault),
        .fetch_fault_cause(Fetch_PageFault_Cause),
        .mem_fault_cause(Data_PageFault_Cause),

        .ptw_mem_req(ptw_mem_req),
        .ptw_mem_addr(ptw_mem_addr),
        .ptw_mem_rdata(Mem_ReadDataM),

        .busy(mmu_busy)
    );

    assign Fetch_PageFault = fetch_fault;
    assign Data_PageFault  = mem_fault;

    // ------------------------------------------------------
    // Instruction side: pure passthrough. Reads have no side
    // effects, so it is safe to always drive the translated (or
    // raw, if disabled) address out; the fetched instruction is
    // only forced to a NOP if the fetch that was frozen on this
    // VA turned out to fault once resolved.
    // ------------------------------------------------------
    assign PCF            = pa_fetch;
    assign instrf_to_core = fetch_fault ? 32'h0000_0013 : InstrF;

    // ------------------------------------------------------
    // Data side: while the MMU is busy (walking either side),
    // the external bus belongs to the PTW, not the core. Once
    // idle, the core's own request goes out translated, with a
    // faulting access blocked (store suppressed / load data
    // zeroed) on its one-cycle resume/gate window.
    // ------------------------------------------------------
    assign Mem_AddrM      = mmu_busy ? ptw_mem_addr : pa_mem;
    assign Mem_ReadEnM    = mmu_busy ? ptw_mem_req   : mem_re_core;
    assign Mem_WriteEnM   = mmu_busy ? 1'b0          : (mem_fault ? 1'b0 : mem_we_core);
    assign MemOpM         = mmu_busy ? 3'b010        : memop_core;
    assign Mem_WriteDataM = mmu_busy ? 32'b0         : mem_wdata_core;

    assign mem_rdata_to_core = mem_fault ? 32'b0 : Mem_ReadDataM;

    // ------------------------------------------------------
    // Core (virtual-address world)
    // ------------------------------------------------------
    RV32IMA #(
        .RESET_ADDR(RESET_ADDR)
    ) core (
        .clk                (clk),
        .rst                (rst),
        .Stall_Core_External(Stall_Core_External | mmu_busy),

        .Snoop_Addr         (Snoop_Addr),
        .Snoop_WE           (Snoop_WE),

        .PCF                (pcf_va),
        .InstrF             (instrf_to_core),

        .Mem_AddrM          (mem_addr_va),
        .Mem_WriteDataM     (mem_wdata_core),
        .Mem_WriteEnM       (mem_we_core),
        .Mem_ReadEnM        (mem_re_core),
        .MemOpM             (memop_core),
        .Mem_ReadDataM      (mem_rdata_to_core),

        .ResultW            (ResultW),
        .ALU_ResultE_Debug  (ALU_ResultE_Debug)
    );

endmodule
