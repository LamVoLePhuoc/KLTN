`timescale 1ns / 1ps

module if_id_registers #(
    parameter [31:0] RESET_VECTOR = 32'h0000_0000
)(
    input         clk,
    input         rst,
    input         stall,
    input         flush,
    input  [31:0] InstrF,
    input  [31:0] PCF,
    input  [31:0] PCPlus4F,
    input         FetchPageFaultF,   // NEW: see RV32IMA.v -- pulses the same cycle
                                       // mmu_core_wrapper forces InstrF to a NOP, i.e.
                                       // exactly when the NOP that's about to land in
                                       // InstrD needs to be tagged "this was a faulting
                                       // fetch" for csr_trap_unit.v downstream. Captured
                                       // with the identical stall/flush timing as InstrD
                                       // on purpose -- it must move through the pipeline
                                       // in lockstep with the instruction slot it tags.
    output reg [31:0] InstrD,
    output reg [31:0] PCD,
    output reg [31:0] PCPlus4D,
    output reg        FetchPageFaultD
);

    localparam NOP_INSTRUCTION = 32'h00000013;

    always @(posedge clk) begin
        if (rst) begin
            InstrD          <= NOP_INSTRUCTION;
            PCD             <= RESET_VECTOR;
            PCPlus4D        <= RESET_VECTOR + 32'h4;
            FetchPageFaultD <= 1'b0;
        end
        else if (flush) begin
            InstrD          <= NOP_INSTRUCTION;
            PCD             <= 32'h0;
            PCPlus4D        <= 32'h0;
            FetchPageFaultD <= 1'b0;
        end
        else if (!stall) begin
            InstrD          <= InstrF;
            PCD             <= PCF;
            PCPlus4D        <= PCPlus4F;
            FetchPageFaultD <= FetchPageFaultF;
        end
    end

endmodule