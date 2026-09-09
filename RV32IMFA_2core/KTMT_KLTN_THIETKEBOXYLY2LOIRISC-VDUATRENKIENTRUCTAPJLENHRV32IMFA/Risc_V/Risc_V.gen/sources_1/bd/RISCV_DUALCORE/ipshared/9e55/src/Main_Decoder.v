module Main_Decoder(
    input  wire [6:0] Op,          // Opcode từ lệnh
    output wire       RegWrite,    // Ghi vào Register File (Int)
    output wire       ALUSrc,      // Chọn nguồn cho ALU (Reg vs Imm)
    output wire       MemWrite,    // Ghi vào bộ nhớ
    output wire       MemRead,     // Đọc từ bộ nhớ
    output wire [1:0] ResultSrc,   // Chọn nguồn ghi về WB (00:ALU, 01:Mem, 10:PC+4, 11:Imm)
    output wire       Branch,      // Lệnh rẽ nhánh
    output wire       Jump,        // Lệnh nhảy (JAL, JALR)
    output wire [2:0] ImmSrc,      // Loại số tức thời (I, S, B, U, J, Zero)
    output wire [1:0] ALUOp,       // Mã nhóm cho ALU Decoder
    output wire       CSR,         // Lệnh hệ thống
    output wire       Fence,       // Lệnh rào cản bộ nhớ
    output wire       Atomic       // Báo hiệu khóa Bus/Nguyên tử
);

    // --- Định nghĩa các Opcodes chuẩn RISC-V ---
    localparam OP_LUI      = 7'b0110111;
    localparam OP_AUIPC    = 7'b0010111;
    localparam OP_JAL      = 7'b1101111;
    localparam OP_JALR     = 7'b1100111;
    localparam OP_BRANCH   = 7'b1100011;
    localparam OP_LOAD     = 7'b0000011;
    localparam OP_STORE    = 7'b0100011;
    localparam OP_OP_IMM   = 7'b0010011;
    localparam OP_OP       = 7'b0110011;
    localparam OP_AMO      = 7'b0101111; // Tập lệnh Atomic (A)
    localparam OP_MISC_MEM = 7'b0001111; // FENCE
    localparam OP_SYSTEM   = 7'b1110011; // CSR, ECALL, EBREAK
    
    // Opcodes cho tập F 
    localparam OP_FLW      = 7'b0000111;
    localparam OP_FSW      = 7'b0100111;

    // 1. Tín hiệu Atomic: Bật khi gặp Opcode AMO (LR, SC, AMOs)
    assign Atomic = (Op == OP_AMO);

    // 2. RegWrite: Cho phép ghi vào Register File số nguyên
    assign RegWrite = (Op == OP_LUI)    ||
                      (Op == OP_AUIPC)  ||
                      (Op == OP_JAL)    ||
                      (Op == OP_JALR)   ||
                      (Op == OP_LOAD)   ||
                      (Op == OP_OP_IMM) ||
                      (Op == OP_OP)     ||
                      (Op == OP_AMO);   

    // 3. ImmSrc: Xác định cách giải mã Immediate
    assign ImmSrc = (Op == OP_STORE || Op == OP_FSW) ? 3'b001 :
                    (Op == OP_BRANCH)                ? 3'b010 :
                    (Op == OP_LUI || Op == OP_AUIPC) ? 3'b011 :
                    (Op == OP_JAL)                   ? 3'b100 :
                    (Op == OP_AMO)                   ? 3'b101 : // Trả về 0 cho Atomic
                    3'b000; // Mặc định I-type (Load, JALR, OP-IMM)

    // 4. ALUSrc: 0 dùng Rs2, 1 dùng Immediate
    assign ALUSrc = (Op == OP_LOAD)   || (Op == OP_FLW)    ||
                    (Op == OP_STORE)  || (Op == OP_FSW)    ||
                    (Op == OP_OP_IMM) || (Op == OP_JALR)   ||
                    (Op == OP_AUIPC)  || (Op == OP_LUI)    ||
                    (Op == OP_AMO);   // Dùng Imm=0 để tính địa chỉ

    // 5. MemWrite: Cho phép ghi vào bộ nhớ
    assign MemWrite = (Op == OP_STORE) || (Op == OP_FSW) || (Op == OP_AMO);

    // 6. MemRead: Cho phép đọc từ bộ nhớ
    assign MemRead = (Op == OP_LOAD) || (Op == OP_FLW) || (Op == OP_AMO);

    // 7. ResultSrc: Chọn dữ liệu ghi về thanh ghi
    assign ResultSrc = (Op == OP_LOAD || Op == OP_FLW || Op == OP_AMO) ? 2'b01 : 
                       (Op == OP_JAL  || Op == OP_JALR)                ? 2'b10 :
                       (Op == OP_LUI  || Op == OP_AUIPC)               ? 2'b11 :
                       2'b00; // Mặc định lấy từ ALU

    // 8. Tín hiệu rẽ nhánh và nhảy
    assign Branch = (Op == OP_BRANCH);
    assign Jump   = (Op == OP_JAL) || (Op == OP_JALR);
    assign CSR    = (Op == OP_SYSTEM);
    assign Fence  = (Op == OP_MISC_MEM);

    // 9. ALUOp: Phân nhóm cho ALU Decoder
    assign ALUOp = (Op == OP_OP || Op == OP_OP_IMM) ? 2'b10 : // R-type/I-type
                   (Op == OP_BRANCH)                ? 2'b01 : // Branch
                   (Op == OP_AMO)                   ? 2'b11 : // Atomic
                   2'b00; // Load/Store/LUI/AUIPC -> ALU thực hiện ADD

endmodule