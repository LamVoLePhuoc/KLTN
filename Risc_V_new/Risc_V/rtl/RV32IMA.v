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

    // Debug / WB
    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug
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

    wire [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E;

    wire [4:0]  RD_E, RS1_E, RS2_E;

    // Execute
    wire [31:0] ALUResultE, WriteDataE, PCTargetE;
    wire        PCSrcE;
    wire        ZeroE, NegativeE, CarryE, OverFlowE;
    wire        Stall_MDU_Req;

    // EX / MEM outputs
    wire        RegWriteM;
    wire        MemWriteM, MemReadM;
    wire [1:0]  ResultSrcM;
    wire        AtomicM, CSR_M, Fence_M;
    wire [4:0]  AmoOpM;        // NEW: RV32A funct5 in MEM

    wire [4:0]  RD_M;
    wire [31:0] PCPlus4M, ALUResultM, WriteDataM;

    // Memory stage
    wire [31:0] ReadDataM;
    wire [2:0]  Mem_BusOpM_unused;

    // MEM / WB outputs
    wire        RegWriteW;
    wire [1:0]  ResultSrcW;
    wire [4:0]  RD_W;
    wire [31:0] PCPlus4W_Pipe, ALU_ResultW_Pipe, ReadDataW_Pipe;

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
    // 1. FETCH
    // =========================================================
    fetch_stage #(
        .RESET_ADDR(RESET_ADDR)
    ) fetch_unit (
        .clk      (clk),
        .rst      (rst),
        .stall    (StallF | Stall_Core_External),
        .bus_ready(~Stall_Core_External),
        .PCSrcE   (PCSrcE),
        .PCTargetE(PCTargetE),
        .PCF      (PCF),
        .PCPlus4F (PCPlus4F)
    );

    // =========================================================
    // 2. IF / ID
    // =========================================================
    if_id_registers if_id (
        .clk     (clk),
        .rst     (rst),
        .stall   (StallD | Stall_Core_External),
        .flush   (FlushD),
        .InstrF  (InstrF),
        .PCF     (PCF),
        .PCPlus4F(PCPlus4F),
        .InstrD  (InstrD),
        .PCD     (PCD),
        .PCPlus4D(PCPlus4D)
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

        .RD1_D       (RD1_D),
        .RD2_D       (RD2_D),

        .Imm_Ext_D   (Imm_Ext_D),
        .PCD_Out     (),
        .PCPlus4D_Out(),

        .RD_D        (RD_D),
        .RS1_D       (RS1_D),
        .RS2_D       (RS2_D)
    );

    // =========================================================
    // 4. ID / EX
    // =========================================================
    id_ex_registers id_ex (
        .clk         (clk),
        .rst         (rst),
        .stall       (StallE | Stall_Core_External),
        .flush       (FlushE),

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

        .ForwardA_E   (ForwardAE),
        .ForwardB_E   (ForwardBE),
        .ResultW      (ResultW),
        .ALUResultM   (ALUResultM),

        .Stall_MDU_Req(Stall_MDU_Req),

        .ALUResultE   (ALUResultE),
        .WriteDataE   (WriteDataE),
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

        .RegWriteW   (RegWriteW),
        .ResultSrcW  (ResultSrcW),
        .RD_W        (RD_W),
        .PCPlus4W    (PCPlus4W_Pipe),
        .ALU_ResultW (ALU_ResultW_Pipe),
        .ReadDataW   (ReadDataW_Pipe)
    );

    // =========================================================
    // 9. WRITEBACK
    // =========================================================
    writeback_stage writeback_unit (
        .ResultSrcW  (ResultSrcW),
        .ALU_ResultW (ALU_ResultW_Pipe),
        .ReadDataW   (ReadDataW_Pipe),
        .PCPlus4W    (PCPlus4W_Pipe),
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
