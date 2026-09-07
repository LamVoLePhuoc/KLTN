`timescale 1ns/1ps
// from Lee Min Hunz with luv
module BranchDecoder(
    input E_Jump, E_Zero, E_Branch, E_signed_less, E_unsigned_less
,   input [2:0] funct3
,   output E_PCSrc
);
    reg E_con;
    always @(*) begin
        case(funct3)
            3'b000: begin   // beq
                E_con = E_Zero;
            end 
            3'b001: begin   // bne
                E_con = ~E_Zero;
            end 
            3'b100: begin   // blt 
                E_con = E_signed_less;
            end 
            3'b101: begin   // bge 
                E_con = ~E_signed_less;
            end 
            3'b110: begin   // bltu 
                E_con = E_unsigned_less;
            end
            3'b111: begin   // bgeu 
                E_con = ~E_unsigned_less;
            end 
            default: begin
                E_con = 1'b0;
            end 
        endcase
    end

    assign E_PCSrc = E_Jump | (E_con & E_Branch);
endmodule