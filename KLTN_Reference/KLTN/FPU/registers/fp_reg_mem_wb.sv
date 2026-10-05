module fp_reg_mem_wb(
    input logic         clk,
    input logic         rst_n,

    input logic         reg_write_w,
    input logic [4:0]   writeAddr_w,
    input logic         wb_sel_w,
    input logic [63:0]  res_w,
    input logic [4:0]   flag_w,
    input logic         ready_w,
    input logic [63:0]  mem2lsu,
    input logic [4:0]   wr_addr_tag_M,
    input logic         bridge_wren_m,

    output logic         reg_write_o,
    output logic [4:0]   writeAddr_o,
    output logic         wb_sel_o,
    output logic [63:0]  res_o,
    output logic [4:0]   flag_o,
    output logic         ready_o,
    output logic [63:0]  data2rf,
    output logic [4:0]   wr_addr_tag_W,
    output logic         bridge_wren_w
);
    timeunit 1ns; timeprecision 1ps;

    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == 1'b0) begin
            {reg_write_o, writeAddr_o, wb_sel_o, res_o, flag_o, ready_o, data2rf, wr_addr_tag_W, bridge_wren_w} <= '0;
        end
        else begin
            {reg_write_o, writeAddr_o, wb_sel_o, res_o, flag_o, ready_o, data2rf, wr_addr_tag_W, bridge_wren_w} <= {reg_write_w, writeAddr_w, wb_sel_w, res_w, flag_w, ready_w, mem2lsu, wr_addr_tag_M, bridge_wren_m};
        end
    end
endmodule: fp_reg_mem_wb