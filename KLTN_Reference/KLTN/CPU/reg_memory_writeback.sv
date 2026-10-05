module reg_memory_writeback (
    input         rd_wrenM,
    input  [1:0]  wb_selM,
    input  [4:0]  rd_addrM,
    input  [4:0]  wr_addr_tagM,
    input  [12:0] pc4M,
    input  [63:0] alu_dataM, ld_dataM,
    input         bridge_wrenM,
    input [4:0]   bridge_wr_addrM,
    input [63:0]  bridge_wr_dataM,

    input         clk, aclr,

    output logic        rd_wrenW,
    output logic [1:0]  wb_selW,
    output logic [4:0]  rd_addrW,
    output logic [4:0]  wr_addr_tagW,
    output logic [12:0] pc4W,
    output logic [63:0] alu_dataW, ld_dataW,
    output logic        bridge_wrenW,
    output logic [4:0]  bridge_wr_addrW,
    output logic [63:0] bridge_wr_dataW
);
    timeunit 1ns; timeprecision 1ps;
    
    always_ff @ (posedge clk, negedge aclr)
    if (!aclr) {wb_selW, rd_wrenW, alu_dataW, ld_dataW, rd_addrW, pc4W, wr_addr_tagW, bridge_wrenW, bridge_wr_addrW, bridge_wr_dataW} = 'b0;
    else       {wb_selW, rd_wrenW, alu_dataW, ld_dataW, rd_addrW, pc4W, wr_addr_tagW, bridge_wrenW, bridge_wr_addrW, bridge_wr_dataW} = {wb_selM, rd_wrenM, alu_dataM, ld_dataM, rd_addrM, pc4M, wr_addr_tagM, bridge_wrenM, bridge_wr_addrM, bridge_wr_dataM};

endmodule