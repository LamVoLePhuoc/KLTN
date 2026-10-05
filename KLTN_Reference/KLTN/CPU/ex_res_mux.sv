module ex_res_mux (
    input ex_res_sel,
    input [63:0] alu_res, muldiv_res,
    output [63:0] ex_res
);
    timeunit 1ns; timeprecision 1ps;

    assign ex_res = (ex_res_sel) ? muldiv_res : alu_res;

endmodule