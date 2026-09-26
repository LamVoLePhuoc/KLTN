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
    input  wire [2:0]  MemOpE,
    input  wire        CSR_E,
    input  wire        Fence_E,

    // --- NEW: see id_ex_registers.v (ExcFlagsD/InstrD) for how
    // these two reached E; CsrWDataE is different -- computed fresh
    // inside execute_stage.v (forwarded rs1 vs. zero-extended uimm,
    // see that file), not threaded from D at all ---
    input  wire [7:0]  ExcFlagsE,
    input  wire [31:0] InstrE,
    input  wire [31:0] CsrWDataE,

    // --- Data Signals from Execute (E) ---
    input  wire [4:0]  RD_E,
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
    output reg  [2:0]  MemOpM,
    output reg         CSR_M,
    output reg         Fence_M,

    output reg  [7:0]  ExcFlagsM,
    output reg  [31:0] InstrM,
    output reg  [31:0] CsrWDataM,

    output reg  [4:0]  RD_M,
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
            MemOpM      <= 3'b000;
            CSR_M       <= 1'b0;
            Fence_M     <= 1'b0;
            ExcFlagsM   <= 8'b0;
            InstrM      <= 32'h00000013;
            CsrWDataM   <= 32'b0;

            RD_M        <= 5'b00000;
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
            MemOpM      <= 3'b000;
            CSR_M       <= 1'b0;
            Fence_M     <= 1'b0;
            ExcFlagsM   <= 8'b0;
            InstrM      <= 32'h00000013;
            CsrWDataM   <= 32'b0;

            RD_M        <= 5'b00000;
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
            MemOpM      <= MemOpE;
            CSR_M       <= CSR_E;
            Fence_M     <= Fence_E;
            ExcFlagsM   <= ExcFlagsE;
            InstrM      <= InstrE;
            CsrWDataM   <= CsrWDataE;

            RD_M        <= RD_E;
            PCPlus4M    <= PCPlus4E;
            ALU_ResultM <= ALU_ResultE;
            WriteDataM  <= WriteDataE;
        end
        // stall -> hold
    end

endmodule