module reg_execute_memory (
    input         mem_wrenE, rd_wrenE, mem_ldenE,
    input  [1:0]  wb_selE,
    input  [2:0]  ld_selE,
    input  [3:0]  byte_enE,
    input  [4:0]  rd_addrE,
    input  [4:0]  wr_addr_tagE,
    input  [12:0] pc4E,
    input  [63:0] alu_dataE, forward2outE,

    input         clk, aclr,

    output logic        mem_wrenM, rd_wrenM, mem_ldenM,
    output logic [1:0]  wb_selM,
    output logic [2:0]  ld_selM,
    output logic [3:0]  byte_enM,
    output logic [4:0]  rd_addrM,
    output logic [4:0]  wr_addr_tagM,
    output logic [12:0] pc4M,
    output logic [63:0] alu_dataM, forward2outM
);
    timeunit 1ns; timeprecision 1ps;
    
    always_ff @ (posedge clk, negedge aclr)
    if (!aclr) {wb_selM, ld_selM, mem_wrenM, byte_enM, rd_wrenM, alu_dataM, forward2outM, rd_addrM, pc4M, wr_addr_tagM, mem_ldenM} = 'b0;
    else       {wb_selM, ld_selM, mem_wrenM, byte_enM, rd_wrenM, alu_dataM, forward2outM, rd_addrM, pc4M, wr_addr_tagM, mem_ldenM} = {wb_selE, ld_selE, mem_wrenE, byte_enE, rd_wrenE, alu_dataE, forward2outE, rd_addrE, pc4E, wr_addr_tagE, mem_ldenE};

endmodule