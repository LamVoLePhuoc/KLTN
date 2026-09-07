`timescale 1ns / 1ps

module mem_wb_registers(
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    input  wire        RegWriteM,
    input  wire        FPRegWriteM,
    input  wire [1:0]  ResultSrcM,
    input  wire [4:0]  RD_M,
    input  wire [4:0]  RD_F_M,
    input  wire [31:0] PCPlus4M,
    input  wire [31:0] ALU_ResultM,
    input  wire [31:0] ReadDataM,

    output reg         RegWriteW,
    output reg         FPRegWriteW,
    output reg  [1:0]  ResultSrcW,
    output reg  [4:0]  RD_W,
    output reg  [4:0]  RD_F_W,
    output reg  [31:0] PCPlus4W,
    output reg  [31:0] ALU_ResultW,
    output reg  [31:0] ReadDataW
);

    always @(posedge clk) begin
        if (rst) begin
            RegWriteW   <= 1'b0;
            FPRegWriteW <= 1'b0;
            ResultSrcW  <= 2'b00;
            RD_W        <= 5'b00000;
            RD_F_W      <= 5'b00000;
            PCPlus4W    <= 32'b0;
            ALU_ResultW <= 32'b0;
            ReadDataW   <= 32'b0;
        end
        else if (flush) begin
            RegWriteW   <= 1'b0;
            FPRegWriteW <= 1'b0;
            ResultSrcW  <= 2'b00;
            RD_W        <= 5'b00000;
            RD_F_W      <= 5'b00000;
            PCPlus4W    <= 32'b0;
            ALU_ResultW <= 32'b0;
            ReadDataW   <= 32'b0;
        end
        else if (!stall) begin
            RegWriteW   <= RegWriteM;
            FPRegWriteW <= FPRegWriteM;
            ResultSrcW  <= ResultSrcM;
            RD_W        <= RD_M;
            RD_F_W      <= RD_F_M;
            PCPlus4W    <= PCPlus4M;
            ALU_ResultW <= ALU_ResultM;
            ReadDataW   <= ReadDataM;
        end
    end

endmodule