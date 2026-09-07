`timescale 1ns / 1ps

module if_id_registers #(
    parameter [31:0] RESET_VECTOR = 32'h0000_0000
)(
    input         clk,
    input         rst,
    input         stall,
    input         flush,
    input  [31:0] InstrF,
    input  [31:0] PCF,
    input  [31:0] PCPlus4F,
    output reg [31:0] InstrD,
    output reg [31:0] PCD,
    output reg [31:0] PCPlus4D
);

    localparam NOP_INSTRUCTION = 32'h00000013;

    always @(posedge clk) begin
        if (rst) begin
            InstrD   <= NOP_INSTRUCTION;
            PCD      <= RESET_VECTOR;
            PCPlus4D <= RESET_VECTOR + 32'h4;
        end
        else if (flush) begin
            InstrD   <= NOP_INSTRUCTION;
            PCD      <= 32'h0;
            PCPlus4D <= 32'h0;
        end
        else if (!stall) begin
            InstrD   <= InstrF;
            PCD      <= PCF;
            PCPlus4D <= PCPlus4F;
        end
    end

endmodule