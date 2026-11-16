`timescale 1ns / 1ps

module ALU_Decoder (
    input  wire [1:0] ALUOp,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    input  wire       is_op_imm,
    output reg  [4:0] ALUControl
);
    localparam [4:0]
        ALU_ADD    = 5'b00000,
        ALU_SUB    = 5'b00001,
        ALU_SLL    = 5'b00010,
        ALU_SLT    = 5'b00011,
        ALU_SLTU   = 5'b00100,
        ALU_XOR    = 5'b00101,
        ALU_SRL    = 5'b00110,
        ALU_SRA    = 5'b00111,
        ALU_OR     = 5'b01000,
        ALU_AND    = 5'b01001,

        ALU_MUL    = 5'b10000,
        ALU_MULH   = 5'b10001,
        ALU_MULHSU = 5'b10010,
        ALU_MULHU  = 5'b10011,
        ALU_DIV    = 5'b10100,
        ALU_DIVU   = 5'b10101,
        ALU_REM    = 5'b10110,
        ALU_REMU   = 5'b10111;

    wire is_m_group = (ALUOp == 2'b10) && (!is_op_imm) && (funct7 == 7'b0000001);

    always @(*) begin
        case (ALUOp)
            2'b00: ALUControl = ALU_ADD; // load/store/addi address
            2'b01: ALUControl = ALU_SUB; // branch compare
            2'b10: begin
                if (is_m_group) begin
                    case (funct3)
                        3'b000: ALUControl = ALU_MUL;
                        3'b001: ALUControl = ALU_MULH;
                        3'b010: ALUControl = ALU_MULHSU;
                        3'b011: ALUControl = ALU_MULHU;
                        3'b100: ALUControl = ALU_DIV;
                        3'b101: ALUControl = ALU_DIVU;
                        3'b110: ALUControl = ALU_REM;
                        3'b111: ALUControl = ALU_REMU;
                        default: ALUControl = ALU_ADD;
                    endcase
                end else begin
                    case (funct3)
                        3'b000: ALUControl = (!is_op_imm && funct7[5]) ? ALU_SUB : ALU_ADD;
                        3'b001: ALUControl = ALU_SLL;
                        3'b010: ALUControl = ALU_SLT;
                        3'b011: ALUControl = ALU_SLTU;
                        3'b100: ALUControl = ALU_XOR;
                        3'b101: ALUControl = funct7[5] ? ALU_SRA : ALU_SRL;
                        3'b110: ALUControl = ALU_OR;
                        3'b111: ALUControl = ALU_AND;
                        default: ALUControl = ALU_ADD;
                    endcase
                end
            end
            2'b11: ALUControl = ALU_ADD; // atomic address calc
            default: ALUControl = ALU_ADD;
        endcase
    end
endmodule