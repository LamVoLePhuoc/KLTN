`timescale 1ns/1ps
// from Lee Min Hunz with luv
module Ins_Mem #(
    parameter integer WIDTH_ADDR = 32,
    parameter integer WIDTH_DATA = 32
)(
    input  [WIDTH_ADDR - 1:0] addr
,   output [WIDTH_DATA - 1:0] instruction
);
    reg [31:0] rom [0:4095];
//    reg [31:0] out;
    
    initial begin: init_and_load
        $readmemh("C:/Law/ISS-RV32ICMFA/Verilog/hexfile.txt", rom);
    end
    // always @(posedge clk) begin
    //     out <= rom[(addr >> 2)];
    // end
    
    assign instruction = rom[(addr >> 2)]; 
endmodule
