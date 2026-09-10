`timescale 1ns/1ps
// from Lee Min Hunz with luv
// ============================================================================
// MEM_WB Pipeline Register
// ============================================================================
// Pipeline stage: Cache (C) -> Writeback (WB)
//
// Function:
//   - Registers final result (after cache response) for writeback
//   - Passes register write control signals
//   - No stall input - always updates (WB is final stage)
// ============================================================================
module MEM_WB #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input                       clk, rst_n
// ,   input                       EN
,   input                       M_RegWrite 
// ,   input                       M_FRegWrite 
// ,   input                       M_MDU_FPUEn 
,   input [DATA_WIDTH - 1:0]    M_mux_result
,   input [4:0]                 M_rd
,   input [2:0]                 M_ResultSrc
    
,   output reg                      W_RegWrite 
// ,   output reg                      W_FRegWrite 
// ,   output reg                      W_MDU_FPUEn 
,   output reg [DATA_WIDTH - 1:0]   W_mux_result
,   output reg [4:0]                W_rd
,   output reg [2:0]                W_ResultSrc
    
);
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            W_mux_result    <= 32'd0;
            W_rd            <= 5'd0;
            W_ResultSrc     <= 3'b0;
            W_RegWrite      <= 1'b0;
            // W_FRegWrite <= 1'b0;
            // W_MDU_FPUEn <= 1'b0;
        end 
        // else if (!EN) begin
        else begin
            W_mux_result    <= M_mux_result;
            W_rd            <= M_rd       ;
            W_ResultSrc     <= M_ResultSrc;
            W_RegWrite      <= M_RegWrite ;
            // W_FRegWrite <= M_FRegWrite;
            // W_MDU_FPUEn <= M_MDU_FPUEn;
        end 
    end 
endmodule
