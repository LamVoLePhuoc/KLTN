`timescale 1ns/1ps
// from Lee Min Hunz with luv
module mux2_1 #(
    parameter WIDTH = 32
)(
    input   [WIDTH - 1:0] in0, in1 
,   input   sel
,   output  [WIDTH - 1:0] res
);
    assign res = (sel == 1'b1) ? in1 : in0;
endmodule
