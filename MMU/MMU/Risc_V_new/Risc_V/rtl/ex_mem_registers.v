`timescale 1ns / 1ps

module ex_mem_registers(
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // --- Control Signals from Execute (E) ---
    input  wire        RegWriteE,
    input  wire        MemWriteE,
    input  wire        MemReadE,
    input  wire [1:0]  ResultSrcE,
    input  wire        AtomicE,
    input  wire [4:0]  AmoOpE,
    input  wire        FPRegWriteE,
    input  wire [2:0]  MemOpE,
    input  wire        CSR_E,
    input  wire        Fence_E,

    // --- Data Signals from Execute (E) ---
    input  wire [4:0]  RD_E,
    input  wire [4:0]  RD_F_E,
    input  wire [31:0] PCPlus4E,
    input  wire [31:0] ALU_ResultE,
    input  wire [31:0] WriteDataE,

    // --- Outputs to Memory (M) ---
    output reg         RegWriteM,
    output reg         MemWriteM,
    output reg         MemReadM,
    output reg  [1:0]  ResultSrcM,
    output reg         AtomicM,
    output reg  [4:0]  AmoOpM,
    output reg         FPRegWriteM,
    output reg  [2:0]  MemOpM,
    output reg         CSR_M,
    output reg         Fence_M,

    output reg  [4:0]  RD_M,
    output reg  [4:0]  RD_F_M,
    output reg  [31:0] PCPlus4M,
    output reg  [31:0] ALU_ResultM,
    output reg  [31:0] WriteDataM
);

    always @(posedge clk) begin
        if (rst) begin
            RegWriteM   <= 1'b0;
            MemWriteM   <= 1'b0;
            MemReadM    <= 1'b0;
            ResultSrcM  <= 2'b00;
            AtomicM     <= 1'b0;
            AmoOpM      <= 5'b00000;
            FPRegWriteM <= 1'b0;
            MemOpM      <= 3'b000;
            CSR_M       <= 1'b0;
            Fence_M     <= 1'b0;

            RD_M        <= 5'b00000;
            RD_F_M      <= 5'b00000;
            PCPlus4M    <= 32'b0;
            ALU_ResultM <= 32'b0;
            WriteDataM  <= 32'b0;
        end
        else if (flush) begin
            // Bubble sạch
            RegWriteM   <= 1'b0;
            MemWriteM   <= 1'b0;
            MemReadM    <= 1'b0;
            ResultSrcM  <= 2'b00;
            AtomicM     <= 1'b0;
            AmoOpM      <= 5'b00000;
            FPRegWriteM <= 1'b0;
            MemOpM      <= 3'b000;
            CSR_M       <= 1'b0;
            Fence_M     <= 1'b0;

            RD_M        <= 5'b00000;
            RD_F_M      <= 5'b00000;
            PCPlus4M    <= 32'b0;
            ALU_ResultM <= 32'b0;
            WriteDataM  <= 32'b0;
        end
        else if (!stall) begin
            RegWriteM   <= RegWriteE;
            MemWriteM   <= MemWriteE;
            MemReadM    <= MemReadE;
            ResultSrcM  <= ResultSrcE;
            AtomicM     <= AtomicE;
            AmoOpM      <= AmoOpE;
            FPRegWriteM <= FPRegWriteE;
            MemOpM      <= MemOpE;
            CSR_M       <= CSR_E;
            Fence_M     <= Fence_E;

            RD_M        <= RD_E;
            RD_F_M      <= RD_F_E;
            PCPlus4M    <= PCPlus4E;
            ALU_ResultM <= ALU_ResultE;
            WriteDataM  <= WriteDataE;
        end
        // stall -> hold
    end

endmodule