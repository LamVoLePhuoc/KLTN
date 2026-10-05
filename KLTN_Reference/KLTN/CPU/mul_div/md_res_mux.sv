module md_res_mux (
    input res_sel,
    input [63:0] mul_res, div_res,
    output [63:0] res
);
    timeunit 1ns; timeprecision 1ps;

    assign res = (res_sel) ? div_res : mul_res;

endmodule