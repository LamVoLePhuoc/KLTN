module fp_reg_decode_execute(
    input logic         clk,
    input logic         rst_n,
    input logic         sclr,

    input logic [19:0]  fp_opcode,
    input logic         en,
    input logic         fmt_sel,
    input logic         rm_sel,
    input logic         wb_sel,
    input logic         wren,
    input logic [4:0]   writeAddr,
    input logic [2:0]   rm,
    input logic [1:0]   fmtLS,
    input logic [1:0]   fmt,
    input logic [63:0]  rdData1,
    input logic [63:0]  rdData2,
    input logic [63:0]  rdData3,
    input logic [2:0]   dyn_rm,
    input logic [63:0]  imm,
    input logic [4:0]   rdAddr1,
    input logic [4:0]   rdAddr2,
    input logic [4:0]   rdAddr3,
    input logic         bridge_rden,

    output logic [19:0]  fp_opcode_d,
    output logic         en_d,
    output logic         fmt_sel_d,
    output logic         rm_sel_d,
    output logic         wb_sel_d,
    output logic         wren_d,
    output logic [4:0]   writeAddr_d,
    output logic [2:0]   rm_d,
    output logic [1:0]   fmtLS_d,
    output logic [1:0]   fmt_d,
    output logic [63:0]  rdData1_d,
    output logic [63:0]  rdData2_d,
    output logic [63:0]  rdData3_d,
    output logic [2:0]   dyn_rm_d,
    output logic [63:0]  imm_d,
    output logic [4:0]   rdAddr1_d,
    output logic [4:0]   rdAddr2_d,
    output logic [4:0]   rdAddr3_d,
    output logic         bridge_rden_d
);
    timeunit 1ns; timeprecision 1ps;

    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == 1'b0) begin
            {fp_opcode_d, en_d, fmt_sel_d, rm_sel_d, wb_sel_d, wren_d, writeAddr_d, rm_d, fmtLS_d, fmt_d, rdData1_d, rdData2_d, rdData3_d, dyn_rm_d, imm_d, rdAddr1_d, rdAddr2_d, rdAddr3_d, bridge_rden_d} <= '0;
        end
        else if (sclr == 1'b1) begin
            {fp_opcode_d, en_d, fmt_sel_d, rm_sel_d, wb_sel_d, wren_d, writeAddr_d, rm_d, fmtLS_d, fmt_d, rdData1_d, rdData2_d, rdData3_d, dyn_rm_d, imm_d, rdAddr1_d, rdAddr2_d, rdAddr3_d, bridge_rden_d} <= '0;
        end
        else begin
            {fp_opcode_d, en_d, fmt_sel_d, rm_sel_d, wb_sel_d, wren_d, writeAddr_d, rm_d, fmtLS_d, fmt_d, rdData1_d, rdData2_d, rdData3_d, dyn_rm_d, imm_d, rdAddr1_d, rdAddr2_d, rdAddr3_d, bridge_rden_d} <= {fp_opcode, en, fmt_sel, rm_sel, wb_sel, wren, writeAddr, rm, fmtLS, fmt, rdData1, rdData2, rdData3, dyn_rm, imm, rdAddr1, rdAddr2, rdAddr3, bridge_rden};
        end
    end

endmodule: fp_reg_decode_execute