module fp_reg_execute_mem(
    input logic         clk,
    input logic         rst_n,

    input logic         reg_write_e,
    input logic [4:0]   writeAddr_e,
    input logic         ld_sel_e,
    input logic         wb_sel_e,
    input logic         wren_e,
    input logic [63:0]  res_e,
    input logic [4:0]   flags_e,
    input logic         ready_e,
    input logic [63:0]  data2mem,
    input logic [63:0]  imm_e,
    input logic         bridge_wren_e,
    input logic [4:0]   wr_addr_tag_E,
    
    output logic         reg_write_m,
    output logic [4:0]   writeAddr_m,
    output logic         ld_sel_m,
    output logic         wb_sel_m,
    output logic         wren_m,
    output logic [63:0]  res_m,
    output logic [4:0]   flag_m,
    output logic         ready_m,
    output logic [63:0]  din,
    output logic [63:0]  addr,
    output logic         bridge_wren_m,
    output logic [4:0]   wr_addr_tag_M
);
    timeunit 1ns; timeprecision 1ps;

    logic [212:0] temp;
    
    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == 1'b0) begin
            temp <= '0;
        end
        else begin
            temp <= {reg_write_e, writeAddr_e, ld_sel_e, wb_sel_e, wren_e, res_e, flags_e, ready_e, data2mem, imm_e, bridge_wren_e, wr_addr_tag_E};
        end
    end

    assign {reg_write_m, writeAddr_m, ld_sel_m, wb_sel_m, wren_m, res_m, flag_m, ready_m, din, addr, bridge_wren_m, wr_addr_tag_M} = temp;

endmodule: fp_reg_execute_mem