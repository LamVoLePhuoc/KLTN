module fp_sign_extend(
    input  logic [11:0] in,
    output logic [63:0] out
);
    timeunit 1ns; timeprecision 1ps;

    assign out = {{52{in[11]}}, in};
endmodule
