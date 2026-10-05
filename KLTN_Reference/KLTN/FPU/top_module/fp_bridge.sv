module fp_bridge(
    input  logic         cpu_busy,

    input  logic         bridge_wren_i,
    input  logic [4:0]   bridge_wr_addr_i,
    input  logic [63:0]  bridge_wr_data_i,

    input  logic         bridge_rden_i,
    input  logic         bridge_rd_sel_i,
    input  logic [4:0]   bridge_rd_addr_i,
    input  logic [63:0]  bridge_rd_data_i,
    
    output logic         bridge_wren_o,
    output logic [4:0]   bridge_wr_addr_o,
    output logic [63:0]  bridge_wr_data_o,

    output logic         bridge_rden_o,
    output logic         bridge_rd_sel_o,
    output logic [4:0]   bridge_rd_addr_o,
    output logic [63:0]  bridge_rd_data_o
);
    timeunit 1ns; timeprecision 1ps;

    assign bridge_rden_o    = bridge_rden_i;
    assign bridge_rd_sel_o  = bridge_rd_sel_i;
    assign bridge_rd_addr_o = bridge_rd_addr_i;
    assign bridge_rd_data_o = (~cpu_busy) ? bridge_rd_data_i : 'z;
    assign bridge_wren_o    = bridge_wren_i;
    assign bridge_wr_addr_o = bridge_wr_addr_i;
    assign bridge_wr_data_o = bridge_wr_data_i;

endmodule: fp_bridge