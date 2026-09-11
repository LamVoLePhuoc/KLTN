`timescale 1ns / 1ps

module RV32IMA #(
    parameter [31:0] RESET_ADDR = 32'h0000_1000
)(
    input  wire        clk,
    input  wire        rst,                  // active-high
    input  wire        Stall_Core_External,

    // Snoop for LR/SC
    input  wire [31:0] Snoop_Addr,
    input  wire        Snoop_WE,

    // IF
    output wire [31:0] PCF,
    input  wire [31:0] InstrF,

    // Memory bus
    output wire [31:0] Mem_AddrM,
    output wire [31:0] Mem_WriteDataM,
    output wire        Mem_WriteEnM,
    output wire        Mem_ReadEnM,
    output wire [2:0]  MemOpM,
    input  wire [31:0] Mem_ReadDataM,

    // NEW: trap/exception unit inputs -- page faults from whatever
    // MMU sits between this core and Mem_*/PCF/InstrF (mmu_core_wrapper.v
    // today). Fetch_PageFault_In feeds if_id_registers.v so the fault
    // tags travel D->E->M in lockstep with the (already NOP-forced)
    // instruction it belongs to; Data_PageFault_In is consumed
    // directly at M-stage timing since mmu_core_wrapper.v already
    // pulses it exactly when the faulting access resolves at the
    // memory-stage boundary, no extra alignment needed.
    input  wire         Fetch_PageFault_In,
    input  wire         Data_PageFault_In,

    // Debug / WB
    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug,

    // NEW: csr_trap_unit.v observability + future MMU integration
    // hooks -- see that file's header for why Satp_PPN_Csr/
    // Mmu_Enable_Csr/Mmu_Flush_Csr are exposed but not yet actually
    // wired to drive translation anywhere in this session's changes.
    output wire [1:0]  CurrentPriv,
    output wire        Mmu_Enable_Csr,
    output wire [19:0] Satp_PPN_Csr,
    output wire        Mmu_Flush_Csr
);

    // =========================================================
    // INTERNAL WIRES
    // =========================================================

    // Hazard / pipeline control
    wire StallF, StallD, StallE;
    wire FlushD, FlushE, FlushM;

    // Forwarding
    wire [1:0] ForwardAE, ForwardBE;

    // IF / ID
    wire [31:0] PCPlus4F;
    wire [31:0] InstrD, PCD, PCPlus4D;
    wire        FetchPageFaultD;               // NEW

    // Decode outputs
    wire        RegWriteD;
    wire        ALUSrcD;
    wire [1:0]  ALUSrcA_D;
    wire        MemWriteD, MemReadD;
    wire [1:0]  ResultSrcD;
    wire        BranchD, JumpD;
    wire [4:0]  ALUControlD;
    wire [2:0]  ImmSrcD, MemOpD;
    wire        AtomicD, CSR_D, Fence_D;
    wire [4:0]  AmoOpD;        // NEW: RV32A funct5

    // NEW: privileged sub-decode (sys_decoder.v, via decode_stage.v)
    wire        IsEcallD, IsEbreakD, IsMretD, IsSretD, IsSfenceVmaD, IsPrivIllegalD, IsIllegalOpD;
    wire [7:0]  ExcFlagsD; // {FetchPageFaultD, IsEcallD, IsEbreakD, IsMretD, IsSretD, IsSfenceVmaD, IsPrivIllegalD, IsIllegalOpD}

    wire [31:0] RD1_D, RD2_D;
    wire [31:0] Imm_Ext_D;

    wire [4:0]  RD_D, RS1_D, RS2_D;

    // ID / EX outputs
    wire        RegWriteE;
    wire        ALUSrcE;
    wire [1:0]  ALUSrcA_E;
    wire        MemWriteE, MemReadE;
    wire [1:0]  ResultSrcE;
    wire        BranchE, JumpE;
    wire [4:0]  ALUControlE;
    wire [2:0]  MemOpE;
    wire        AtomicE, CSR_E, Fence_E;
    wire [4:0]  AmoOpE;        // NEW: RV32A funct5 in EX
    wire [6:0]  OpE;
    wire [7:0]  ExcFlagsE;     // NEW
    wire [31:0] InstrE;        // NEW

    wire [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E;

    wire [4:0]  RD_E, RS1_E, RS2_E;

    // Execute
    wire [31:0] ALUResultE, WriteDataE, PCTargetE;
    wire [31:0] CsrWDataE;     // NEW
    wire        PCSrcE;
    wire        ZeroE, NegativeE, CarryE, OverFlowE;
    wire        Stall_MDU_Req;

    // EX / MEM outputs
    wire        RegWriteM;
    wire        MemWriteM, MemReadM;
    wire [1:0]  ResultSrcM;
    wire        AtomicM, CSR_M, Fence_M;
    wire [4:0]  AmoOpM;        // NEW: RV32A funct5 in MEM
    wire [7:0]  ExcFlagsM;     // NEW
    wire [31:0] InstrM;        // NEW
    wire [31:0] CsrWDataM;     // NEW

    wire [4:0]  RD_M;
    wire [31:0] PCPlus4M, ALUResultM, WriteDataM;

    // Memory stage
    wire [31:0] ReadDataM;
    wire [2:0]  Mem_BusOpM_unused;

    // MEM / WB outputs
    wire        RegWriteW;
    wire [1:0]  ResultSrcW;
    wire [4:0]  RD_W;
    wire [31:0] PCPlus4W_Pipe, ALU_ResultW_Pipe, ReadDataW_Pipe, CsrRDataW_Pipe;

    // NEW: csr_trap_unit.v <-> pipeline
    wire [31:0] CsrRDataM;
    wire        TrapTakenM;
    wire [31:0] TrapPCM;
    wire [31:0] PCM;   // = PCPlus4M - 4 (no compressed instructions, so this is exact)
                        // rather than threading a whole new PCE/PCM field through
                        // id_ex_registers.v/ex_mem_registers.v just for this.

    // Branch type pipeline helper
    wire [2:0] BranchTypeD;
    reg  [2:0] BranchTypeE;

    // Decode-stage opcode helper
    wire [6:0] OpD;

    assign OpD               = InstrD[6:0];
    assign BranchTypeD       = InstrD[14:12];
    assign ALU_ResultE_Debug = ALUResultE;

    // Pipeline helper for branch funct3 because current id_ex_registers
    // does not carry BranchType yet.
    always @(posedge clk) begin
        if (rst) begin
            BranchTypeE <= 3'b000;
        end
        else if (FlushE) begin
            BranchTypeE <= 3'b000;
        end
        else if (!(StallE | Stall_Core_External)) begin
            BranchTypeE <= BranchTypeD;
        end
    end

    // =========================================================
    // NEW: trap redirect override
    //
    // TrapTakenM (an older, M-stage instruction) always wins over
    // PCSrcE (a younger, E-stage branch/jump resolving the same
    // cycle) -- the younger instruction is being flushed away by
    // this same trap anyway, so redirecting to its branch target
    // first would just be immediately overwritten and discarded.
    // Overriding the WIRES fed into fetch_stage/if_id_registers/
    // id_ex_registers here, rather than fetch_stage.v/hazard_unit.v
    // themselves, means neither of those (already-synthesized) files
    // needs to change -- their existing 2-way muxes already do
    // exactly what's needed once these upstream signals are correct.
    // =========================================================
    wire        PCSrcE_eff    = PCSrcE | TrapTakenM;
    wire [31:0] PCTargetE_eff = TrapTakenM ? TrapPCM : PCTargetE;
    wire        FlushD_eff    = FlushD | TrapTakenM;

    // NEW (bug found reviewing tb_csr_trap.v, before it was ever run):
    // the existing "forward from M" path (execute_stage.v's
    // forward_a_mux/forward_b_mux, fed by ALUResultM) only knows how
    // to forward an ALU result -- it has no idea ResultSrcM can now
    // also mean "the CSR read value" (ResultSrc=2'b11). A CSR
    // instruction immediately followed by one that consumes its rd
    // (e.g. `csrrs x31,mepc,x0` then `addi x31,x31,4`, exactly what
    // this session's own trap-handler test program does) would
    // silently forward garbage instead of CsrRDataM. Teaching
    // execute_stage.v's forward muxes a 4th source would work, but
    // this repo already has a proven, simpler answer for exactly
    // this shape of problem: hazard_unit.v's load_use_hazard already
    // stalls F/D and bubbles E for one cycle whenever a LOAD's
    // result is needed immediately, specifically so the consumer
    // reads it one cycle later via the (already-correct, since
    // writeback_stage.v's own mux already handles every ResultSrc
    // case including CSR) "forward from W" path instead of ever
    // needing an M-stage forward at all. Reusing that same idiom
    // here for a CSR producer -- computed and OR'd in at this same
    // top-level-override boundary, not inside hazard_unit.v itself --
    // sidesteps the gap entirely rather than growing the ALU-only
    // forwarding mux to also understand CSR results.
    wire csr_load_use_hazard = CSR_E & RegWriteE & (RD_E != 5'd0) &
                                ((RD_E == RS1_D) | (RD_E == RS2_D));

    wire StallF_eff = StallF | csr_load_use_hazard;
    wire StallD_eff = StallD | csr_load_use_hazard;
    wire FlushE_eff = FlushE | TrapTakenM | csr_load_use_hazard;

    // =========================================================
    // 1. FETCH
    // =========================================================
    fetch_stage #(
        .RESET_ADDR(RESET_ADDR)
    ) fetch_unit (
        .clk      (clk),
        .rst      (rst),
        .stall    (StallF_eff | Stall_Core_External),
        .bus_ready(~Stall_Core_External),
        .PCSrcE   (PCSrcE_eff),
        .PCTargetE(PCTargetE_eff),
        .PCF      (PCF),
        .PCPlus4F (PCPlus4F)
    );

    // =========================================================
    // 2. IF / ID
    // =========================================================
    if_id_registers if_id (
        .clk            (clk),
        .rst            (rst),
        .stall          (StallD_eff | Stall_Core_External),
        .flush          (FlushD_eff),
        .InstrF         (InstrF),
        .PCF            (PCF),
        .PCPlus4F       (PCPlus4F),
        .FetchPageFaultF(Fetch_PageFault_In),
        .InstrD         (InstrD),
        .PCD            (PCD),
        .PCPlus4D       (PCPlus4D),
        .FetchPageFaultD(FetchPageFaultD)
    );

    // =========================================================
    // 3. DECODE
    // =========================================================
    decode_stage decode_unit (
        .clk         (clk),
        .rst         (rst),

        .InstrD      (InstrD),
        .PCD         (PCD),
        .PCPlus4D    (PCPlus4D),

        .RegWriteW   (RegWriteW),
        .RD_W        (RD_W),
        .ResultW     (ResultW),

        .RegWriteD   (RegWriteD),
        .ALUSrcD     (ALUSrcD),
        .ALUSrcA_D   (ALUSrcA_D),
        .MemWriteD   (MemWriteD),
        .MemReadD    (MemReadD),
        .ResultSrcD  (ResultSrcD),
        .BranchD     (BranchD),
        .JumpD       (JumpD),
        .ALUControlD (ALUControlD),
        .ImmSrcD     (ImmSrcD),
        .MemOpD      (MemOpD),
        .AtomicD     (AtomicD),
        .AmoOpD      (AmoOpD),      // NEW
        .CSR_D       (CSR_D),
        .Fence_D     (Fence_D),

        .IsEcallD      (IsEcallD),      // NEW
        .IsEbreakD     (IsEbreakD),     // NEW
        .IsMretD       (IsMretD),       // NEW
        .IsSretD       (IsSretD),       // NEW
        .IsSfenceVmaD  (IsSfenceVmaD),  // NEW
        .IsPrivIllegalD(IsPrivIllegalD),// NEW
        .IsIllegalOpD  (IsIllegalOpD),  // NEW

        .RD1_D       (RD1_D),
        .RD2_D       (RD2_D),

        .Imm_Ext_D   (Imm_Ext_D),
        .PCD_Out     (),
        .PCPlus4D_Out(),

        .RD_D        (RD_D),
        .RS1_D       (RS1_D),
        .RS2_D       (RS2_D)
    );

    // NEW: pack the D-stage exception tags into one bus purely to
    // keep id_ex_registers.v's/ex_mem_registers.v's port count down
    // -- see id_ex_registers.v's port comment for the bit assignment
    // (unpacked back into named signals below, at csr_trap_unit.v).
    assign ExcFlagsD = { FetchPageFaultD, IsEcallD, IsEbreakD, IsMretD,
                          IsSretD, IsSfenceVmaD, IsPrivIllegalD, IsIllegalOpD };

    // =========================================================
    // 4. ID / EX
    // =========================================================
    id_ex_registers id_ex (
        .clk         (clk),
        .rst         (rst),
        .stall       (StallE | Stall_Core_External),
        .flush       (FlushE_eff),

        .ExcFlagsD   (ExcFlagsD),   // NEW
        .InstrD      (InstrD),      // NEW

        .RegWriteD   (RegWriteD),
        .ALUSrcD     (ALUSrcD),
        .ALUSrcA_D   (ALUSrcA_D),
        .MemWriteD   (MemWriteD),
        .MemReadD    (MemReadD),
        .ResultSrcD  (ResultSrcD),
        .BranchD     (BranchD),
        .JumpD       (JumpD),
        .ALUControlD (ALUControlD),
        .AtomicD     (AtomicD),
        .AmoOpD      (AmoOpD),      // NEW
        .MemOpD      (MemOpD),
        .CSR_D       (CSR_D),
        .Fence_D     (Fence_D),
        .OpD         (OpD),

        .RD1_D       (RD1_D),
        .RD2_D       (RD2_D),
        .Imm_Ext_D   (Imm_Ext_D),
        .PCD         (PCD),
        .PCPlus4D    (PCPlus4D),

        .RD_D        (RD_D),
        .RS1_D       (RS1_D),
        .RS2_D       (RS2_D),

        .RegWriteE   (RegWriteE),
        .ALUSrcE     (ALUSrcE),
        .ALUSrcA_E   (ALUSrcA_E),
        .MemWriteE   (MemWriteE),
        .MemReadE    (MemReadE),
        .ResultSrcE  (ResultSrcE),
        .BranchE     (BranchE),
        .JumpE       (JumpE),
        .ALUControlE (ALUControlE),
        .AtomicE     (AtomicE),
        .AmoOpE      (AmoOpE),      // NEW
        .MemOpE      (MemOpE),
        .CSR_E       (CSR_E),
        .Fence_E     (Fence_E),
        .OpE         (OpE),

        .ExcFlagsE   (ExcFlagsE),   // NEW
        .InstrE      (InstrE),      // NEW

        .RD1_E       (RD1_E),
        .RD2_E       (RD2_E),
        .Imm_Ext_E   (Imm_Ext_E),
        .PCE         (PCE),
        .PCPlus4E    (PCPlus4E),

        .RD_E        (RD_E),
        .RS1_E       (RS1_E),
        .RS2_E       (RS2_E)
    );

    // =========================================================
    // 5. EXECUTE
    // =========================================================
    execute_stage execute_unit (
        .clk          (clk),
        .rst          (rst),

        .RD1_E        (RD1_E),
        .RD2_E        (RD2_E),
        .PCE          (PCE),
        .PCPlus4E     (PCPlus4E),
        .Imm_Ext_E    (Imm_Ext_E),

        .ALUControlE  (ALUControlE),
        .ALUSrcE      (ALUSrcE),
        .ALUSrcA_E    (ALUSrcA_E),
        .AtomicE      (AtomicE),
        .ResultSrcE   (ResultSrcE),
        .MemWriteE    (MemWriteE),

        .BranchE      (BranchE),
        .JumpE        (JumpE),
        .BranchTypeE  (BranchTypeE),
        .OpE          (OpE),
        .MemOpE       (MemOpE),      // NEW

        .ForwardA_E   (ForwardAE),
        .ForwardB_E   (ForwardBE),
        .ResultW      (ResultW),
        .ALUResultM   (ALUResultM),

        .Stall_MDU_Req(Stall_MDU_Req),

        .ALUResultE   (ALUResultE),
        .WriteDataE   (WriteDataE),
        .CsrWDataE    (CsrWDataE),   // NEW
        .PCTargetE    (PCTargetE),
        .PCSrcE       (PCSrcE),

        .ZeroE        (ZeroE),
        .NegativeE    (NegativeE),
        .CarryE       (CarryE),
        .OverFlowE    (OverFlowE)
    );

    // =========================================================
    // 6. EX / MEM
    // =========================================================
    ex_mem_registers ex_mem (
        .clk         (clk),
        .rst         (rst),
        .stall       (Stall_Core_External),
        .flush       (FlushM),

        .RegWriteE   (RegWriteE),
        .MemWriteE   (MemWriteE),
        .MemReadE    (MemReadE),
        .ResultSrcE  (ResultSrcE),
        .AtomicE     (AtomicE),
        .AmoOpE      (AmoOpE),      // NEW
        .MemOpE      (MemOpE),
        .CSR_E       (CSR_E),
        .Fence_E     (Fence_E),

        .ExcFlagsE   (ExcFlagsE),   // NEW
        .InstrE      (InstrE),      // NEW
        .CsrWDataE   (CsrWDataE),   // NEW

        .RD_E        (RD_E),
        .PCPlus4E    (PCPlus4E),
        .ALU_ResultE (ALUResultE),
        .WriteDataE  (WriteDataE),

        .RegWriteM   (RegWriteM),
        .MemWriteM   (MemWriteM),
        .MemReadM    (MemReadM),
        .ResultSrcM  (ResultSrcM),
        .AtomicM     (AtomicM),
        .AmoOpM      (AmoOpM),      // NEW
        .MemOpM      (MemOpM),
        .CSR_M       (CSR_M),
        .Fence_M     (Fence_M),

        .ExcFlagsM   (ExcFlagsM),   // NEW
        .InstrM      (InstrM),      // NEW
        .CsrWDataM   (CsrWDataM),   // NEW

        .RD_M        (RD_M),
        .PCPlus4M    (PCPlus4M),
        .ALU_ResultM (ALUResultM),
        .WriteDataM  (WriteDataM)
    );

    // =========================================================
    // 7. MEMORY
    // =========================================================
    memory_stage memory_unit (
        .clk           (clk),
        .rst           (rst),

        .MemWriteM     (MemWriteM),
        .MemReadM      (MemReadM),
        .AtomicM       (AtomicM),
        .AmoOpM        (AmoOpM),    // NEW
        .MemOpM        (MemOpM),

        .ALU_ResultM   (ALUResultM),
        .WriteDataM    (WriteDataM),

        .Snoop_Addr    (Snoop_Addr),
        .Snoop_WE      (Snoop_WE),

        .bus_addr      (Mem_AddrM),
        .bus_write_data(Mem_WriteDataM),
        .bus_mem_write (Mem_WriteEnM),
        .bus_mem_read  (Mem_ReadEnM),
        .bus_mem_op    (Mem_BusOpM_unused),
        .bus_read_data (Mem_ReadDataM),

        .ReadDataM     (ReadDataM)
    );

    // QUAN TRỌNG:
    // KHÔNG được assign MemOpM = Mem_BusOpM_unused.
    // MemOpM đã được drive bởi ex_mem_registers.
    // Mem_BusOpM_unused chỉ là output phụ từ memory_stage.

    // =========================================================
    // 7b. CSR / TRAP / PRIVILEGE (NEW)
    // =========================================================
    wire FetchPageFaultM, IsEcallM, IsEbreakM, IsMretM, IsSretM,
         IsSfenceVmaM, IsPrivIllegalM, IsIllegalOpM;
    assign { FetchPageFaultM, IsEcallM, IsEbreakM, IsMretM,
             IsSretM, IsSfenceVmaM, IsPrivIllegalM, IsIllegalOpM } = ExcFlagsM;

    assign PCM = PCPlus4M - 32'd4;

    csr_trap_unit #(
        .HART_ID(32'd0)   // NOTE: quad_core_soc.v does not yet thread a
                           // distinct per-core hart ID down to here -- all
                           // 4 cores currently read mhartid as 0. A small,
                           // well-defined follow-up (add a HART_ID parameter
                           // to mmu_core_wrapper.v/core_l1_wrapper.v and
                           // pass 0/1/2/3 from quad_core_soc.v), not done in
                           // this pass for the same reason satp isn't wired
                           // to the MMU yet -- see this file's other NOTEs.
    ) csr_trap (
        .clk(clk), .rst(rst),
        .Stall_Core_External(Stall_Core_External),

        .CsrOpM     (CSR_M),
        .CsrFunct3M (MemOpM),      // reused -- see execute_stage.v's CsrWDataE comment
        .CsrAddrM   (InstrM[31:20]),
        .CsrWDataM  (CsrWDataM),
        .CsrRDataM  (CsrRDataM),

        .IsEcallM      (IsEcallM),
        .IsEbreakM     (IsEbreakM),
        .IsMretM       (IsMretM),
        .IsSretM       (IsSretM),
        .IsSfenceVmaM  (IsSfenceVmaM),
        .IsPrivIllegalM(IsPrivIllegalM),
        .IsIllegalOpM  (IsIllegalOpM),

        .MemReadM  (MemReadM),
        .MemWriteM (MemWriteM),
        .FetchPageFaultM(FetchPageFaultM),
        .DataPageFaultM (Data_PageFault_In),
        .PCM     (PCM),
        .InstrM  (InstrM),
        .MemAddrM(ALUResultM),

        .TrapTakenM(TrapTakenM),
        .TrapPCM   (TrapPCM),

        .CurrentPriv   (CurrentPriv),
        .Mmu_Enable_Csr(Mmu_Enable_Csr),
        .Satp_PPN_Csr  (Satp_PPN_Csr),
        .Mmu_Flush_Csr (Mmu_Flush_Csr)
    );

    // =========================================================
    // 8. MEM / WB
    // =========================================================
    mem_wb_registers mem_wb (
        .clk         (clk),
        .rst         (rst),
        .stall       (Stall_Core_External),
        .flush       (1'b0),

        .RegWriteM   (RegWriteM),
        .ResultSrcM  (ResultSrcM),
        .RD_M        (RD_M),
        .PCPlus4M    (PCPlus4M),
        .ALU_ResultM (ALUResultM),
        .ReadDataM   (ReadDataM),
        .CsrRDataM   (CsrRDataM),      // NEW

        .RegWriteW   (RegWriteW),
        .ResultSrcW  (ResultSrcW),
        .RD_W        (RD_W),
        .PCPlus4W    (PCPlus4W_Pipe),
        .ALU_ResultW (ALU_ResultW_Pipe),
        .ReadDataW   (ReadDataW_Pipe),
        .CsrRDataW   (CsrRDataW_Pipe)  // NEW
    );

    // =========================================================
    // 9. WRITEBACK
    // =========================================================
    writeback_stage writeback_unit (
        .ResultSrcW  (ResultSrcW),
        .ALU_ResultW (ALU_ResultW_Pipe),
        .ReadDataW   (ReadDataW_Pipe),
        .PCPlus4W    (PCPlus4W_Pipe),
        .CsrRDataW   (CsrRDataW_Pipe), // NEW
        .ResultW     (ResultW)
    );

    // =========================================================
    // 10. HAZARD
    // =========================================================
    hazard_unit hz_unit (
        .Rs1_D        (RS1_D),
        .Rs2_D        (RS2_D),

        .Rs1_E        (RS1_E),
        .Rs2_E        (RS2_E),

        .RD_E         (RD_E),

        .MemReadE     (MemReadE),
        .RegWriteE    (RegWriteE),

        .PCSrcE       (PCSrcE),
        .Stall_MDU_Req(Stall_MDU_Req),

        .RegWriteM    (RegWriteM),
        .RD_M         (RD_M),

        .RegWriteW    (RegWriteW),
        .RD_W         (RD_W),

        .ForwardAE    (ForwardAE),
        .ForwardBE    (ForwardBE),

        .StallF       (StallF),
        .StallD       (StallD),
        .StallE       (StallE),
        .FlushD       (FlushD),
        .FlushE       (FlushE),
        .FlushM       (FlushM)
    );

endmodule
