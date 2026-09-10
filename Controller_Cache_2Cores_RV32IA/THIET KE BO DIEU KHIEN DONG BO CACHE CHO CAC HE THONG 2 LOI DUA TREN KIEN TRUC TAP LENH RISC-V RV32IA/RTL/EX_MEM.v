`timescale 1ns/1ps
// from Lee Min Hunz with luv
// ============================================================================
// EX_MEM Pipeline Register  
// ============================================================================
// Pipeline stage: Execute (EX) -> Memory (MEM)
//
// Function:
//   - Registers ALU result and data to be stored
//   - Passes control signals for memory access and writeback
//   - Includes atomic operation signals (LR/SC/AMO) for RV32A extension
//
// Stall behavior: On EN=1, register values are held (for dcache stall)
// ============================================================================
module EX_MEM #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input                       clk
,   input                       rst_n
,   input                       EN
,   input                       Flush
,   input                       E_RegWrite
// ,   input                       E_MemWrite
// ,   input                       E_ResPCSel
// ,   input                       E_data_req
,   input   [DATA_WIDTH - 1:0]  E_ALUResult 
// ,   input   [DATA_WIDTH - 1:0]  E_WriteData
// ,   input   [DATA_WIDTH - 1:0]  E_ImmExt

// ,   input   [ADDR_WIDTH - 1:0]  E_PCPlus4
// ,   input   [ADDR_WIDTH - 1:0]  E_PCTarget
,   input   [4:0]               E_rd
,   input   [2:0]               E_ResultSrc 
// ,   input   [2:0]               E_StoreSrc
,   input   [2:0]               E_funct3
// ,   input                       E_amo
// ,   input   [2:0]               E_amo_op
// ,   input                       E_lr
// ,   input                       E_sc
// ,   input                       E_Predict_Taken
// ,   input   [ADDR_WIDTH - 1:0]  E_PC
// ,   input   [ADDR_WIDTH - 1:0]  E_PCPlus4
// ,   input   [ADDR_WIDTH - 1:0]  E_PCTarget
// ,   input                       E_Branch
// ,   input                       E_Jump
// ,   input                       E_PCSrc
// ,   input   [2:0]               E_GHSR

,   output reg                      M_RegWrite
// ,   output reg                      M_MemWrite
// ,   output reg  M_ResPCSel 
// ,   output reg                      M_data_req
,   output reg [DATA_WIDTH - 1:0]   M_ALUResult
// ,   output reg [DATA_WIDTH - 1:0]   M_WriteData
// ,   output reg [DATA_WIDTH - 1:0]   M_ImmExt
// ,   output reg [ADDR_WIDTH - 1:0]   M_PCPlus4
// ,   output reg [ADDR_WIDTH - 1:0]   M_PCTarget
,   output reg  [4:0]               M_rd
,   output reg  [2:0]               M_ResultSrc
// ,   output reg  [2:0]               M_StoreSrc
,   output reg  [2:0]               M_funct3
// ,   output reg                      M_amo
// ,   output reg  [2:0]               M_amo_op
// ,   output reg                      M_lr
// ,   output reg                      M_sc
// ,   output reg                      M_Predict_Taken
// ,   output reg  [ADDR_WIDTH - 1:0]  M_PC
// ,   output reg  [ADDR_WIDTH - 1:0]  M_PCPlus4
// ,   output reg  [ADDR_WIDTH - 1:0]  M_PCTarget
// ,   output reg                      M_Branch
// ,   output reg                      M_Jump
// ,   output reg                      M_PCSrc
// ,   output reg  [2:0]               M_GHSR
);
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            M_ALUResult <= 32'd0;
            // M_WriteData <= 32'd0;
            // M_ImmExt    <= 32'd0;
            // M_PCPlus4   <= 32'd0;
            // M_PCTarget  <= 32'd0;
            M_rd        <= 5'd0;
            M_ResultSrc <= 3'd0;
            // M_StoreSrc  <= 3'd0;
            // M_amo_op    <= 3'd0;
            M_funct3    <= 3'd0;
            M_RegWrite  <= 1'd0;
            // M_MemWrite  <= 1'd0;
            // M_ResPCSel  <= 1'd0;
            // M_data_req  <= 1'b0;
            // M_amo       <= 1'b0;
            // M_lr        <= 1'b0;
            // M_sc        <= 1'b0;

            // M_Predict_Taken <= 1'b0;
            // M_PC            <= 32'd0;
            // M_PCPlus4       <= 32'd0;
            // M_PCTarget      <= 32'd0;
            // M_Branch        <= 1'b0;
            // M_Jump          <= 1'b0;
            // M_PCSrc         <= 1'b0;
            // M_GHSR          <= 3'd0;
        end 
        else if (Flush) begin
            M_RegWrite      <= 1'b0;
            // M_MemWrite      <= 1'b0;
            // M_Branch        <= 1'b0;
            // M_Jump          <= 1'b0;
            // M_PCSrc         <= 1'b0;
            // M_Predict_Taken <= 1'b0; 
            // Các tín hiệu Data như M_PC, M_ALUResult không cần xóa cũng được vì không có RegWrite thì chúng vô hại.
        end
        else if (~EN) begin
            M_ALUResult <= E_ALUResult;
            // M_WriteData <= E_WriteData;
            // M_ImmExt    <= E_ImmExt   ;
            // M_PCPlus4   <= E_PCPlus4  ;
            // M_PCTarget  <= E_PCTarget ;
            M_rd        <= E_rd       ;
            M_ResultSrc <= E_ResultSrc;
            // M_StoreSrc  <= E_StoreSrc ;
            M_RegWrite  <= E_RegWrite ;
            // M_MemWrite  <= E_MemWrite ;
            // M_ResPCSel  <= E_ResPCSel ;
            M_funct3    <= E_funct3;
            // M_data_req  <= E_data_req ;
            // M_amo       <= E_amo      ;
            // M_amo_op    <= E_amo_op   ;
            // M_lr        <= E_lr       ;
            // M_sc        <= E_sc       ;

            // M_Predict_Taken <= E_Predict_Taken;
            // M_PC            <= E_PC           ;
            // M_PCPlus4       <= E_PCPlus4      ;
            // M_PCTarget      <= E_PCTarget     ;
            // M_Branch        <= E_Branch       ;
            // M_Jump          <= E_Jump         ;
            // M_PCSrc         <= E_PCSrc        ;
            // M_GHSR          <= E_GHSR         ;
        end 
    end 
endmodule
