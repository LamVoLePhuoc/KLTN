`timescale 1ns/1ps
// from Lee Min Hunz with luv
// ============================================================================
// IF_ID Pipeline Register
// ============================================================================
// Pipeline stage: Stage2/ICache (S2) -> Decode (ID)
//
// Function:
//   - Registers fetched instruction and PC values
//   - Passes branch prediction info to decode stage
//   - Supports flush (misprediction) and stall (data hazard)
//
// Flush behavior: On D_Flush, instruction is replaced with NOP (0x00000000)
// Stall behavior: On EN=1, register values are held
// ============================================================================
module IF_ID #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input                           clk, rst_n 
,   input                           EN 
,   input                           D_Flush
,   input                           F_Predict_Taken
,   input       [DATA_WIDTH - 1:0]  F_RD 
,   input       [ADDR_WIDTH - 1:0]  F_PC
,   input       [ADDR_WIDTH - 1:0]  F_PCPlus4
,   input       [2:0]               F_GHSR
// ,   input                           s2_ignore_instr
    
,   output reg                      D_Predict_Taken
,   output reg  [DATA_WIDTH - 1:0]  D_Instr
,   output reg  [DATA_WIDTH - 1:0]  D_PC
,   output reg  [ADDR_WIDTH - 1:0]  D_PCPlus4
,   output reg  [2:0]               D_GHSR
// ,   output reg                      D_ignore_instr    
);
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            D_PC            <= 32'd0; 
            D_PCPlus4       <= 32'd0; 
            D_Instr         <= 32'd0;
            D_GHSR          <= 3'd0;
            D_Predict_Taken <= 1'b0;
            // D_ignore_instr  <= 1'b0;
        end 
        else begin
            if (D_Flush) begin
                D_PC            <= 32'd0; 
                D_PCPlus4       <= 32'd0; 
                D_Instr         <= 32'd0; 
                D_GHSR          <= 3'd0;
                D_Predict_Taken <= 1'b0;
                // D_ignore_instr  <= 1'b0;
            end 
            else if (~EN) begin
                D_PC            <= F_PC;
                D_PCPlus4       <= F_PCPlus4;
                D_Instr         <= F_RD;
                D_GHSR          <= F_GHSR;
                D_Predict_Taken <= F_Predict_Taken;
                // D_ignore_instr  <= s2_ignore_instr;
            end
        end 
    end
endmodule
