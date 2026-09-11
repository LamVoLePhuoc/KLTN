`timescale 1ns / 1ps

module writeback_stage(
    input  wire [1:0]  ResultSrcW,
    input  wire [31:0] ALU_ResultW,
    input  wire [31:0] ReadDataW,
    input  wire [31:0] PCPlus4W,
    output reg  [31:0] ResultW
);

    always @(*) begin
        ResultW = 32'h00000000;

        case (ResultSrcW)
            2'b00: ResultW = ALU_ResultW; // ALU / integer
            2'b01: ResultW = ReadDataW;   // Load / LR / SC status
            2'b10: ResultW = PCPlus4W;    // JAL / JALR
            2'b11: ResultW = ALU_ResultW; // FPU result đã đi chung ALU_ResultW
            default: ResultW = 32'h00000000;
        endcase
    end

endmodule