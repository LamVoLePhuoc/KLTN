module Control_Unit(
    input  wire [6:0] Op,
    input  wire [6:0] funct7,
    input  wire [2:0] funct3,

    output wire        RegWrite,    // Ghi file thanh ghi Int
    output wire        FPRegWrite,  // Ghi file thanh ghi Float
    output wire        ALUSrc,
    output wire        MemWrite,
    output wire        MemRead,
    output wire [1:0]  ResultSrc,
    output wire        Branch,
    output wire        Jump,
    output wire [2:0]  ImmSrc,
    output wire [4:0]  ALUControl,
    output wire [4:0]  FPUControl,
    output wire [2:0]  MemOp,       // Điều khiển LB, LH, LW, LBU, LHU
    output wire        CSR,
    output wire        Fence,
    output wire        Atomic
);

    wire [1:0] ALUOp;
    wire       RegWrite_Main; // Tín hiệu RegWrite từ Main Decoder

    // 1. Gọi Main Decoder 
    Main_Decoder md (
        .Op(Op), 
        .RegWrite(RegWrite_Main), 
        .ALUSrc(ALUSrc),
        .MemWrite(MemWrite), 
        .MemRead(MemRead), 
        .ResultSrc(ResultSrc),
        .Branch(Branch), 
        .Jump(Jump), 
        .ImmSrc(ImmSrc),
        .ALUOp(ALUOp), 
        .CSR(CSR), 
        .Fence(Fence), 
        .Atomic(Atomic)
    );

    // 2. Logic MemOp (Dùng funct3 để biết đọc/ghi byte, halfword hay word)
    assign MemOp = funct3;

    // 3. Gọi ALU Decoder (Cho tập I, M và tính địa chỉ cho tập A)
    wire is_op_imm = (Op == 7'b0010011);
    ALU_Decoder alu_dec (
        .ALUOp(ALUOp), 
        .funct3(funct3), 
        .funct7(funct7), 
        .is_op_imm(is_op_imm), 
        .ALUControl(ALUControl)
    );

    // 4. Gọi FPU Decoder (Cho tập F)
    FPU_Decoder fpu_dec (
        .opcode(Op), 
        .funct7(funct7), 
        .funct3(funct3), 
        .FPUControl(FPUControl)
    );

    // 5. Phân loại ghi thanh ghi (Quan trọng cho tập F)
    // fpu_writes_to_int = 1 khi kết quả của FPU cần ghi vào thanh ghi số nguyên (X)
    reg fpu_writes_to_int;
    always @(*) begin
        case (FPUControl)
            5'b01000, 5'b01001, 5'b01010, // FEQ.S, FLT.S, FLE.S
            5'b01100, 5'b01101,           // FCVT.W.S, FCVT.WU.S
            5'b10000, 5'b10010:           // FMV.X.W, FCLASS.S
                fpu_writes_to_int = 1'b1;
            default: 
                fpu_writes_to_int = 1'b0;
        endcase
    end

    wire is_FOP = (Op == 7'b1010011); // Opcode lệnh tính toán số thực
    wire is_FLW = (Op == 7'b0000111); // Opcode Load Float

    // Quyết định cuối cùng ghi vào Register File nào:
    // - Ghi thanh ghi Int khi: Main Decoder yêu cầu HOẶC lệnh FPU trả kết quả về Int
    assign RegWrite   = RegWrite_Main | (is_FOP & fpu_writes_to_int);
    
    // - Ghi thanh ghi Float khi: Lệnh FLW (Load Float) HOẶC lệnh FPU trả kết quả về Float
    assign FPRegWrite = is_FLW | (is_FOP & ~fpu_writes_to_int);

endmodule