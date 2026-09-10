`timescale 1ns/1ps
// from Lee Min Hunz with luv
module AluDecoder(
    input       [2:0]   ALUOp
,   input       [2:0]   funct3
,   input               funct7_5, op_5
,   output reg  [3:0]   ALUControl
);
    always @(*) begin
        case(ALUOp)
            3'b000: begin
                ALUControl = 4'b0000;    // (add) intruction lw, sw
            end 
            3'b001: begin
                ALUControl = 4'b1000;    // (sub) intruction beq 
            end 
            3'b010: begin
                case(funct3)
                    3'b00: begin
                        case({op_5, funct7_5})
                            2'b00, 2'b01, 2'b10:    ALUControl = 4'b0000;    // (add) intruction add
                            2'b11:                  ALUControl = 4'b1000;    // (sub) intruction sub
                            default:                ALUControl = 4'b0000;
                        endcase
                    end 
                    3'b001: begin
                        ALUControl = 4'b0001;   // (ShiftLeftLogical) sll
                    end 
                    3'b010: begin
                        ALUControl = 4'b1001;   // (set less than) slt
                    end 
                    3'b011: begin
                        ALUControl = 4'b1010;   // SetLessThan(U) sltu
                    end 
                    3'b100: begin
                        ALUControl = 4'b0110;   // xor
                    end 
                    3'b101: begin
                        case({op_5, funct7_5})
                            2'b10, 2'b00:   ALUControl = 4'b0010;    // ShiftRightLogical srl/srli
                            2'b11, 2'b01:   ALUControl = 4'b0011;    // ShiftRightArith sra/srai
                            default:        ALUControl = 4'b0000;
                        endcase
                    end 
                    3'b110: begin
                        ALUControl = 4'b0101;   // or 
                    end 
                    3'b111: begin
                        ALUControl = 4'b0100;   // and 
                    end 
                    default: begin
                        ALUControl = 4'b0000;
                    end 
                endcase
            end
            3'b011: begin
                ALUControl = 4'b0111;   // (lui) intruction lui
            end
            3'b100: begin
                ALUControl = 4'b1011;   // (auipc) instruction auipc
            end
            3'b101: begin
                ALUControl = 4'b1100;   // jal/ jalr
            end
            default: begin
                ALUControl = 4'b0000;
            end
        endcase
    end 
endmodule