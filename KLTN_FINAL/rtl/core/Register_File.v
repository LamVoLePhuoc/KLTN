`timescale 1ns / 1ps

module Register_File(
    input  wire        clk,
    input  wire        rst,   // active-high, synchronous
    input  wire        WE3,
    input  wire [4:0]  A1,
    input  wire [4:0]  A2,
    input  wire [4:0]  A3,
    input  wire [31:0] WD3,
    output wire [31:0] RD1,
    output wire [31:0] RD2
);

    reg [31:0] Register [31:1];
    integer i;

    always @(posedge clk) begin
        if (rst) begin
            for (i = 1; i < 32; i = i + 1)
                Register[i] <= 32'h00000000;
        end
        else if (WE3 && (A3 != 5'd0)) begin
            Register[A3] <= WD3;
        end
    end

    assign RD1 = (A1 == 5'd0) ? 32'h00000000 :
                 ((WE3 && (A3 != 5'd0) && (A1 == A3)) ? WD3 : Register[A1]);

    assign RD2 = (A2 == 5'd0) ? 32'h00000000 :
                 ((WE3 && (A3 != 5'd0) && (A2 == A3)) ? WD3 : Register[A2]);

endmodule