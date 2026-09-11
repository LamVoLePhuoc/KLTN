`timescale 1ns / 1ps

module id_ex_registers(
    input  wire         clk,
    input  wire         rst,      // active-high, synchronous
    input  wire         stall,
    input  wire         flush,

    // --- Inputs từ Decode stage ---
    input  wire         RegWriteD,
    input  wire         ALUSrcD,
    input  wire [1:0]   ALUSrcA_D,
    input  wire         MemWriteD,
    input  wire         MemReadD,
    input  wire [1:0]   ResultSrcD,
    input  wire         BranchD,
    input  wire         JumpD,
    input  wire [4:0]   ALUControlD,

    // --- RV32A control ---
    input  wire         AtomicD,
    input  wire [4:0]   AmoOpD,

    // --- Other control ---
    input  wire [2:0]   MemOpD,
    input  wire         CSR_D,
    input  wire         Fence_D,
    input  wire [6:0]   OpD,

    // --- NEW: trap/exception tagging, packed as one bus purely to
    // keep this pipeline-register file's port count manageable --
    // see RV32IMA.v for the bit assignment (unpacked back into named
    // signals there, where csr_trap_unit.v actually consumes them).
    input  wire [7:0]   ExcFlagsD,
    input  wire [31:0]  InstrD,

    // --- Integer data từ Decode stage ---
    input  wire [31:0]  RD1_D,
    input  wire [31:0]  RD2_D,
    input  wire [31:0]  Imm_Ext_D,
    input  wire [31:0]  PCD,
    input  wire [31:0]  PCPlus4D,

    input  wire [4:0]   RD_D,
    input  wire [4:0]   RS1_D,
    input  wire [4:0]   RS2_D,

    // --- Outputs sang Execute stage ---
    output reg          RegWriteE,
    output reg          ALUSrcE,
    output reg  [1:0]   ALUSrcA_E,
    output reg          MemWriteE,
    output reg          MemReadE,
    output reg  [1:0]   ResultSrcE,
    output reg          BranchE,
    output reg          JumpE,
    output reg  [4:0]   ALUControlE,

    // --- RV32A control ---
    output reg          AtomicE,
    output reg  [4:0]   AmoOpE,

    // --- Other control ---
    output reg  [2:0]   MemOpE,
    output reg          CSR_E,
    output reg          Fence_E,
    output reg  [6:0]   OpE,

    // --- NEW: see the matching input above ---
    output reg  [7:0]   ExcFlagsE,
    output reg  [31:0]  InstrE,

    // --- Integer data sang Execute stage ---
    output reg  [31:0]  RD1_E,
    output reg  [31:0]  RD2_E,
    output reg  [31:0]  Imm_Ext_E,
    output reg  [31:0]  PCE,
    output reg  [31:0]  PCPlus4E,

    output reg  [4:0]   RD_E,
    output reg  [4:0]   RS1_E,
    output reg  [4:0]   RS2_E
);

    always @(posedge clk) begin
        if (rst) begin
            // =====================================================
            // RESET: clear control
            // =====================================================
            RegWriteE   <= 1'b0;
            ALUSrcE     <= 1'b0;
            ALUSrcA_E   <= 2'b00;
            MemWriteE   <= 1'b0;
            MemReadE    <= 1'b0;
            ResultSrcE  <= 2'b00;
            BranchE     <= 1'b0;
            JumpE       <= 1'b0;
            ALUControlE <= 5'b00000;

            AtomicE     <= 1'b0;
            AmoOpE      <= 5'b00000;

            MemOpE      <= 3'b000;
            CSR_E       <= 1'b0;
            Fence_E     <= 1'b0;
            OpE         <= 7'b0000000;
            ExcFlagsE   <= 8'b0;
            InstrE      <= 32'h00000013;

            // =====================================================
            // RESET: clear integer data
            // =====================================================
            RD1_E       <= 32'b0;
            RD2_E       <= 32'b0;
            Imm_Ext_E   <= 32'b0;
            PCE         <= 32'b0;
            PCPlus4E    <= 32'b0;

            RD_E        <= 5'b00000;
            RS1_E       <= 5'b00000;
            RS2_E       <= 5'b00000;
        end

        else if (flush) begin
            // =====================================================
            // FLUSH: insert clean bubble
            // Xóa cả control, metadata, address, data
            // =====================================================
            RegWriteE   <= 1'b0;
            ALUSrcE     <= 1'b0;
            ALUSrcA_E   <= 2'b00;
            MemWriteE   <= 1'b0;
            MemReadE    <= 1'b0;
            ResultSrcE  <= 2'b00;
            BranchE     <= 1'b0;
            JumpE       <= 1'b0;
            ALUControlE <= 5'b00000;

            AtomicE     <= 1'b0;
            AmoOpE      <= 5'b00000;

            MemOpE      <= 3'b000;
            CSR_E       <= 1'b0;
            Fence_E     <= 1'b0;
            OpE         <= 7'b0000000;
            ExcFlagsE   <= 8'b0;
            InstrE      <= 32'h00000013;

            RD1_E       <= 32'b0;
            RD2_E       <= 32'b0;
            Imm_Ext_E   <= 32'b0;
            PCE         <= 32'b0;
            PCPlus4E    <= 32'b0;

            RD_E        <= 5'b00000;
            RS1_E       <= 5'b00000;
            RS2_E       <= 5'b00000;
        end

        else if (!stall) begin
            // =====================================================
            // NORMAL PIPELINE TRANSFER: D -> E
            // =====================================================

            // --- control ---
            RegWriteE   <= RegWriteD;
            ALUSrcE     <= ALUSrcD;
            ALUSrcA_E   <= ALUSrcA_D;
            MemWriteE   <= MemWriteD;
            MemReadE    <= MemReadD;
            ResultSrcE  <= ResultSrcD;
            BranchE     <= BranchD;
            JumpE       <= JumpD;
            ALUControlE <= ALUControlD;

            // --- RV32A ---
            AtomicE     <= AtomicD;
            AmoOpE      <= AmoOpD;

            // --- other control ---
            MemOpE      <= MemOpD;
            CSR_E       <= CSR_D;
            Fence_E     <= Fence_D;
            OpE         <= OpD;
            ExcFlagsE   <= ExcFlagsD;
            InstrE      <= InstrD;

            // --- integer data ---
            RD1_E       <= RD1_D;
            RD2_E       <= RD2_D;
            Imm_Ext_E   <= Imm_Ext_D;
            PCE         <= PCD;
            PCPlus4E    <= PCPlus4D;

            RD_E        <= RD_D;
            RS1_E       <= RS1_D;
            RS2_E       <= RS2_D;
        end

        // stall = 1 -> giữ nguyên toàn bộ thanh ghi pipeline
    end

endmodule
