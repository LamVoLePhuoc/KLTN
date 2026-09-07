`timescale 1ns / 1ps

module Control_Unit(
    input  wire [6:0] Op,
    input  wire [6:0] funct7,
    input  wire [2:0] funct3,

    output wire        RegWrite,
    output wire        ALUSrc,
    output wire [1:0]  ALUSrcA,
    output wire        MemWrite,
    output wire        MemRead,
    output wire [1:0]  ResultSrc,
    output wire        Branch,
    output wire        Jump,
    output wire [2:0]  ImmSrc,
    output wire [4:0]  ALUControl,
    output wire [2:0]  MemOp,
    output wire        CSR,
    output wire        Fence,
    output wire        Atomic
);

    wire [1:0] ALUOp;

    // ============================================================
    // Funct5 dùng cho RV32A
    // Instruction A-type:
    // Instr[31:27] = funct5
    // Instr[31:25] = funct7
    // Vì funct7 = Instr[31:25], nên Funct5 = funct7[6:2]
    // ============================================================
    wire [4:0] Funct5;
    assign Funct5 = funct7[6:2];

    // ============================================================
    // OPCODE ENCODING
    // ============================================================
    localparam [6:0]
        OP_OP_IMM  = 7'b0010011;

    // ============================================================
    // MAIN DECODER
    // ============================================================
    Main_Decoder md (
        .Op         (Op),
        .Funct5     (Funct5),

        .RegWrite   (RegWrite),
        .ALUSrc     (ALUSrc),
        .ALUSrcA    (ALUSrcA),
        .MemWrite   (MemWrite),
        .MemRead    (MemRead),
        .ResultSrc  (ResultSrc),
        .Branch     (Branch),
        .Jump       (Jump),
        .ImmSrc     (ImmSrc),
        .ALUOp      (ALUOp),
        .CSR        (CSR),
        .Fence      (Fence),
        .Atomic     (Atomic)
    );

    // ============================================================
    // MEMORY OPERATION
    //
    // Với load/store thường:
    // funct3 quyết định LB/LH/LW/LBU/LHU/SB/SH/SW
    //
    // Với A-extension:
    // funct3 phải là 3'b010 cho .W
    // memory_stage có thể dùng MemOp = funct3 để biết là word access.
    // ============================================================
    assign MemOp = funct3;

    // ============================================================
    // ALU DECODER
    // ============================================================
    wire is_op_imm;
    assign is_op_imm = (Op == OP_OP_IMM);

    ALU_Decoder alu_dec (
        .ALUOp      (ALUOp),
        .funct3     (funct3),
        .funct7     (funct7),
        .is_op_imm  (is_op_imm),
        .ALUControl (ALUControl)
    );

endmodule
