`timescale 1ns/1ps
// from Lee Min Hunz with luv
module Extend(
    input       [2:0]   ImmSrc
,   input       [31:7]  Instr
,   output reg  [31:0]  ImmExt
);
    always@(*) begin
        case(ImmSrc)
            3'd0: ImmExt = {{20{Instr[31]}}, Instr[31:20]};                                 // I-type 12-bit signed immediate
            3'd1: ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};                    // S-type 12-bit signed immediate
            3'd2: ImmExt = {{20{Instr[31]}}, Instr[7], Instr[30:25], Instr[11:8], 1'b0};    // B-type 13-bit signed immediate
            3'd3: ImmExt = {{12{Instr[31]}}, Instr[19:12], Instr[20], Instr[30:21], 1'b0};  // J-type 21-bit signed immediate
            3'd4: ImmExt = {Instr[31:12], 12'b0};                                           // U-type
            3'd5: ImmExt = 32'd0;                                                           // A 0 to be added to rs1 for A operations
            default: ImmExt = 32'd0;
        endcase
    end
endmodule