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
// UPDATED: the core now has a real trap/exception unit
// (csr_trap_unit.v, instantiated inside RV32IMA.v) that
// Fetch_PageFault/Data_PageFault feed directly (see the
// Fetch_PageFault_In/Data_PageFault_In connections below) -- a page
// fault actually traps (redirects to mtvec/stvec, sets
// mcause/mepc/mtval) instead of only forcing a NOP/blocking a store
// with nowhere for software to catch it. The one-cycle-early NOP-
// force/store-suppress/load-zero behaviour below is still exactly
// right and still needed: it's what keeps the faulting instruction
// itself harmless on the very cycle the trap unit is reacting to it.
//
// Multi-cycle memory: Instr_ValidF / Mem_ReadDataValidM /
// Mem_WriteDoneM are real inputs the caller must drive -- this
// wrapper does NOT assume InstrF/Mem_ReadDataM are valid just
// because it asked for them. Whenever the core (or the PTW) has an
// outstanding fetch/load/store and the matching *_Valid/*_Done
// signal hasn't arrived yet, the whole pipeline is held frozen via
// the existing Stall_Core_External mechanism (same trick already
// used for the MDU) until it does -- so a caller backed by a
// same-cycle combinational memory (tb_mmu_core.v) simply ties all
// three to a constant 1 and gets the exact same 0-wait behaviour as
// before; a caller backed by real multi-cycle memory (mmu_ip_wrapper.v,
// AXI4) pulses each exactly on the cycle its data/response is
// actually valid. ptw_mem_valid (into mmu_top) is just
// Mem_ReadDataValidM again, since PTW reads share the same
// Mem_AddrM/Mem_ReadEnM path as the core's own loads (see the
// mmu_busy mux below) -- whatever "the data on Mem_ReadDataM is
// valid for the address I'm currently driving" means, it means the
// same thing regardless of who asked.
// ============================================================
module mmu_core_wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_1000,

    // 0 (default): mmu_top is driven by the plain external
    // Mmu_Enable/Satp_PPN inputs below, exactly as before this
    // session -- this is what tb_mmu_core.v relies on to test the
    // MMU/PTW/TLB in isolation, without needing to execute real CSR
    // writes first. 1: mmu_top is instead driven by the core's own
    // satp CSR (Mmu_Enable_Csr/Satp_PPN_Csr below), making satp the
    // one real source of truth -- used by the real system
    // (core_l1_wrapper.v). See csr_trap_unit.v's header for why this
    // is a parameter rather than always-on.
    parameter          MMU_CTRL_FROM_CSR = 0
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
    input  wire        Instr_ValidF,      // 1 exactly when InstrF is valid for PCF

    // Memory bus (physical address out)
    output wire [31:0] Mem_AddrM,
    output wire [31:0] Mem_WriteDataM,
    output wire        Mem_WriteEnM,
    output wire        Mem_ReadEnM,
    output wire [2:0]  MemOpM,
    input  wire [31:0] Mem_ReadDataM,
    input  wire        Mem_ReadDataValidM, // 1 exactly when Mem_ReadDataM is valid for Mem_AddrM
    input  wire        Mem_WriteDoneM,     // 1 exactly when the store at Mem_AddrM has completed

    // Debug / WB
    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug,

    // MMU status
    output wire        Fetch_PageFault,
    output wire        Data_PageFault,
    output wire [1:0]  Fetch_PageFault_Cause,
    output wire [1:0]  Data_PageFault_Cause,

    // RV32IMA.v's csr_trap_unit.v traps fetch_fault/mem_fault for
    // real, and exposes these hooks -- passed straight through, AND
    // (when MMU_CTRL_FROM_CSR=1 above) fed back into mmu_top's own
    // mmu_enable/satp_ppn/flush inputs, making satp the real source
    // of truth for translation. Still exposed as outputs regardless
    // of the parameter, for observability (e.g. tb_csr_trap.v).
    output wire [1:0]  CurrentPriv,
    output wire        Mmu_Enable_Csr,
    output wire [19:0] Satp_PPN_Csr,
    output wire        Mmu_Flush_Csr
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

    // ------------------------------------------------------
    // CSR-vs-external MMU control mux (see MMU_CTRL_FROM_CSR above).
    // Mmu_Enable_Csr/Satp_PPN_Csr/Mmu_Flush_Csr are this wrapper's OWN
    // output wires (driven by the `core` instance below, textually
    // later in this file) -- referencing them here is fine, Verilog
    // netlists are not order-sensitive. No combinational loop: all
    // three are purely registered CSR state inside csr_trap_unit.v
    // (satp_mode/satp_ppn/priv, and a registered one-cycle pulse for
    // flush), with no combinational path back from mmu_top's outputs
    // into csr_trap_unit.v.
    //
    // Flush is always OR'd in regardless of the parameter -- an extra
    // TLB invalidate from a source a given build doesn't otherwise use
    // is always safe (costs a refill, never a correctness bug), so
    // there is no reason to gate it too.
    wire        mmu_enable_eff = MMU_CTRL_FROM_CSR ? Mmu_Enable_Csr : Mmu_Enable;
    wire [19:0] satp_ppn_eff   = MMU_CTRL_FROM_CSR ? Satp_PPN_Csr   : Satp_PPN;
    wire        mmu_flush_eff  = Mmu_Flush | Mmu_Flush_Csr;

    mmu_top mmu (
        .clk(clk), .rst(rst),

        .mmu_enable(mmu_enable_eff),
        .satp_ppn(satp_ppn_eff),
        .flush(mmu_flush_eff),

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
        .ptw_mem_valid(Mem_ReadDataValidM),

        .busy(mmu_busy)
    );

    assign Fetch_PageFault = fetch_fault;
    assign Data_PageFault  = mem_fault;

    // ------------------------------------------------------
    // Multi-cycle memory stall (see header NOTE). While mmu_busy,
    // Mem_AddrM/Mem_ReadEnM belong to the PTW, whose own completion
    // is already gated by ptw_mem_valid above and by mmu_busy
    // itself -- so these two only need to fire for the core's OWN,
    // non-PTW fetch/load/store traffic, i.e. exactly when NOT busy.
    // mem_re_core/mem_we_core/pcf_va all stay parked on the same
    // value every cycle the core is frozen (the pipeline register
    // driving them simply doesn't advance), so re-checking the
    // *_Valid/*_Done input every cycle is both correct and
    // sufficient -- no extra "outstanding transaction" state needed
    // here, the caller owns that bookkeeping (see mmu_ip_wrapper.v).
    // ------------------------------------------------------
    // NOTE: keyed off Mem_WriteEnM/Mem_ReadEnM (the *actual*, already
    // fault-gated bus outputs below), not the raw core-side
    // mem_we_core/mem_re_core -- a store that mem_fault suppressed
    // never asserts Mem_WriteEnM, so it must never wait for a
    // Mem_WriteDoneM that (correctly) will never come. A faulting
    // *load* is different: Mem_ReadEnM is NOT suppressed on fault
    // (only the returned data is, via mem_rdata_to_core below), so a
    // real read is genuinely issued and genuinely needs to complete.
    wire fetch_wait = ~mmu_busy & ~Instr_ValidF;
    wire data_wait  = ~mmu_busy & (Mem_WriteEnM ? ~Mem_WriteDoneM :
                                    Mem_ReadEnM  ? ~Mem_ReadDataValidM :
                                                    1'b0);
    wire mem_stall  = fetch_wait | data_wait;

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
        .Stall_Core_External(Stall_Core_External | mmu_busy | mem_stall),

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

        // NEW: feed the MMU's own already-computed fault flags
        // straight into the core's trap unit -- see RV32IMA.v's port
        // comment. This is the SAME fetch_fault/mem_fault this
        // wrapper already exposes as Fetch_PageFault/Data_PageFault
        // above; now it ALSO reaches the core internally, so a page
        // fault actually traps instead of only forcing a NOP/
        // blocking a store with nowhere for software to catch it.
        .Fetch_PageFault_In (fetch_fault),
        .Data_PageFault_In  (mem_fault),

        .ResultW            (ResultW),
        .ALU_ResultE_Debug  (ALU_ResultE_Debug),

        .CurrentPriv        (CurrentPriv),
        .Mmu_Enable_Csr     (Mmu_Enable_Csr),
        .Satp_PPN_Csr       (Satp_PPN_Csr),
        .Mmu_Flush_Csr      (Mmu_Flush_Csr)
    );

endmodule
