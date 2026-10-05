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
// instead of virtual ones. RV32IMA.v itself gained a small,
// additive Mem_PhysAddrM input since this file was first written
// (see below and memory_stage.v's header) -- every other part of
// its port shape is unchanged.
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
// FIXED (was previously flagged as a real, un-fixed bug here --
// see Risc_V_new/README.md's risk register): memory_stage.v's LR/SC
// reservation match used to compare Snoop_Addr (physical, coming
// from another core) against ALU_ResultM, which above the MMU is a
// *virtual* address -- correct only by coincidence, when a core's
// own VA->PA mapping happened to be the identity function. Fixed by
// adding RV32IMA.v's new Mem_PhysAddrM input (see memory_stage.v's
// header for the full reasoning) and wiring this wrapper's own
// already-computed pa_mem into it below -- reservation tracking and
// the snoop compare are now both in the physical domain, matching
// Snoop_Addr's domain exactly, regardless of this core's own page
// table.
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
// actually valid. PTW reads use Mem_ReadDataValidM; Accessed/Dirty
// PTE writes use Mem_WriteDoneM. The wrapper selects the completion
// source from ptw_mem_we while mmu_busy owns the D-memory bus.
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
    parameter          MMU_CTRL_FROM_CSR       = 0,

    // Permission context used only in external-control mode. The
    // integrated system instead takes privilege/SUM/MXR from CSRs.
    parameter [1:0]    EXTERNAL_PRIV            = 2'b01,
    parameter          EXTERNAL_SUM             = 0,
    parameter          EXTERNAL_MXR             = 0,

    // Optional coarse VA-region guard and trace storage from
    // mmu_top.  Both default off for backward compatibility and so
    // board bitstreams contain no debug buffer unless requested.
    parameter          MMU_REGION_POLICY_ENABLE = 0,
    parameter          MMU_DEBUG_TRACE_ENABLE   = 0,

    // Set only when the downstream data path is l1_dcache.  In that
    // configuration PTW A/D updates are emitted as a coherent AMOOR.W
    // of bits A/D, so another hart cannot have its concurrent PTE edit
    // overwritten by the PTW's earlier read value. Direct AXI/simple
    // RAM users keep the legacy full-word write by leaving this zero.
    parameter          PTW_ATOMIC_AD_ENABLE     = 0,

    // Zero removes the diagnostic counter. A non-zero value latches an
    // internal mark_debug flag if one PTW transaction waits this long.
    parameter integer  MMU_PTW_WATCHDOG_CYCLES = 0
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        Stall_Core_External,

    // MMU control
    input  wire        Mmu_Enable,
    input  wire [19:0] Satp_PPN,     // physical page number of the root page table
    input  wire        Mmu_Flush,    // pulse to invalidate all TLBs; safe even during a PTW

    // Snoop for LR/SC (see NOTE above: physical domain)
    input  wire [31:0] Snoop_Addr,
    input  wire        Snoop_WE,

    // IF (physical address out)
    output wire [31:0] PCF,
    input  wire [31:0] InstrF,
    input  wire        Instr_ValidF,      // 1 exactly when InstrF is valid for PCF
    input  wire        Instr_ErrorF,      // valid with Instr_ValidF; instruction access failed

    // Memory bus (physical address out)
    output wire [31:0] Mem_AddrM,
    output wire [31:0] Mem_WriteDataM,
    output wire        Mem_WriteEnM,
    output wire        Mem_ReadEnM,
    output wire [2:0]  MemOpM,
    output wire        Mem_AmoRmwM,
    output wire [4:0]  Mem_AmoOpM,
    output wire [31:0] Mem_AmoOperandM,
    input  wire [31:0] Mem_ReadDataM,
    input  wire        Mem_ReadDataValidM, // 1 exactly when Mem_ReadDataM is valid for Mem_AddrM
    input  wire        Mem_WriteDoneM,     // 1 exactly when the store at Mem_AddrM has completed
    input  wire        Mem_ReadErrorM,     // valid with Mem_ReadDataValidM
    input  wire        Mem_WriteErrorM,    // valid with Mem_WriteDoneM

    // Debug / WB
    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug,

    // MMU status
    output wire        Fetch_PageFault,
    output wire        Data_PageFault,
    output wire        Fetch_AccessFault,
    output wire        Data_AccessFault,
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
    output wire        Mmu_Flush_Csr,
    output wire        FenceI_M
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
    wire        mem_amo_core;
    wire [4:0]  mem_amo_op_core;
    wire [31:0] mem_amo_operand_core;
    wire [31:0] mem_rdata_to_core;

    wire mem_req_core = mem_re_core | mem_we_core;
    // A cache hit may complete while the pipeline remains frozen for an
    // unrelated instruction miss or external maintenance operation.  Remember
    // that completion so a level-held M-stage store/AMO is not issued again on
    // every stalled cycle.  The bit clears exactly when the pipeline can
    // advance, which also permits truly back-to-back identical accesses.
    reg  core_data_completed;

    // ------------------------------------------------------
    // MMU
    // ------------------------------------------------------
    wire [31:0] pa_fetch;
    wire [31:0] pa_mem;
    wire        fetch_fault;
    wire        mem_fault;
    wire        mmu_fetch_access_fault;
    wire        mmu_mem_access_fault;
    wire        mmu_busy;

    wire        ptw_mem_req;
    wire        ptw_mem_we;
    wire [31:0] ptw_mem_addr;
    wire [31:0] ptw_mem_wdata;
    wire        mstatus_sum_csr;
    wire        mstatus_mxr_csr;

    // Kept as internal observability nets.  A simulation testbench or
    // an FPGA ILA can reach these hierarchically without widening the
    // stable core wrapper interface.
    wire [79:0] mmu_debug_trace_data;
    wire [4:0]  mmu_debug_trace_count;
    wire [3:0]  mmu_debug_trace_write_index;
    wire [1:0]  mmu_debug_controller_state;
    wire [2:0]  mmu_debug_fetch_region;
    wire [2:0]  mmu_debug_mem_region;
    (* mark_debug = "true" *) wire mmu_ptw_timeout_error;

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
    wire [1:0]  mmu_priv_eff   = MMU_CTRL_FROM_CSR ? CurrentPriv : EXTERNAL_PRIV;
    wire        mmu_sum_eff    = MMU_CTRL_FROM_CSR ? mstatus_sum_csr : EXTERNAL_SUM;
    wire        mmu_mxr_eff    = MMU_CTRL_FROM_CSR ? mstatus_mxr_csr : EXTERNAL_MXR;
    wire        ptw_mem_valid  = ptw_mem_we ? Mem_WriteDoneM : Mem_ReadDataValidM;
    wire        ptw_mem_error  = ptw_mem_we ? Mem_WriteErrorM : Mem_ReadErrorM;

    mmu_top #(
        .REGION_POLICY_ENABLE(MMU_REGION_POLICY_ENABLE),
        .DEBUG_TRACE_ENABLE(MMU_DEBUG_TRACE_ENABLE),
        .PTW_WATCHDOG_CYCLES(MMU_PTW_WATCHDOG_CYCLES)
    ) mmu (
        .clk(clk), .rst(rst),

        .mmu_enable(mmu_enable_eff),
        .satp_ppn(satp_ppn_eff),
        .flush(mmu_flush_eff),
        .current_priv(mmu_priv_eff),
        .mstatus_sum(mmu_sum_eff),
        .mstatus_mxr(mmu_mxr_eff),

        .va_fetch(pcf_va),
        .pa_fetch(pa_fetch),

        .va_mem(mem_addr_va),
        .mem_req(mem_req_core),
        .mem_is_store(mem_we_core),
        .pa_mem(pa_mem),

        .fetch_fault(fetch_fault),
        .mem_fault(mem_fault),
        .fetch_access_fault(mmu_fetch_access_fault),
        .mem_access_fault(mmu_mem_access_fault),
        .fetch_fault_cause(Fetch_PageFault_Cause),
        .mem_fault_cause(Data_PageFault_Cause),

        .ptw_mem_req(ptw_mem_req),
        .ptw_mem_we(ptw_mem_we),
        .ptw_mem_addr(ptw_mem_addr),
        .ptw_mem_wdata(ptw_mem_wdata),
        .ptw_mem_rdata(Mem_ReadDataM),
        .ptw_mem_valid(ptw_mem_valid),
        .ptw_mem_error(ptw_mem_error),

        .busy(mmu_busy),

        .debug_trace_rd_index(4'b0000),
        .debug_trace_rd_data(mmu_debug_trace_data),
        .debug_trace_count(mmu_debug_trace_count),
        .debug_trace_write_index(mmu_debug_trace_write_index),
        .debug_controller_state(mmu_debug_controller_state),
        .debug_fetch_region(mmu_debug_fetch_region),
        .debug_mem_region(mmu_debug_mem_region),
        .ptw_timeout_error(mmu_ptw_timeout_error)
    );

    assign Fetch_PageFault = fetch_fault;
    assign Data_PageFault  = mem_fault;

    // A failed page-table access is reported by mmu_top at T_GATE.
    // Normal fetch/load/store response errors are accepted only with
    // their matching completion pulse and only while the core, not the
    // PTW, owns that memory channel.
    wire core_fetch_access_fault = ~mmu_busy & Instr_ValidF & Instr_ErrorF;
    wire core_data_access_fault = ~mmu_busy &
                                  ((mem_re_core & Mem_ReadDataValidM & Mem_ReadErrorM) |
                                   (mem_we_core & Mem_WriteDoneM & Mem_WriteErrorM));
    assign Fetch_AccessFault = mmu_fetch_access_fault | core_fetch_access_fault;
    assign Data_AccessFault  = mmu_mem_access_fault | core_data_access_fault;

    // ------------------------------------------------------
    // Multi-cycle memory stall (see header NOTE). While mmu_busy,
    // Mem_AddrM/Mem_ReadEnM belong to the PTW, whose own completion
    // is already gated by ptw_mem_valid above and by mmu_busy
    // itself -- so these two only need to fire for the core's OWN,
    // non-PTW fetch/load/store traffic, i.e. exactly when NOT busy.
    // mem_re_core/mem_we_core/pcf_va all stay parked while the core is
    // frozen. core_data_completed remembers a data response if some
    // independent fetch/maintenance stall keeps that same M-stage
    // request parked afterwards; its bus enables are then suppressed
    // so stores and AMOs cannot be accepted twice.
    // ------------------------------------------------------
    // NOTE: completion waits use the effective, fault-gated requests,
    // not raw mem_we_core/mem_re_core. A translation or PTW access
    // fault suppresses both loads and stores, so neither may wait for
    // a bus completion that will never be requested. A direct physical
    // bus error is different: its matching completion has arrived.
    wire core_store_req = mem_we_core & ~mem_fault & ~mmu_mem_access_fault;
    wire core_load_req  = mem_re_core & ~mem_fault & ~mmu_mem_access_fault;
    wire fetch_wait = ~mmu_busy & ~fetch_fault & ~mmu_fetch_access_fault &
                      ~Instr_ValidF;
    wire data_wait  = ~mmu_busy & ~core_data_completed &
                      (core_store_req ? ~Mem_WriteDoneM :
                       core_load_req  ? ~Mem_ReadDataValidM :
                                        1'b0);
    wire mem_stall  = fetch_wait | data_wait;
    wire core_pipeline_stall = Stall_Core_External | mmu_busy | mem_stall;
    wire core_data_response = ~mmu_busy & ~core_data_completed &
                              ((core_store_req & Mem_WriteDoneM) |
                               (core_load_req  & Mem_ReadDataValidM));

    always @(posedge clk) begin
        if (rst)
            core_data_completed <= 1'b0;
        else if (!core_pipeline_stall)
            core_data_completed <= 1'b0;
        else if (core_data_response)
            core_data_completed <= 1'b1;
        else if (!mem_req_core)
            core_data_completed <= 1'b0;
    end

    // ------------------------------------------------------
    // Instruction side: pure passthrough. Reads have no side
    // effects, so it is safe to always drive the translated (or
    // raw, if disabled) address out; the fetched instruction is
    // only forced to a NOP if the fetch that was frozen on this
    // VA turned out to fault once resolved.
    // ------------------------------------------------------
    assign PCF            = pa_fetch;
    assign instrf_to_core = (fetch_fault | Fetch_AccessFault) ?
                            32'h0000_0013 : InstrF;

    // ------------------------------------------------------
    // Data side: while the MMU is busy (walking either side),
    // the external bus belongs to the PTW, not the core. Once
    // idle, the core's own request goes out translated, with a
    // faulting access blocked (store suppressed / load data
    // zeroed) on its one-cycle resume/gate window.
    // ------------------------------------------------------
    assign Mem_AddrM      = mmu_busy ? ptw_mem_addr : pa_mem;
    assign Mem_ReadEnM    = mmu_busy ? (ptw_mem_req & ~ptw_mem_we) :
                                      (mem_re_core & ~core_data_completed);
    assign Mem_WriteEnM   = mmu_busy ? (ptw_mem_req &  ptw_mem_we) :
                                      (core_store_req & ~core_data_completed);
    assign MemOpM         = mmu_busy ? 3'b010        : memop_core;
    assign Mem_WriteDataM = mmu_busy ? ptw_mem_wdata : mem_wdata_core;

    // The PTW is the sole owner of the D-memory port while mmu_busy.
    // Never leak a stalled core AMO onto a PTE read/write. On the
    // coherent cached path, turn the A/D write into AMOOR.W with only
    // the A/D mask as operand; l1_dcache then performs one serialized
    // read-modify-write after obtaining M ownership. The full updated
    // PTE remains on Mem_WriteDataM for non-AMO downstream users.
    assign Mem_AmoRmwM = mmu_busy ?
                         (PTW_ATOMIC_AD_ENABLE && ptw_mem_req && ptw_mem_we) :
                         mem_amo_core;
    assign Mem_AmoOpM = mmu_busy ? 5'b01000 : mem_amo_op_core; // AMOOR.W
    assign Mem_AmoOperandM = mmu_busy ? (ptw_mem_wdata & 32'h0000_00C0) :
                                      mem_amo_operand_core;

    assign mem_rdata_to_core = (mem_fault | Data_AccessFault) ?
                               32'b0 : Mem_ReadDataM;

    // ------------------------------------------------------
    // Core (virtual-address world)
    // ------------------------------------------------------
    RV32IMA #(
        .RESET_ADDR(RESET_ADDR)
    ) core (
        .clk                (clk),
        .rst                (rst),
        .Stall_Core_External(core_pipeline_stall),

        .Snoop_Addr         (Snoop_Addr),
        .Snoop_WE           (Snoop_WE),

        .PCF                (pcf_va),
        .InstrF             (instrf_to_core),

        .Mem_AddrM          (mem_addr_va),
        .Mem_WriteDataM     (mem_wdata_core),
        .Mem_WriteEnM       (mem_we_core),
        .Mem_ReadEnM        (mem_re_core),
        .MemOpM             (memop_core),
        .Mem_AmoRmwM        (mem_amo_core),
        .Mem_AmoOpM         (mem_amo_op_core),
        .Mem_AmoOperandM    (mem_amo_operand_core),
        .Mem_ReadDataM      (mem_rdata_to_core),

        // LR/SC VA-vs-PA fix (see memory_stage.v/RV32IMA.v headers):
        // pa_mem is this exact cycle's already-computed physical
        // translation of mem_addr_va -- valid and stable whenever the
        // core is not frozen (mmu_busy=0), which is exactly when an
        // LR/SC in M-stage would actually retire and need it. This is
        // the ONE place in the whole design that turns the bug into a
        // real fix: every other RV32IMA instantiation site has no MMU
        // at all (VA=PA transparently) and just loops Mem_AddrM back
        // into this same port instead.
        .Mem_PhysAddrM      (pa_mem),

        // NEW: feed the MMU's own already-computed fault flags
        // straight into the core's trap unit -- see RV32IMA.v's port
        // comment. This is the SAME fetch_fault/mem_fault this
        // wrapper already exposes as Fetch_PageFault/Data_PageFault
        // above; now it ALSO reaches the core internally, so a page
        // fault actually traps instead of only forcing a NOP/
        // blocking a store with nowhere for software to catch it.
        .Fetch_PageFault_In (fetch_fault),
        .Data_PageFault_In  (mem_fault),
        .Fetch_AccessFault_In(Fetch_AccessFault),
        .Data_AccessFault_In (Data_AccessFault),

        .ResultW            (ResultW),
        .ALU_ResultE_Debug  (ALU_ResultE_Debug),

        .CurrentPriv        (CurrentPriv),
        .Mmu_Enable_Csr     (Mmu_Enable_Csr),
        .Satp_PPN_Csr       (Satp_PPN_Csr),
        .Mstatus_Sum         (mstatus_sum_csr),
        .Mstatus_Mxr         (mstatus_mxr_csr),
        .Mmu_Flush_Csr      (Mmu_Flush_Csr),
        .FenceI_M           (FenceI_M)
    );

endmodule
