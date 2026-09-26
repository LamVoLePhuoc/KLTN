`timescale 1ns / 1ps

module fetch_stage #(
    parameter [31:0] RESET_ADDR = 32'h0000_0000
) (
    input         clk,
    input         rst,
    input         stall,
    input         bus_ready,
    input         PCSrcE,
    input  [31:0] PCTargetE,

    output [31:0] PCF,
    output [31:0] PCPlus4F
);

    wire [31:0] PC_Next;
    wire        PC_Write;

    assign PC_Write = bus_ready && (~stall || PCSrcE);

    mux PC_MUX (
        .a(PCPlus4F),
        .b(PCTargetE),
        .s(PCSrcE),
        .c(PC_Next)
    );

    PC_module #(.RESET_VECTOR(RESET_ADDR)) Program_Counter (
        .clk(clk),
        .rst(rst),
        .PC_Write(PC_Write),
        .PC_Next(PC_Next),
        .PC(PCF)
    );

    PC_Adder PC_adder (
        .a(PCF),
        .b(32'h4),
        .c(PCPlus4F)
    );

endmodule