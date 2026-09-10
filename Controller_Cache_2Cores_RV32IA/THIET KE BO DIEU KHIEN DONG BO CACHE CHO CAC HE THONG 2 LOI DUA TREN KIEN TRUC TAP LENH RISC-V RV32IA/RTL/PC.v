`timescale 1ns/1ps
// from Lee Min Hunz with luv
module PC #(
    parameter WIDTH     = 32,
    parameter START_PC  = 32'd0
    // parameter END_PC    = 32'd1024
)(
    input       clk, rst_n, EN
,   input       [WIDTH - 1:0] PCNext
,   output reg  [WIDTH - 1:0] PC
);
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            PC <= START_PC;
        end else begin
            if (~EN) begin
                PC <= PCNext;
            end
        end
    end
endmodule
