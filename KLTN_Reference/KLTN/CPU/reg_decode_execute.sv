module reg_decode_execute (
    input         mem_wrenD, mem_ldenD, op_a_selD, op_b_selD, rd_wrenD, br_selD, ex_res_selD,
    input  [1:0]  wb_selD, muldiv_opD, muldiv_modeD,
    input  [2:0]  ld_selD,
    input  [3:0]  byte_enD, alu_opD,
    input  [4:0]  rs1_addrD, rs2_addrD, rd_addrD, bridge_rd_addrD, wr_addr_tagD,
    input  [12:0] pcD, pc4D,
    input  [63:0] immD, rs1_dataD, rs2_dataD, bridge_rd_rf_dataD,
    input         bridge_rdenD, W_suffixD,

    input         clk, sclr, aclr,

    output logic        mem_wrenE, mem_ldenE, op_a_selE, op_b_selE, rd_wrenE, br_selE, ex_res_selE,
    output logic [1:0]  wb_selE, muldiv_opE, muldiv_modeE,
    output logic [2:0]  ld_selE,
    output logic [3:0]  byte_enE, alu_opE,
    output logic [4:0]  rs1_addrE, rs2_addrE, rd_addrE, bridge_rd_addrE, wr_addr_tagE,
    output logic [12:0] pcE, pc4E,
    output logic [63:0] immE, rs1_dataE, rs2_dataE, bridge_rd_rf_dataE,
    output logic        W_suffixE, bridge_rdenE
);
    timeunit 1ns; timeprecision 1ps;
    
    always_ff @ (posedge clk, negedge aclr)
    if (!aclr)     {wb_selE, ld_selE, mem_wrenE, byte_enE, alu_opE, op_b_selE, op_a_selE, rd_wrenE, br_selE, immE, rs1_dataE, rs2_dataE, rs1_addrE, rs2_addrE, rd_addrE, pcE, pc4E, W_suffixE, bridge_rdenE, bridge_rd_addrE, bridge_rd_rf_dataE, ex_res_selE, muldiv_opE, muldiv_modeE, wr_addr_tagE, mem_ldenE} = 'b0;
	else if (sclr) {wb_selE, ld_selE, mem_wrenE, byte_enE, alu_opE, op_b_selE, op_a_selE, rd_wrenE, br_selE, immE, rs1_dataE, rs2_dataE, rs1_addrE, rs2_addrE, rd_addrE, pcE, pc4E, W_suffixE, bridge_rdenE, bridge_rd_addrE, bridge_rd_rf_dataE, ex_res_selE, muldiv_opE, muldiv_modeE, wr_addr_tagE, mem_ldenE} = 'b0;
    else           {wb_selE, ld_selE, mem_wrenE, byte_enE, alu_opE, op_b_selE, op_a_selE, rd_wrenE, br_selE, immE, rs1_dataE, rs2_dataE, rs1_addrE, rs2_addrE, rd_addrE, pcE, pc4E, W_suffixE, bridge_rdenE, bridge_rd_addrE, bridge_rd_rf_dataE, ex_res_selE, muldiv_opE, muldiv_modeE, wr_addr_tagE, mem_ldenE} = {wb_selD, ld_selD, mem_wrenD, byte_enD, alu_opD, op_b_selD, op_a_selD, rd_wrenD, br_selD, immD, rs1_dataD, rs2_dataD, rs1_addrD, rs2_addrD, rd_addrD, pcD, pc4D, W_suffixD, bridge_rdenD, bridge_rd_addrD, bridge_rd_rf_dataD, ex_res_selD, muldiv_opD, muldiv_modeD, wr_addr_tagD, mem_ldenD};

endmodule