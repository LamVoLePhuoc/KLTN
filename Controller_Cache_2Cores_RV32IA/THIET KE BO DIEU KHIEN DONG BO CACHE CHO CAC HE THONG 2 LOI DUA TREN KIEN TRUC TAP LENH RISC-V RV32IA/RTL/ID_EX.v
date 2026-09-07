`timescale 1ns/1ps
// from Lee Min Hunz with luv
// ============================================================================
// ID_EX Pipeline Register
// ============================================================================
// Pipeline stage: Decode (ID) -> Execute (EX)
// 
// Function:
//   - Registers decoded instruction data and control signals
//   - Supports flush (from branch misprediction) and stall (from hazards)
//   - Passes register values, immediate, PC, and control signals to EX stage
//
// Flush behavior: On E_Flush, all control signals are cleared (NOP insertion)
// Stall behavior: On EN=1, register values are held (pipeline freeze)
// ============================================================================
module ID_EX #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input                       clk
,   input                       rst_n
,   input                       E_Flush
,   input                       EN

,   input                       D_RegWrite
,   input                       D_MemWrite
,   input                       D_Jump
,   input                       D_Branch
,   input                       D_ALUSrc
,   input                       D_addr_addend_sel
,   input                       D_ResPCSel
// ,   input                       D_RegSrc1
// ,   input                       D_RegSrc2
,   input                       D_Predict_Taken
,   input                       D_data_req
,   input   [DATA_WIDTH - 1:0]  D_RD1
,   input   [DATA_WIDTH - 1:0]  D_RD2
,   input   [DATA_WIDTH - 1:0]  D_ImmExt
,   input   [ADDR_WIDTH - 1:0]  D_PC
,   input   [ADDR_WIDTH - 1:0]  D_PCPlus4
,   input   [2:0]               D_ResultSrc
,   input   [2:0]               D_StoreSrc 
,   input   [2:0]               D_funct3
,   input   [2:0]               D_GHSR
,   input   [3:0]               D_ALUControl
,   input   [4:0]               D_Rs1
,   input   [4:0]               D_Rs2
,   input   [4:0]               D_rd

,   input                       D_amo
,   input       [2:0]           D_amo_op
,   input                       D_lr
,   input                       D_sc

,   input   [DATA_WIDTH - 1:0]  E_SrcA_fix  // Giá trị Forwarding thực tế tại EX
,   input   [DATA_WIDTH - 1:0]  E_SrcB_fix  // Giá trị Forwarding thực tế tại EX (cho rs2)


,   output reg  E_RegWrite
,   output reg  E_MemWrite
,   output reg  E_Jump
,   output reg  E_Branch
,   output reg  E_ALUSrc
,   output reg  E_addr_addend_sel
,   output reg  E_ResPCSel
// ,   output reg  E_RegSrc1 
// ,   output reg  E_RegSrc2
,   output reg  E_Predict_Taken
,   output reg  E_data_req
,   output reg  [DATA_WIDTH - 1:0]  E_RD1
,   output reg  [DATA_WIDTH - 1:0]  E_RD2
,   output reg  [DATA_WIDTH - 1:0]  E_ImmExt
,   output reg  [ADDR_WIDTH - 1:0]  E_PC
,   output reg  [ADDR_WIDTH - 1:0]  E_PCPlus4
,   output reg  [2:0]               E_ResultSrc
,   output reg  [2:0]               E_StoreSrc
,   output reg  [2:0]               E_funct3
,   output reg  [2:0]               E_GHSR
,   output reg  [3:0]               E_ALUControl
,   output reg  [4:0]               E_Rs1
,   output reg  [4:0]               E_Rs2
,   output reg  [4:0]               E_rd

,   output reg                      E_amo
,   output reg  [2:0]               E_amo_op
,   output reg                      E_lr
,   output reg                      E_sc
);
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            E_RD1               <= 32'd0;
            E_RD2               <= 32'd0;
            E_ImmExt            <= 32'd0;
            E_PC                <= 32'd0;
            E_PCPlus4           <= 32'd0;
            E_Rs1               <= 5'd0;
            E_Rs2               <= 5'd0;
            E_rd                <= 5'd0;
            E_ALUControl        <= 4'd0;
            E_StoreSrc          <= 3'd0;
            E_ResultSrc         <= 3'd0;
            E_funct3            <= 3'd0;
            E_GHSR              <= 3'd0;
            E_RegWrite          <= 1'd0;
            E_MemWrite          <= 1'd0;
            E_Jump              <= 1'd0;
            E_Branch            <= 1'd0;
            E_ALUSrc            <= 1'd0;
            E_addr_addend_sel   <= 1'd0;
            E_ResPCSel          <= 1'd0;
            // E_RegSrc1           <= 1'd0;
            // E_RegSrc2           <= 1'd0;
            E_Predict_Taken     <= 1'b0;
            E_data_req          <= 1'b0;

            E_amo               <= 1'b0;
            E_amo_op            <= 3'd0;
            E_lr                <= 1'b0;
            E_sc                <= 1'b0;
        end 
        else begin
            if (E_Flush) begin
                E_RD1               <= 32'd0;
                E_RD2               <= 32'd0;
                E_ImmExt            <= 32'd0;
                E_PC                <= 32'd0;
                E_PCPlus4           <= 32'd0;
                E_Rs1               <= 5'd0;
                E_Rs2               <= 5'd0;
                E_rd                <= 5'd0;
                E_ALUControl        <= 4'd0;
                E_StoreSrc          <= 3'd0;
                E_ResultSrc         <= 3'd0;
                E_funct3            <= 3'd0;
                E_GHSR              <= 3'd0;
                E_RegWrite          <= 1'd0;
                E_MemWrite          <= 1'd0;
                E_Jump              <= 1'd0;
                E_Branch            <= 1'd0;
                E_ALUSrc            <= 1'd0;
                E_addr_addend_sel   <= 1'd0;
                E_ResPCSel          <= 1'd0;
                // E_RegSrc1           <= 1'd0;
                // E_RegSrc2           <= 1'd0;
                E_Predict_Taken     <= 1'b0;
                E_data_req          <= 1'b0;

                E_amo               <= 1'b0;
                E_amo_op            <= 3'd0;
                E_lr                <= 1'b0;
                E_sc                <= 1'b0;
            end 
            else begin 
                if (~EN) begin
                    E_RD1               <= D_RD1             ;
                    E_RD2               <= D_RD2             ;
                    E_ImmExt            <= D_ImmExt          ;
                    E_PC                <= D_PC              ;
                    E_PCPlus4           <= D_PCPlus4         ;
                    E_Rs1               <= D_Rs1             ;
                    E_Rs2               <= D_Rs2             ;
                    E_rd                <= D_rd              ;
                    E_ALUControl        <= D_ALUControl      ;
                    E_StoreSrc          <= D_StoreSrc        ;
                    E_ResultSrc         <= D_ResultSrc       ;
                    E_funct3            <= D_funct3;
                    E_GHSR              <= D_GHSR;
                    E_RegWrite          <= D_RegWrite        ;
                    E_MemWrite          <= D_MemWrite        ;
                    E_Jump              <= D_Jump            ;
                    E_Branch            <= D_Branch          ;
                    E_ALUSrc            <= D_ALUSrc          ;
                    E_addr_addend_sel   <= D_addr_addend_sel ;
                    E_ResPCSel          <= D_ResPCSel        ;
                    // E_RegSrc1           <= D_RegSrc1         ;
                    // E_RegSrc2           <= D_RegSrc2         ;
                    E_Predict_Taken     <= D_Predict_Taken   ;
                    E_data_req          <= D_data_req;

                    E_amo               <= D_amo             ;
                    E_amo_op            <= D_amo_op          ;
                    E_lr                <= D_lr              ;
                    E_sc                <= D_sc              ;
                end 
                else begin
                    E_RD1 <= E_SrcA_fix;
                    E_RD2 <= E_SrcB_fix;
                end 
            end
        end
    end 

endmodule
