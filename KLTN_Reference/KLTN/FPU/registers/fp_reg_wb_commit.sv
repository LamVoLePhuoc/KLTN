module fp_reg_wb_commit(
    input  logic         clk,
    input  logic         rst_n,

    input  logic         reg_write_w,
    input  logic [4:0]   writeAddr_w,
    input  logic         wr_commit_w,
    input  logic         bridge_wren_w,
    input  logic [63:0]  writeData_w,

    output logic         reg_write_c,
    output logic [4:0]   writeAddr_c,
    output logic         wr_commit_c,
    output logic         bridge_wren_c,
    output logic [63:0]  writeData_c
);
    timeunit 1ns; timeprecision 1ps;

    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == 1'b0) begin
            {reg_write_c, writeAddr_c, wr_commit_c, bridge_wren_c, writeData_c} <= '0;
        end
        else begin
            {reg_write_c, writeAddr_c, wr_commit_c, bridge_wren_c, writeData_c} <= {reg_write_w, writeAddr_w, wr_commit_w, bridge_wren_w, writeData_w};
        end
    end
endmodule: fp_reg_wb_commit