`timescale 1ns/1ps
// from Lee Min Hunz with luv
// ============================================================================
// fetch_pipe Pipeline Register
// ============================================================================
// Pipeline stage: Fetch/S1 -> Stage2/S2 (ICache latency compensation)
//
// Function:
//   - Holds PC and branch prediction signals during icache access
//   - Synchronizes fetch stage with icache response
//   - Supports flush (misprediction) and stall (icache miss)
//
// Note: This register exists because icache has 1-cycle latency.
//       S1: Send address to icache
//       S2: Receive instruction from icache
// ============================================================================
module fetch_pipe #(
    parameter DATA_W = 32,
    parameter ADDR_W = 32,
    parameter START_PC = 32'd0
)(
    input clk
,   input rst_n
,   input EN
,   input Flush

,   input                   s1_Predict_Taken
,   input [2:0]             s1_GHSR 
,   input [ADDR_W - 1:0]    s1_PC 
,   input [ADDR_W - 1:0]    s1_PCPlus4
    
    
,   output reg              s2_Predict_Taken
,   output reg [2:0]        s2_GHSR
,   output reg [ADDR_W-1:0] s2_PC
,   output reg [ADDR_W-1:0] s2_PCPlus4
);
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            s2_Predict_Taken    <= 1'b0;
            s2_GHSR             <= 3'd0;
            s2_PC               <= START_PC;
            s2_PCPlus4          <= START_PC + 32'd4;
        end 
        else begin
            if (Flush) begin
                s2_Predict_Taken    <= 1'b0;
                s2_GHSR             <= 3'd0;
                s2_PC               <= {(ADDR_W){1'b0}};
                s2_PCPlus4          <= {(ADDR_W){1'b0}};
            end 
            else if (~EN) begin
                s2_Predict_Taken    <= s1_Predict_Taken;
                s2_GHSR             <= s1_GHSR         ;
                s2_PC               <= s1_PC           ;
                s2_PCPlus4          <= s1_PCPlus4      ;
            end 
        end 
    end 
endmodule