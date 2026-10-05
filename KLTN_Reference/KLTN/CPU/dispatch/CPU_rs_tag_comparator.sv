module CPU_rs_tag_comparator (
    input  logic [4:0] rs1_tag, rs2_tag,
    input  logic [4:0] current_rs1_tag, current_rs2_tag,
    output logic       rs1_rf_sel, rs2_rf_sel
);
    timeunit 1ns; timeprecision 1ps;

    assign rs1_rf_sel = (rs1_tag != current_rs1_tag) ? 1'b1 : 1'b0;     // 1: temp regfile, 0: main regfile
    assign rs2_rf_sel = (rs2_tag != current_rs2_tag) ? 1'b1 : 1'b0;     // 1: temp regfile, 0: main regfile

endmodule: CPU_rs_tag_comparator