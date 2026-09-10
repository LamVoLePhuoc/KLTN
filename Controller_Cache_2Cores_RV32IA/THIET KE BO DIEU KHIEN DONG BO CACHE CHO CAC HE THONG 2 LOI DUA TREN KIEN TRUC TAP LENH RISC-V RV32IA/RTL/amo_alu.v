`timescale 1ns/1ps
// from Lee Min Hunz with luv
module amo_alu #(
    parameter DATA_WIDTH = 32
) (
    input       [DATA_WIDTH-1:0]    i_data_from_mem
,   input       [DATA_WIDTH-1:0]    i_data_from_core
,   input       [2:0]               i_amo_op
,   output  reg [DATA_WIDTH-1:0]    o_amo_alu_result 
);

    always @(*) begin
        case (i_amo_op)
            3'b000: o_amo_alu_result = i_data_from_core;                   //AMOSWAP
            3'b001: o_amo_alu_result = i_data_from_mem + i_data_from_core; // AMOADD
            3'b010: o_amo_alu_result = i_data_from_mem & i_data_from_core; // AMOAND
            3'b011: o_amo_alu_result = i_data_from_mem | i_data_from_core; // AMOOR
            3'b100: o_amo_alu_result = i_data_from_mem ^ i_data_from_core; // AMOXOR
            
            // AMOMAX
            3'b101: o_amo_alu_result = ( $signed(i_data_from_mem)  > $signed(i_data_from_core) ) ? i_data_from_mem : i_data_from_core; 

            // AMOMIN
            3'b110: o_amo_alu_result = ( $signed(i_data_from_mem)  < $signed(i_data_from_core) ) ? i_data_from_mem : i_data_from_core; 
            default: o_amo_alu_result = {DATA_WIDTH{1'b0}};
        endcase
    end
endmodule