`timescale 1ns / 1ps

module FP_Register_File (
    input  wire        clk,
    input  wire        rst,   // active-high, synchronous
    input  wire        WE3,
    input  wire [4:0]  A1,
    input  wire [4:0]  A2,
    input  wire [4:0]  A3,
    input  wire [4:0]  A_W,
    input  wire [31:0] WD3,
    output wire [31:0] RD1,
    output wire [31:0] RD2,
    output wire [31:0] RD3
);

    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'h00000000;
        end
        else if (WE3) begin
            regs[A_W] <= WD3;
        end
    end

    assign RD1 = (WE3 && (A1 == A_W)) ? WD3 : regs[A1];
    assign RD2 = (WE3 && (A2 == A_W)) ? WD3 : regs[A2];
    assign RD3 = (WE3 && (A3 == A_W)) ? WD3 : regs[A3];

endmodule