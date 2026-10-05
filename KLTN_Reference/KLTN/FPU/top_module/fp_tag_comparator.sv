module fp_tag_comparator (
    input  logic [4:0] wr_addr_tag,
    input  logic [4:0] current_wr_addr_tag,
    output logic       wr_commit
);
    timeunit 1ns; timeprecision 1ps;

    assign wr_commit = (wr_addr_tag == current_wr_addr_tag) ? 1'b1 : 1'b0;

endmodule: fp_tag_comparator