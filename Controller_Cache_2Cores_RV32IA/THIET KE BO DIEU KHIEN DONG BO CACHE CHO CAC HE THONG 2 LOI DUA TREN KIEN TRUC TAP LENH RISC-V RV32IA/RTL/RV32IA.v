`timescale 1ns/1ps
`include "define.vh"
// from Lee Min Hunz with luv
// ============================================================================
// RV32IA - RISC-V 32-bit Integer + Atomic Extension CPU Core
// ============================================================================
//
// A 7-stage pipelined RISC-V processor supporting RV32IA ISA extensions.
// Designed for dual-core configuration with cache coherence support.
//
// ISA Extensions:
//   - RV32I: Base integer instructions
//   - RV32A: Atomic instructions (LR.W, SC.W, AMO*)
//
// Features:
//   - Branch prediction with BTB and PHT
//   - Data forwarding (EX-EX, MEM-EX, CACHE-EX)
//   - Hazard detection and pipeline stalling
//   - Integrated with L1 ICache and DCache
//   - ACE snoop interface for cache coherence
//
// Atomic Support:
//   - LR.W (Load-Reserved): cpu_lr asserted
//   - SC.W (Store-Conditional): cpu_sc asserted
//   - AMO* (Atomic Memory Op): cpu_amo + cpu_amo_op
//
// ============================================================================
module RV32IA #(
    parameter WIDTH_DATA    = `DATA_W,
    parameter WIDTH_ADDR    = `ADDR_W,
    parameter START_PC      = `CODE_A_START
    // parameter END_PC        = 32'd1024
)(
    input   clk
,   input   rst_n
// ,   input   test_stall

    // cpu <-> dcache
,   input   [WIDTH_DATA-1:0]    data_rdata
,   input                       dcache_stall
,   output                      data_req
,   output                      data_wr
,   output  [1:0]               data_size
,   output  [WIDTH_ADDR - 1:0]  data_addr
,   output  [WIDTH_DATA - 1:0]  data_wdata
,   output                      o_dcache_flush

    // cpu atomic interface
,   output                      cpu_lr
,   output                      cpu_sc
,   output                      cpu_amo
,   output  [2:0]               cpu_amo_op

    // cpu <-> icache
,   input                       icache_stall
,   input   [WIDTH_DATA - 1:0]  imem_instr

,   output                      fetch_stall
,   output                      icache_req
// ,   output                      icache_flush
,   output  [WIDTH_ADDR - 1:0]  icache_addr

    // Debug port
,   input   [4:0]               i_debug_reg_addr
,   input                       i_debug_ren
,   output  [WIDTH_DATA-1:0]    o_debug_reg_data
);

    // ================================================================
    // SIGNAL DECLARATIONS - Organized by Pipeline Stage
    // ================================================================
    // Pipeline: IF(S1) -> S2(icache) -> ID -> EX -> MEM -> CACHE -> WB
    // ================================================================

    // ================================================================
    // FETCH STAGE (S1) - PC Generation & Branch Prediction
    // ================================================================
    reg  [WIDTH_ADDR-1:0]   PCNext;             // Next PC (from prediction or correction)
    wire [WIDTH_DATA-1:0]   F_RD;               // Fetched instruction from icache
    wire [WIDTH_ADDR-1:0]   F_PC, F_PCPlus4;    // Current PC and PC+4
    wire                    F_Stall;            // Stall fetch stage
    wire                    F_Predict_Taken;    // Branch prediction result
    wire [2:0]              F_GHSR;             // Global History Shift Register
    wire [31:0]             F_Predict_Target;   // Predicted target address
    
    // ================================================================
    // STAGE 2 (S2) - Post-ICache Pipeline Register
    // ================================================================
    wire                    s2_Predict_Taken;   // Prediction from S1 (pipelined)
    wire [2:0]              s2_GHSR;            // GHSR from S1 (pipelined)
    wire [WIDTH_ADDR-1:0]   s2_PC, s2_PCPlus4;  // PC values (pipelined)
    wire                    fetch_pipe_Flush;   // Flush fetch pipeline on mispredict
    reg                     s2_ignore_instr;
    // ================================================================
    // DECODE STAGE (ID) - Instruction Decode & Register Read
    // ================================================================
    wire [WIDTH_DATA-1:0]   D_Instr, D_ImmExt;          // Instruction & sign-extended immediate
    wire [WIDTH_ADDR-1:0]   D_PC, D_PCPlus4;            // PC values
    wire [WIDTH_DATA-1:0]   RDX1, RDX2;                 // Register file read data
    // wire [WIDTH_DATA-1:0]   D_Instr_Safe;
    wire [4:0]              A1, A2, WD3;                // Register addresses (rs1, rs2, rd)
    // Control signals from decoder
    wire                    D_RegWrite, D_MemWrite, D_Jump, D_Branch, D_ALUSrc, D_addr_addend_sel, D_ResPCSel;
    wire [3:0]              D_ALUControl;
    wire [2:0]              D_ResultSrc, D_ImmSrc, D_StoreSrc;
    wire                    D_Predict_Taken;
    wire [2:0]              D_GHSR;
    wire                    D_data_req;                 // Data memory request
    wire                    D_Stall, D_Flush;           // Hazard control
    // wire                    D_ignore_instr;

    // Atomic Instructions (RV32A Extension)
    wire            D_amo;          // Atomic Memory Operation
    wire    [2:0]   D_amo_op;       // AMO operation type
    wire            D_lr, D_sc;     // Load-Reserved, Store-Conditional

    // ================================================================
    // EXECUTE STAGE (EX) - ALU & Branch Resolution
    // ================================================================
    wire [WIDTH_DATA-1:0]   E_RD1, E_RD2;               // Register values (pipelined)
    wire [WIDTH_DATA-1:0]   E_ImmExt, E_ALUResult;      // Immediate & ALU output
    wire [WIDTH_ADDR-1:0]   E_PC, E_PCPlus4, E_PCtmp, E_PCTarget;  // PC & branch target
    wire [4:0]              E_rs1, E_rs2, E_rd;         // Register addresses
    reg  [WIDTH_DATA-1:0]   E_SrcA;
    wire [WIDTH_DATA-1:0]   E_SrcB; 
    reg  [WIDTH_DATA-1:0]   E_WriteData; // ALU operands & store data
    // Control signals
    wire                    E_signed_less, E_RegWrite, E_MemWrite, E_Jump, E_Branch, E_ALUSrc, E_Zero, E_PCSrc, E_addr_addend_sel, E_ResPCSel;
    wire                    E_unsigned_less;
    wire [3:0]              E_ALUControl;
    wire [2:0]              E_ResultSrc, E_funct3, E_StoreSrc;
    // Branch prediction correction
    wire                    E_Predict_Taken;            // Prediction from earlier stages
    wire [2:0]              E_GHSR;
    wire                    E_Mispredict;               // Branch misprediction detected
    // wire [31:0]             E_Correct_PC;               // Correct PC on mispredict
    wire                    E_data_req;
    wire                    E_Stall, E_Flush;
    wire [1:0]              ForwardAE, ForwardBE;       // Forwarding mux selects

    // Atomic signals (pipelined)
    wire                    E_amo;
    wire    [2:0]           E_amo_op;
    wire                    E_lr, E_sc;

    // ================================================================
    // MEMORY STAGE (MEM) - Data Cache Request
    // ================================================================
    wire [WIDTH_DATA-1:0]   M_ALUResult;
    wire [WIDTH_DATA-1:0]   M_mux_result; 
    wire [WIDTH_DATA-1:0]   M_ReadData;
    wire [4:0]              M_rd;
    wire [2:0]              M_ResultSrc;
    wire [2:0]              M_funct3;
    wire [1:0]              M_byte_off;
    wire                    M_RegWrite;
    // wire                    M_MemWrite;
    wire                    M_Stall;
    wire                    M_Flush;
    // Atomic signals (pipelined)
    reg  [31:0]             aligned_load_data;

    // wire                    M_Predict_Taken;
    wire [WIDTH_ADDR-1:0]   M_PC;
    wire [WIDTH_ADDR-1:0]   M_PCPlus4;
    wire [WIDTH_ADDR-1:0]   M_PCTarget;
    wire                    M_Branch;
    wire                    M_Jump;
    wire                    M_PCSrc;
    wire [2:0]              M_GHSR;


    // ================================================================
    // WRITEBACK STAGE (WB) - Write Result to Register File
    // ================================================================
    wire [WIDTH_DATA-1:0]   W_mux_result;       // Final result to write
    wire [4:0]              W_rd;               // Destination register
    wire                    W_RegWrite;         // Write enable
    wire [2:0]              W_ResultSrc;

    // ================================================================
    // BRANCH PREDICTION UNIT & PC SELECTION
    // ================================================================
    wire [1:0] pc_sel;
    assign F_PCPlus4    = F_PC + 32'd4;
    assign E_Mispredict = (E_PCSrc != E_Predict_Taken);
    
    assign pc_sel[1]    = E_Mispredict;
    assign pc_sel[0]    = E_Mispredict ? E_PCSrc : F_Predict_Taken;
    
    always @(*) begin
        case (pc_sel)
            2'b11: PCNext   = E_PCTarget;       // wrong predict & should jump
            2'b10: PCNext   = E_PCPlus4;        // wrong predict & shouldn't jump
            2'b01: PCNext   = F_Predict_Target; // correct predict
            2'b00: PCNext   = F_PCPlus4;        // correct predict
            default: PCNext = F_PCPlus4;        // prevent X latching
        endcase
    end

    // ================================================================
    // BPU & BRANCH DECODER INSTANTIATION
    // ================================================================
    // BPU #(
    //     .W_ADDR(WIDTH_ADDR)
    // ) BPU_inst (
    //     .clk            (clk)
    // ,   .rst_n          (rst_n)
    // ,   .F_PC           (F_PC[WIDTH_ADDR-1:2])
    // ,   .predict_taken  (F_Predict_Taken)
    // ,   .target_pc      (F_Predict_Target)
    // ,   .F_GHSR         (F_GHSR)

    // ,   .E_PC           (M_PC[WIDTH_ADDR-1:2])
    // ,   .E_PCTarget     (M_PCTarget)
    // ,   .E_Branch       (M_Branch)
    // ,   .E_Jump         (M_Jump)
    // ,   .taken          (M_PCSrc)
    // ,   .E_GHSR         (M_GHSR)
    // );

    BPU #(
        .W_ADDR(WIDTH_ADDR)
    ) BPU_inst (
        .clk            (clk)
    ,   .rst_n          (rst_n)
  
        // IF state
    ,   .F_PC           (F_PC[WIDTH_ADDR-1:2])
    ,   .predict_taken  (F_Predict_Taken)
    ,   .target_pc      (F_Predict_Target)
    ,   .F_GHSR         (F_GHSR)

        // EX state
    ,   .M_PC           (E_PC[WIDTH_ADDR-1:2])
    ,   .M_PCTarget     (E_PCTarget)
    ,   .M_Branch       (E_Branch)
    ,   .M_Jump         (E_Jump)
    ,   .M_PCSrc        (E_PCSrc)
    ,   .M_GHSR         (E_GHSR)

    );

    BranchDecoder BranchDecoder_inst(
        .E_Jump         (E_Jump)
    ,   .E_Zero         (E_Zero)
    ,   .E_Branch       (E_Branch)
    ,   .E_signed_less  (E_signed_less)
    ,   .E_unsigned_less(E_unsigned_less)
    ,   .funct3         (E_funct3)
    ,   .E_PCSrc        (E_PCSrc)
    );

    // ================================================================
    // HAZARD UNIT - Stall, Flush, and Forwarding Control
    // ================================================================
    // assign icache_flush = fetch_pipe_Flush;

    HazardUnit_v2 HazardUnit_inst(
        .D_Rs1          (A1)
    ,   .D_Rs2          (A2)
    ,   .E_Rs1          (E_rs1)
    ,   .E_Rs2          (E_rs2)
    ,   .E_rd           (E_rd)
    ,   .icache_stall   (icache_stall)
    ,   .dcache_stall   (dcache_stall)
        
    ,   .E_ResultSrc    (E_ResultSrc)
    ,   .E_Mispredict   (E_Mispredict)
    // ,   .M_Mispredict   (M_Mispredict)
    ,   .M_RegWrite     (M_RegWrite)
    ,   .M_Rd           (M_rd)
    ,   .W_Rd           (W_rd)
    ,   .W_RegWrite     (W_RegWrite)
        
    ,   .F_Stall            (F_Stall)
    ,   .D_Stall            (D_Stall)
    ,   .E_Stall            (E_Stall)
    ,   .M_Stall            (M_Stall)
    ,   .fetch_pipe_Flush   (fetch_pipe_Flush)
    ,   .D_Flush            (D_Flush)
    ,   .E_Flush            (E_Flush)
    ,   .M_Flush            (M_Flush)
    ,   .ForwardAE          (ForwardAE)
    ,   .ForwardBE          (ForwardBE)
    );

    // ================================================================
    // FETCH STAGE (S1) - PC Register
    // ================================================================
    PC #(
        .WIDTH      (WIDTH_ADDR)
    ,   .START_PC   (START_PC)
    ) PC_inst(    
        .clk    (clk)
    ,   .rst_n  (rst_n)
    ,   .EN     (F_Stall)
    ,   .PCNext (PCNext)
    ,   .PC     (F_PC)
    );

    // ================================================================
    // I-CACHE CONNECTION
    // ================================================================
    assign icache_addr = F_PC;          // S1 -> Cache
    assign icache_req  = rst_n;         // Always request when not reset
    assign fetch_stall = F_Stall;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_ignore_instr <= 1'b0;
        end 
        else if (F_Stall) begin
            s2_ignore_instr <= s2_ignore_instr;
        end 
        else begin
            s2_ignore_instr <= fetch_pipe_Flush;
        end
    end

    assign F_RD = s2_ignore_instr ? 32'h00000000 : imem_instr;
    // ================================================================
    // PIPELINE REGISTER: S1 -> S2 (fetch_pipe)
    // ================================================================
    fetch_pipe #(
        .DATA_W(WIDTH_DATA),
        .ADDR_W(WIDTH_ADDR),
        .START_PC(START_PC)
    ) fetch_pipe_register (
        .clk    (clk)
    ,   .rst_n  (rst_n)
    ,   .EN     (F_Stall)
    ,   .Flush  (fetch_pipe_Flush)

    ,   .s1_Predict_Taken   (F_Predict_Taken)
    ,   .s1_GHSR            (F_GHSR)
    ,   .s1_PC              (F_PC)
    ,   .s1_PCPlus4         (F_PCPlus4)

    ,   .s2_Predict_Taken   (s2_Predict_Taken)
    ,   .s2_GHSR            (s2_GHSR         )
    ,   .s2_PC              (s2_PC           )
    ,   .s2_PCPlus4         (s2_PCPlus4      )
    );

    // ================================================================
    // PIPELINE REGISTER: S2 -> ID (IF_ID)
    // ================================================================
    wire D_Flush_actual = D_Flush | s2_ignore_instr;
    IF_ID IF_ID_register(
        .clk                (clk)
    ,   .rst_n              (rst_n)
    ,   .EN                 (D_Stall)
    // ,   .D_Flush            (D_Flush)
    ,   .D_Flush            (D_Flush_actual)
    ,   .F_RD               (F_RD)
    ,   .F_PC               (s2_PC)
    ,   .F_PCPlus4          (s2_PCPlus4)
    ,   .F_GHSR             (s2_GHSR)
    ,   .F_Predict_Taken    (s2_Predict_Taken)
    // ,   .s2_ignore_instr    (s2_ignore_instr)

    ,   .D_Instr            (D_Instr)
    ,   .D_PC               (D_PC)
    ,   .D_PCPlus4          (D_PCPlus4)
    ,   .D_GHSR             (D_GHSR)
    ,   .D_Predict_Taken    (D_Predict_Taken)
    // ,   .D_ignore_instr     (D_ignore_instr)
    );

    // ================================================================
    // DECODE STAGE (ID) - Control Unit & Register File
    // ================================================================
    // assign D_Instr_Safe = D_ignore_instr ? 32'h00000013 : D_Instr;
    // assign A1           = D_Instr_Safe[19:15];   // rs1
    // assign A2           = D_Instr_Safe[24:20];   // rs2  
    // assign WD3          = D_Instr_Safe[11:7];    // rd

    assign A1   = D_Instr[19:15];   // rs1
    assign A2   = D_Instr[24:20];   // rs2  
    assign WD3  = D_Instr[11:7];    // rd
    
    ControlUnit ControlUnit_ins(
        .op                 (D_Instr[6:0])
    // ,   .funct7             (D_Instr[31:25])
    ,   .funct7_5           (D_Instr[30])
    ,   .funct5             (D_Instr[31:27])
    ,   .funct3             (D_Instr[14:12])
    //     .op                 (D_Instr_Safe[6:0])
    // ,   .funct7             (D_Instr_Safe[31:25])
    // ,   .funct5             (D_Instr_Safe[31:27])
    // ,   .funct3             (D_Instr_Safe[14:12])

    ,   .ResultSrc          (D_ResultSrc)
    ,   .MemWrite           (D_MemWrite)
    ,   .ALUControl         (D_ALUControl)
    ,   .ALUSrc             (D_ALUSrc)
    ,   .ImmSrc             (D_ImmSrc)
    ,   .RegWrite           (D_RegWrite)
    ,   .Branch             (D_Branch)
    ,   .Jump               (D_Jump)
    ,   .StoreSrc           (D_StoreSrc)
    ,   .addr_addend_sel    (D_addr_addend_sel)
    ,   .ResPCSel           (D_ResPCSel)
    ,   .data_req           (D_data_req)
    ,   .amo                (D_amo)
    ,   .amo_op             (D_amo_op)
    ,   .lr                 (D_lr)
    ,   .sc                 (D_sc)
    );

    RegFile register_file(
        .clk    (clk)
    ,   .rst_n  (rst_n)
    ,   .we     (W_RegWrite)
    ,   .rs1    (A1)
    ,   .rs2    (A2)
    ,   .rd     (W_rd)
    ,   .wd     (W_mux_result)
    ,   .rd1    (RDX1)
    ,   .rd2    (RDX2)

    ,   .debug_addr (i_debug_reg_addr)
    ,   .debug_ren  (i_debug_ren)
    ,   .debug_data (o_debug_reg_data)
    );

    Extend extend_inst(
        .ImmSrc (D_ImmSrc)
    ,   .Instr  (D_Instr[31:7])
    ,   .ImmExt (D_ImmExt)
    );

    // ================================================================
    // PIPELINE REGISTER: ID -> EX (ID_EX)
    // ================================================================
    ID_EX ID_EX_register(
        .clk                (clk)
    ,   .rst_n              (rst_n)
    ,   .E_Flush            (E_Flush)
    ,   .EN                 (E_Stall)

    ,   .D_RD1              (RDX1)
    ,   .D_RD2              (RDX2)
    ,   .D_Rs1              (A1)
    ,   .D_Rs2              (A2)
    ,   .D_rd               (WD3)
    ,   .D_ImmExt           (D_ImmExt)
    ,   .D_PC               (D_PC)
    ,   .D_PCPlus4          (D_PCPlus4)
    ,   .D_RegWrite         (D_RegWrite)
    ,   .D_MemWrite         (D_MemWrite)
    ,   .D_Jump             (D_Jump)
    ,   .D_Branch           (D_Branch)
    ,   .D_ALUSrc           (D_ALUSrc)
    ,   .D_ResultSrc        (D_ResultSrc)
    ,   .D_funct3           (D_Instr[14:12])
    ,   .D_GHSR             (D_GHSR)
    ,   .D_StoreSrc         (D_StoreSrc)
    ,   .D_ALUControl       (D_ALUControl)
    ,   .D_addr_addend_sel  (D_addr_addend_sel)
    ,   .D_ResPCSel         (D_ResPCSel)
    ,   .D_Predict_Taken    (D_Predict_Taken)
    ,   .D_data_req         (D_data_req)
    ,   .D_amo              (D_amo)
    ,   .D_amo_op           (D_amo_op)
    ,   .D_lr               (D_lr)
    ,   .D_sc               (D_sc)

    ,   .E_SrcA_fix         (E_SrcA)      // Giá trị sau Mux Forwarding A
    ,   .E_SrcB_fix         (E_WriteData) // Giá trị sau Mux Forwarding B

    ,   .E_RD1              (E_RD1)
    ,   .E_RD2              (E_RD2)
    ,   .E_Rs1              (E_rs1)
    ,   .E_Rs2              (E_rs2)
    ,   .E_rd               (E_rd)
    ,   .E_ImmExt           (E_ImmExt)
    ,   .E_PC               (E_PC)
    ,   .E_PCPlus4          (E_PCPlus4)
    ,   .E_RegWrite         (E_RegWrite)
    ,   .E_MemWrite         (E_MemWrite)
    ,   .E_Jump             (E_Jump)
    ,   .E_Branch           (E_Branch)
    ,   .E_ALUSrc           (E_ALUSrc)
    ,   .E_ResultSrc        (E_ResultSrc)
    ,   .E_funct3           (E_funct3)
    ,   .E_GHSR             (E_GHSR)
    ,   .E_StoreSrc         (E_StoreSrc)
    ,   .E_ALUControl       (E_ALUControl)
    ,   .E_addr_addend_sel  (E_addr_addend_sel)
    ,   .E_ResPCSel         (E_ResPCSel)
    ,   .E_Predict_Taken    (E_Predict_Taken)
    ,   .E_data_req         (E_data_req)
    ,   .E_amo              (E_amo)
    ,   .E_amo_op           (E_amo_op)
    ,   .E_lr               (E_lr)
    ,   .E_sc               (E_sc)
    );

    // ================================================================
    // EXECUTE STAGE (EX) - ALU & Forwarding
    // ================================================================
    ALU alu_inst(
        .ALUControl (E_ALUControl)
    ,   .in1        (E_SrcA)
    ,   .in2        (E_SrcB)
    ,   .PC         (E_PC)
    ,   .E_ImmExt   (E_ImmExt)
    ,   .E_PCPlus4  (E_PCPlus4)

    ,   .result         (E_ALUResult)
    ,   .zero           (E_Zero)
    ,   .signed_less    (E_signed_less)
    ,   .unsigned_less  (E_unsigned_less)
    );

    mux2_1 Mux_PCadd(
        .in0    (E_PC)
    // ,   .in1    (E_RD1)
    ,   .in1    (E_SrcA)
    ,   .sel    (E_addr_addend_sel)
    ,   .res    (E_PCtmp)
    );

    always @(*) begin
        case(ForwardAE)
            2'b00:      E_SrcA  = E_RD1;
            // 2'b01:      E_SrcA  = M_mux_result;     // TODO: check
            2'b01:      E_SrcA  = M_ALUResult;     // Đã tối ưu: Dùng M_ALUResult cắt path
            2'b10:      E_SrcA  = W_mux_result;
            default:    E_SrcA  = E_RD1; 
        endcase

        case(ForwardBE)
            2'b00:      E_WriteData = E_RD2;
            // 2'b01:      E_WriteData = M_mux_result; // TODO: check
            2'b01:      E_WriteData = M_ALUResult; // Đã tối ưu: Dùng M_ALUResult cắt path
            2'b10:      E_WriteData = W_mux_result;
            default:    E_WriteData = E_RD2; 
        endcase
    end

    mux2_1 mux_E_ALUSrc (
        .in0    (E_WriteData)
    ,   .in1    (E_ImmExt)
    ,   .sel    (E_ALUSrc)
    ,   .res    (E_SrcB)
    );

    assign E_PCTarget   = E_ImmExt + E_PCtmp;  // Branch/Jump target address

    // ================================================================
    // MEMORY STAGE (MEM) - D-Cache Interface
    // ================================================================
    assign data_wr          = E_MemWrite;
    assign data_size        = E_StoreSrc;   // lb/sb=00, lh/sh=01, lw/sw=10
    assign data_addr        = E_ALUResult; // For AMO/SC/LR, use address from register; otherwise use ALU result
    assign data_wdata       = E_WriteData;
    assign data_req         = E_data_req;
    assign o_dcache_flush   = 1'b0; // No longer needed since flush happens in E before memory request

    // Atomic instruction signals to D-Cache
    assign cpu_lr       = E_lr;         // Load-Reserved
    assign cpu_sc       = E_sc;         // Store-Conditional
    assign cpu_amo      = E_amo;        // Atomic operation
    assign cpu_amo_op   = E_amo_op;     // AMO type

    // ================================================================
    // PIPELINE REGISTER: EX -> MEM (EX_MEM)
    // ================================================================
    EX_MEM EX_MEM_register(
        .clk    (clk)
    ,   .rst_n  (rst_n)
    ,   .EN     (M_Stall)
    ,   .Flush  (M_Flush)
    ,   .E_ALUResult    (E_ALUResult)
    // ,   .E_WriteData    (E_WriteData)
    ,   .E_rd           (E_rd)
    ,   .E_RegWrite     (E_RegWrite)
    // ,   .E_MemWrite     (E_MemWrite)
    ,   .E_ResultSrc    (E_ResultSrc)
    ,   .E_funct3       (E_funct3)
    // ,   .E_Predict_Taken(E_Predict_Taken)
    // ,   .E_PC           (E_PC)
    // ,   .E_PCPlus4      (E_PCPlus4)
    // ,   .E_PCTarget     (E_PCTarget)
    // ,   .E_Branch       (E_Branch)
    // ,   .E_Jump         (E_Jump)
    // ,   .E_PCSrc        (E_PCSrc)
    // ,   .E_GHSR         (E_GHSR)

    ,   .M_ALUResult    (M_ALUResult)
    ,   .M_rd           (M_rd)
    ,   .M_RegWrite     (M_RegWrite)
    // ,   .M_MemWrite     (M_MemWrite)
    ,   .M_ResultSrc    (M_ResultSrc)
    ,   .M_funct3       (M_funct3)
    // ,   .M_Predict_Taken(M_Predict_Taken)
    // ,   .M_PC           (M_PC)
    // ,   .M_PCPlus4      (M_PCPlus4)
    // ,   .M_PCTarget     (M_PCTarget)
    // ,   .M_Branch       (M_Branch)
    // ,   .M_Jump         (M_Jump)
    // ,   .M_PCSrc        (M_PCSrc)
    // ,   .M_GHSR         (M_GHSR)
    );

    // ================================================================
    // PIPELINE REGISTER: MEM -> CACHE (MEM_CACHE)
    // ================================================================
    assign M_byte_off   = M_ALUResult[1:0];

    always @(*) begin
        case (M_funct3)
            3'b000: begin // LB (Load Byte - Sign Extend)
                case (M_byte_off)
                    2'b00: aligned_load_data = {{24{data_rdata[7]}},  data_rdata[7:0]};
                    2'b01: aligned_load_data = {{24{data_rdata[15]}}, data_rdata[15:8]};
                    2'b10: aligned_load_data = {{24{data_rdata[23]}}, data_rdata[23:16]};
                    2'b11: aligned_load_data = {{24{data_rdata[31]}}, data_rdata[31:24]};
                endcase
            end
            3'b100: begin // LBU (Load Byte Unsigned - Zero Extend)
                case (M_byte_off)
                    2'b00: aligned_load_data = {24'd0, data_rdata[7:0]};
                    2'b01: aligned_load_data = {24'd0, data_rdata[15:8]};
                    2'b10: aligned_load_data = {24'd0, data_rdata[23:16]};
                    2'b11: aligned_load_data = {24'd0, data_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH (Load Halfword - Sign Extend)
                case (M_byte_off[1])
                    1'b0: aligned_load_data = {{16{data_rdata[15]}}, data_rdata[15:0]};
                    1'b1: aligned_load_data = {{16{data_rdata[31]}}, data_rdata[31:16]};
                endcase
            end
            3'b101: begin // LHU (Load Halfword Unsigned - Zero Extend)
                case (M_byte_off[1])
                    1'b0: aligned_load_data = {16'd0, data_rdata[15:0]};
                    1'b1: aligned_load_data = {16'd0, data_rdata[31:16]};
                endcase
            end
            3'b010:  aligned_load_data = data_rdata; // LW (Load Word)
            default: aligned_load_data = data_rdata;
        endcase
    end

    assign M_ReadData   = aligned_load_data;
    
    mux2_1 mux_M_Result (
        .in0    (M_ALUResult)
    ,   .in1    (M_ReadData)
    ,   .sel    (M_ResultSrc[0])
    ,   .res    (M_mux_result)
    );

    // ================================================================
    // PIPELINE REGISTER: CACHE -> WRITEBACK (MEM_WB)
    // ================================================================
    MEM_WB MEM_WB_register(
        .clk            (clk)
    ,   .rst_n          (rst_n)
    ,   .M_rd           (M_rd)
    ,   .M_RegWrite     (M_RegWrite)
    ,   .M_ResultSrc    (M_ResultSrc)
    ,   .M_mux_result   (M_mux_result)

    ,   .W_rd           (W_rd)
    ,   .W_RegWrite     (W_RegWrite)
    ,   .W_ResultSrc    (W_ResultSrc)
    ,   .W_mux_result   (W_mux_result)
    );
endmodule