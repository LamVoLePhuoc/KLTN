`timescale 1ns/1ps
// from Lee Min Hunz with luv
module ALU #(
    parameter DATA_WIDTH = 32
)(
    input       [3:0]               ALUControl 
,   input       [DATA_WIDTH - 1:0]  in1
,   input       [DATA_WIDTH - 1:0]  in2
,   input       [DATA_WIDTH - 1:0]  PC
,   input       [DATA_WIDTH - 1:0]  E_ImmExt
,   input       [DATA_WIDTH - 1:0]  E_PCPlus4

,   output reg  [DATA_WIDTH - 1:0]  result
,   output reg                      zero
,   output                          signed_less
,   output                          unsigned_less
);
    wire [DATA_WIDTH - 1:0] sub = in1 - in2;

    // BLT, BGE, SLT
    // assign signed_less = $signed(in1) < $signed(in2);
    assign signed_less   = (in1[31] == in2[31]) ? sub[31] : in1[31];

    // BLTU, BGEU, SLTU
    // assign unsigned_less = $unsigned(in1) < $unsigned(in2);
    assign unsigned_less = (in1[31] == in2[31]) ? sub[31] : in2[31];

    wire [4:0] shamt        = in2[4:0];

    always @(*) begin
        case(ALUControl)
            4'b0000: result = in1 + in2;            // add
            4'b0001: result = in1 << shamt;         // sll
            4'b0010: result = in1 >> shamt;         // srl
            4'b0011: result = in1 >>> shamt;        // sra
            4'b0100: result = in1 & in2;            // and
            4'b0101: result = in1 | in2;            // or
            4'b0110: result = in1 ^ in2;            // xor
            4'b0111: result = E_ImmExt;             // lui
            4'b1000: result = sub;                  // sub
            4'b1001: result = {31'b0,signed_less};  // slt
            4'b1010: result = {31'b0,signed_less};  // sltu
            4'b1011: result = PC + E_ImmExt;        // auipc
            4'b1100: result = E_PCPlus4;            // jal / jalr
            default: result = 32'b0;                // Mac dinh la 0
        endcase
        zero = (result == 32'b0);
    end
endmodule
