`timescale 1ns / 1ps

module Main_Decoder(
    input  wire [6:0] Op,
    input  wire [4:0] Funct5,   // Instr[31:27] dùng cho RV32A

    output reg        RegWrite,
    output reg        ALUSrc,
    output reg  [1:0] ALUSrcA,     // 00: rs1, 01: PC, 10: zero
    output reg        MemWrite,
    output reg        MemRead,
    output reg  [1:0] ResultSrc,   // 00: ALU, 01: MEM, 10: PC+4
    output reg        Branch,
    output reg        Jump,
    output reg  [2:0] ImmSrc,
    output reg  [1:0] ALUOp,
    output reg        CSR,
    output reg        Fence,
    output reg        Atomic
);

    // ============================================================
    // OPCODE ENCODING
    // ============================================================
    localparam [6:0]
        OP_LOAD     = 7'b0000011,
        OP_MISC_MEM = 7'b0001111,
        OP_OP_IMM   = 7'b0010011,
        OP_AUIPC    = 7'b0010111,
        OP_STORE    = 7'b0100011,
        OP_AMO      = 7'b0101111,
        OP_OP       = 7'b0110011,
        OP_LUI      = 7'b0110111,
        OP_BRANCH   = 7'b1100011,
        OP_JALR     = 7'b1100111,
        OP_JAL      = 7'b1101111,
        OP_SYSTEM   = 7'b1110011;

    // ============================================================
    // RV32A FUNCT5 ENCODING
    // Instr[31:27]
    // ============================================================
    localparam [4:0]
        AMO_ADD     = 5'b00000,   // AMOADD.W
        AMO_SWAP    = 5'b00001,   // AMOSWAP.W
        AMO_LR      = 5'b00010,   // LR.W
        AMO_SC      = 5'b00011,   // SC.W
        AMO_XOR     = 5'b00100,   // AMOXOR.W
        AMO_OR      = 5'b01000,   // AMOOR.W
        AMO_AND     = 5'b01100,   // AMOAND.W
        AMO_MIN     = 5'b10000,   // AMOMIN.W
        AMO_MAX     = 5'b10100,   // AMOMAX.W
        AMO_MINU    = 5'b11000,   // AMOMINU.W
        AMO_MAXU    = 5'b11100;   // AMOMAXU.W

    // ============================================================
    // MAIN DECODE
    // ============================================================
    always @(*) begin
        // Default: NOP / invalid instruction
        RegWrite  = 1'b0;
        ALUSrc    = 1'b0;
        ALUSrcA   = 2'b00;
        MemWrite  = 1'b0;
        MemRead   = 1'b0;
        ResultSrc = 2'b00;
        Branch    = 1'b0;
        Jump      = 1'b0;
        ImmSrc    = 3'b000;
        ALUOp     = 2'b00;
        CSR       = 1'b0;
        Fence     = 1'b0;
        Atomic    = 1'b0;

        case (Op)

            // ====================================================
            // Integer load: LB/LH/LW/LBU/LHU
            // rd <- MEM[rs1 + imm]
            // ====================================================
            OP_LOAD: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                ALUSrcA   = 2'b00;   // rs1
                MemRead   = 1'b1;
                MemWrite  = 1'b0;
                ResultSrc = 2'b01;   // MEM
                ImmSrc    = 3'b000;  // I-type
                ALUOp     = 2'b00;   // ADD address
            end

            // ====================================================
            // Integer store: SB/SH/SW
            // MEM[rs1 + imm] <- rs2
            // ====================================================
            OP_STORE: begin
                RegWrite  = 1'b0;
                ALUSrc    = 1'b1;
                ALUSrcA   = 2'b00;   // rs1
                MemRead   = 1'b0;
                MemWrite  = 1'b1;
                ImmSrc    = 3'b001;  // S-type
                ALUOp     = 2'b00;   // ADD address
            end

            // ====================================================
            // Integer OP-IMM
            // ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
            // ====================================================
            OP_OP_IMM: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                ALUSrcA   = 2'b00;   // rs1
                ResultSrc = 2'b00;   // ALU
                ImmSrc    = 3'b000;  // I-type
                ALUOp     = 2'b10;
            end

            // ====================================================
            // Integer OP
            // RV32I R-type + RV32M M-extension
            // ====================================================
            OP_OP: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b0;
                ALUSrcA   = 2'b00;   // rs1
                ResultSrc = 2'b00;   // ALU/MDU tùy execute_stage
                ALUOp     = 2'b10;
            end

            // ====================================================
            // Branch
            // BEQ/BNE/BLT/BGE/BLTU/BGEU
            // ====================================================
            OP_BRANCH: begin
                RegWrite  = 1'b0;
                ALUSrc    = 1'b0;
                ALUSrcA   = 2'b00;   // rs1
                Branch    = 1'b1;
                ImmSrc    = 3'b010;  // B-type
                ALUOp     = 2'b01;   // compare/sub
            end

            // ====================================================
            // LUI
            // rd <- imm
            // ALU input A = zero, input B = U-imm
            // ====================================================
            OP_LUI: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                ALUSrcA   = 2'b10;   // zero
                ResultSrc = 2'b00;   // ALU
                ImmSrc    = 3'b011;  // U-type
                ALUOp     = 2'b00;   // ADD zero + imm
            end

            // ====================================================
            // AUIPC
            // rd <- PC + imm
            // ALU input A = PC, input B = U-imm
            // ====================================================
            OP_AUIPC: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                ALUSrcA   = 2'b01;   // PC
                ResultSrc = 2'b00;   // ALU
                ImmSrc    = 3'b011;  // U-type
                ALUOp     = 2'b00;   // ADD PC + imm
            end

            // ====================================================
            // JAL
            // rd <- PC + 4, PC <- PC + imm
            // ====================================================
            OP_JAL: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                ALUSrcA   = 2'b01;   // PC
                Jump      = 1'b1;
                ResultSrc = 2'b10;   // PC+4
                ImmSrc    = 3'b100;  // J-type
                ALUOp     = 2'b00;
            end

            // ====================================================
            // JALR
            // rd <- PC + 4, PC <- rs1 + imm
            // ====================================================
            OP_JALR: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                ALUSrcA   = 2'b00;   // rs1
                Jump      = 1'b1;
                ResultSrc = 2'b10;   // PC+4
                ImmSrc    = 3'b000;  // I-type
                ALUOp     = 2'b00;
            end

            // ====================================================
            // RV32A: Atomic Memory Operations
            //
            // Format:
            // funct5 = Instr[31:27]
            // aq     = Instr[26]
            // rl     = Instr[25]
            // rs2    = Instr[24:20]
            // rs1    = Instr[19:15]
            // funct3 = Instr[14:12] = 010 for .W
            // rd     = Instr[11:7]
            // opcode = 0101111
            //
            // Địa chỉ A-extension:
            // addr = rs1 + 0
            //
            // LR.W:
            //   rd <- MEM[rs1]
            //   reservation <- rs1
            //
            // SC.W:
            //   nếu reservation hợp lệ:
            //       MEM[rs1] <- rs2
            //       rd <- 0
            //   ngược lại:
            //       rd <- 1
            //
            // AMOxx.W:
            //   old <- MEM[rs1]
            //   MEM[rs1] <- old op rs2
            //   rd <- old
            // ====================================================
            OP_AMO: begin
                RegWrite  = 1'b1;
                ALUSrc    = 1'b1;
                ALUSrcA   = 2'b00;   // rs1
                ResultSrc = 2'b01;   // kết quả từ memory_stage
                ImmSrc    = 3'b101;  // atomic imm = 0
                ALUOp     = 2'b11;   // address = rs1 + 0
                Atomic    = 1'b1;

                case (Funct5)

                    // --------------------------------------------
                    // LR.W
                    // Chỉ đọc memory, không ghi memory.
                    // rd nhận dữ liệu đọc được.
                    // --------------------------------------------
                    AMO_LR: begin
                        MemRead  = 1'b1;
                        MemWrite = 1'b0;
                    end

                    // --------------------------------------------
                    // SC.W
                    // Về mặt control, đây là store có điều kiện.
                    // memory_stage quyết định ghi thật hay không.
                    // rd = 0 nếu thành công, rd = 1 nếu thất bại.
                    // --------------------------------------------
                    AMO_SC: begin
                        MemRead  = 1'b0;
                        MemWrite = 1'b1;
                    end

                    // --------------------------------------------
                    // AMO read-modify-write:
                    // AMOSWAP.W, AMOADD.W, AMOXOR.W, AMOAND.W,
                    // AMOOR.W, AMOMIN.W, AMOMAX.W, AMOMINU.W,
                    // AMOMAXU.W
                    // --------------------------------------------
                    AMO_ADD,
                    AMO_SWAP,
                    AMO_XOR,
                    AMO_OR,
                    AMO_AND,
                    AMO_MIN,
                    AMO_MAX,
                    AMO_MINU,
                    AMO_MAXU: begin
                        MemRead  = 1'b1;
                        MemWrite = 1'b1;
                    end

                    // --------------------------------------------
                    // Funct5 không hợp lệ trong RV32A
                    // Cho thành NOP để tránh ghi sai memory.
                    // --------------------------------------------
                    default: begin
                        RegWrite  = 1'b0;
                        MemRead   = 1'b0;
                        MemWrite  = 1'b0;
                        ResultSrc = 2'b00;
                        Atomic    = 1'b0;
                    end

                endcase
            end

            // ====================================================
            // Fence
            // fence/fence.i nếu bạn chưa xử lý thật thì chỉ set Fence.
            // ====================================================
            OP_MISC_MEM: begin
                RegWrite  = 1'b0;
                MemRead   = 1'b0;
                MemWrite  = 1'b0;
                Fence     = 1'b1;
            end

            // ====================================================
            // CSR / SYSTEM
            // ecall/ebreak/csr...
            // ====================================================
            OP_SYSTEM: begin
                RegWrite  = 1'b0;
                MemRead   = 1'b0;
                MemWrite  = 1'b0;
                CSR       = 1'b1;
            end

            default: begin
                // Giữ default NOP
            end

        endcase
    end

endmodule