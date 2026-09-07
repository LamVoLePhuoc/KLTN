`timescale 1ns / 1ps

module Control_Unit(
    input  wire [6:0] Op,
    input  wire [6:0] funct7,
    input  wire [2:0] funct3,
    input  wire [4:0] rs2,

    output wire        RegWrite,
    output wire        FPRegWrite,
    output wire        ALUSrc,
    output wire [1:0]  ALUSrcA,
    output wire        MemWrite,
    output wire        MemRead,
    output wire [1:0]  ResultSrc,
    output wire        Branch,
    output wire        Jump,
    output wire [2:0]  ImmSrc,
    output wire [4:0]  ALUControl,
    output wire [4:0]  FPUControl,
    output wire [2:0]  MemOp,
    output wire        CSR,
    output wire        Fence,
    output wire        Atomic
);

    wire [1:0] ALUOp;
    wire       RegWrite_Main;

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
    // FPU CONTROL ENCODING
    // ============================================================
    localparam [4:0]
        FEQ_S       = 5'b01000,
        FLT_S       = 5'b01001,
        FLE_S       = 5'b01010,
        FCVT_W_S    = 5'b01101,
        FCVT_WU_S   = 5'b01110,
        FMV_X_W     = 5'b10001,
        FCLASS_S    = 5'b10011,
        INVALID_FPU = 5'b11111;

    // ============================================================
    // OPCODE ENCODING
    // ============================================================
    localparam [6:0]
        OP_OP_IMM  = 7'b0010011,
        OP_FLW     = 7'b0000111,
        OP_FSW     = 7'b0100111,
        OP_FP      = 7'b1010011,
        OP_FMADD   = 7'b1000011,
        OP_FMSUB   = 7'b1000111,
        OP_FNMSUB  = 7'b1001011,
        OP_FNMADD  = 7'b1001111;

    // ============================================================
    // MAIN DECODER
    // ============================================================
    Main_Decoder md (
        .Op         (Op),
        .Funct5     (Funct5),

        .RegWrite   (RegWrite_Main),
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

    // ============================================================
    // FPU DECODER
    // ============================================================
    FPU_Decoder fpu_dec (
        .opcode     (Op),
        .funct7     (funct7),
        .funct3     (funct3),
        .rs2        (rs2),
        .FPUControl (FPUControl)
    );

    // ============================================================
    // FPU WRITEBACK CONTROL
    // ============================================================
    wire is_FOP;
    wire is_FLW;
    wire valid_fpu_op;

    assign is_FOP =
        (Op == OP_FP)     ||
        (Op == OP_FMADD)  ||
        (Op == OP_FMSUB)  ||
        (Op == OP_FNMSUB) ||
        (Op == OP_FNMADD);

    assign is_FLW = (Op == OP_FLW);

    assign valid_fpu_op = (FPUControl != INVALID_FPU);

    reg fpu_writes_to_int;

    always @(*) begin
        case (FPUControl)
            FEQ_S,
            FLT_S,
            FLE_S,
            FCVT_W_S,
            FCVT_WU_S,
            FMV_X_W,
            FCLASS_S:
                fpu_writes_to_int = 1'b1;

            default:
                fpu_writes_to_int = 1'b0;
        endcase
    end

    // ============================================================
    // INTEGER REGISTER FILE WRITE ENABLE
    //
    // RegWrite_Main:
    // - RV32I
    // - RV32M
    // - RV32A
    // - jump/load/etc.
    //
    // fpu_writes_to_int:
    // - FEQ.S / FLT.S / FLE.S
    // - FCVT.W.S / FCVT.WU.S
    // - FMV.X.W
    // - FCLASS.S
    // ============================================================
    assign RegWrite =
        RegWrite_Main |
        (is_FOP && valid_fpu_op && fpu_writes_to_int);

    // ============================================================
    // FLOAT REGISTER FILE WRITE ENABLE
    //
    // FLW ghi vào FP register.
    // Các lệnh FPU còn lại ghi FP nếu không phải nhóm ghi integer.
    // ============================================================
    assign FPRegWrite =
        is_FLW |
        (is_FOP && valid_fpu_op && !fpu_writes_to_int);

endmodule