`timescale 1ns / 1ps

module decode_stage(
    input  wire        clk,
    input  wire        rst,   // active-high, synchronous

    // --- Từ tầng Fetch (IF) ---
    input  wire [31:0] InstrD,
    input  wire [31:0] PCD,
    input  wire [31:0] PCPlus4D,

    // --- Từ tầng Write-Back (WB) ---
    input  wire        RegWriteW,     // Integer RF write enable
    input  wire [4:0]  RD_W,          // Địa chỉ ghi integer RF
    input  wire [31:0] ResultW,       // Dữ liệu ghi

    // --- Tín hiệu điều khiển (Output) ---
    output wire        RegWriteD,
    output wire        ALUSrcD,
    output wire [1:0]  ALUSrcA_D,
    output wire        MemWriteD,
    output wire        MemReadD,
    output wire [1:0]  ResultSrcD,
    output wire        BranchD,
    output wire        JumpD,
    output wire [4:0]  ALUControlD,
    output wire [2:0]  ImmSrcD,
    output wire [2:0]  MemOpD,
    output wire        AtomicD,
    output wire [4:0]  AmoOpD,     // NEW: RV32A funct5 = Instr[31:27]
    output wire        CSR_D,
    output wire        Fence_D,

    // --- Dữ liệu integer RF (Output) ---
    output wire [31:0] RD1_D,
    output wire [31:0] RD2_D,

    output wire [31:0] Imm_Ext_D,
    output wire [31:0] PCD_Out,
    output wire [31:0] PCPlus4D_Out,

    // --- Địa chỉ integer register ---
    output wire [4:0]  RD_D,
    output wire [4:0]  RS1_D,
    output wire [4:0]  RS2_D
);

    // =========================================================
    // OPCODE LOCALPARAM
    // =========================================================
    localparam [6:0]
        OP_AMO    = 7'b0101111;

    // =========================================================
    // PASS PC
    // =========================================================
    assign PCD_Out      = PCD;
    assign PCPlus4D_Out = PCPlus4D;

    // =========================================================
    // 1. CONTROL UNIT
    //
    // Với RV32A:
    // - opcode = InstrD[6:0] = 0101111
    // - funct7 = InstrD[31:25]
    // - funct5 = InstrD[31:27] = funct7[6:2]
    //
    // Control_Unit phải lấy Funct5 = funct7[6:2]
    // rồi truyền vào Main_Decoder.
    // =========================================================
    Control_Unit control (
        .Op         (InstrD[6:0]),
        .funct7     (InstrD[31:25]),
        .funct3     (InstrD[14:12]),

        .RegWrite   (RegWriteD),
        .ALUSrc     (ALUSrcD),
        .ALUSrcA    (ALUSrcA_D),
        .MemWrite   (MemWriteD),
        .MemRead    (MemReadD),
        .ResultSrc  (ResultSrcD),
        .Branch     (BranchD),
        .Jump       (JumpD),
        .ImmSrc     (ImmSrcD),
        .ALUControl (ALUControlD),
        .MemOp      (MemOpD),
        .CSR        (CSR_D),
        .Fence      (Fence_D),
        .Atomic     (AtomicD)
    );

    // =========================================================
    // 2. INTEGER REGISTER FILE
    //
    // Dùng cho:
    // - RV32I
    // - RV32M
    // - RV32A
    //
    // Với lệnh A:
    // - rs1: chứa địa chỉ memory
    // - rs2: dữ liệu dùng cho SC/AMO
    // - rd : nhận old value hoặc SC result
    // =========================================================
    Register_File rf (
        .clk (clk),
        .rst (rst),

        .WE3 (RegWriteW),
        .WD3 (ResultW),

        .A1  (InstrD[19:15]),   // rs1
        .A2  (InstrD[24:20]),   // rs2
        .A3  (RD_W),            // rd ở WB stage

        .RD1 (RD1_D),
        .RD2 (RD2_D)
    );

    // =========================================================
    // 3. SIGN EXTEND
    //
    // Với RV32A, ImmSrcD nên là 3'b101.
    // Trong Sign_Extend.v cần có:
    //
    // 3'b101: Imm_Ext = 32'b0;
    //
    // Vì địa chỉ lệnh A là:
    // addr = rs1 + 0
    // =========================================================
    Sign_Extend extension (
        .In      (InstrD),
        .ImmSrc  (ImmSrcD),
        .Imm_Ext (Imm_Ext_D)
    );

    // =========================================================
    // 4. EXTRACT INTEGER REGISTER ADDRESSES
    // =========================================================
    assign RD_D  = InstrD[11:7];
    assign RS1_D = InstrD[19:15];
    assign RS2_D = InstrD[24:20];

    // =========================================================
    // 5. EXTRACT RV32A AMO OPERATION
    //
    // RV32A format:
    //
    // Instr[31:27] = funct5 / amo operation
    // Instr[26]    = aq
    // Instr[25]    = rl
    // Instr[24:20] = rs2
    // Instr[19:15] = rs1
    // Instr[14:12] = funct3, với .W là 3'b010
    // Instr[11:7]  = rd
    // Instr[6:0]   = opcode = 7'b0101111
    //
    // AmoOpD encoding:
    // 5'b00000 = AMOADD.W
    // 5'b00001 = AMOSWAP.W
    // 5'b00010 = LR.W
    // 5'b00011 = SC.W
    // 5'b00100 = AMOXOR.W
    // 5'b01000 = AMOOR.W
    // 5'b01100 = AMOAND.W
    // 5'b10000 = AMOMIN.W
    // 5'b10100 = AMOMAX.W
    // 5'b11000 = AMOMINU.W
    // 5'b11100 = AMOMAXU.W
    // =========================================================
    assign AmoOpD = InstrD[31:27];

endmodule
