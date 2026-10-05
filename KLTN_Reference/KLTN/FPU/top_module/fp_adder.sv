module fp_adder(
    input  logic [63:0] a,
    input  logic [63:0] b,
    output logic [63:0] sum
);
    timeunit 1ns; timeprecision 1ps;

    assign sum = a + b;
endmodule
