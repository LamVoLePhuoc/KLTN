module fp_reg_issue_decode(
    input logic         clk,
    input logic         rst_n,
    input logic         en,
    input logic         sclr,

    input logic [31:0]  instr_i,
    input logic [4:0]   wr_addr_tag_i, 
    input logic         rs1_rf_sel_i,
    input logic         rs2_rf_sel_i,
    input logic         rs3_rf_sel_i,
    output logic [31:0] instr,
    output logic [4:0]  wr_addr_tag_D,
    output logic        rs1_rf_sel_d,
    output logic        rs2_rf_sel_d,
    output logic        rs3_rf_sel_d
);
    timeunit 1ns; timeprecision 1ps;
    
    logic [31:0] instr_temp;
    logic [4:0] wr_addr_tag_temp;
    logic rs1_rf_sel_temp;
    logic rs2_rf_sel_temp;
    logic rs3_rf_sel_temp;

    always_ff @(posedge clk, negedge rst_n) begin
        if (rst_n == 1'b0) begin
            instr_temp <= '0;
            wr_addr_tag_temp <= '0;
            rs1_rf_sel_temp <= '0;
            rs2_rf_sel_temp <= '0;
            rs3_rf_sel_temp <= '0;
        end
        else if (sclr == 1'b1) begin
            instr_temp <= '0;
            wr_addr_tag_temp <= '0;
            rs1_rf_sel_temp <= '0;
            rs3_rf_sel_temp <= '0;
            rs2_rf_sel_temp <= '0;
        end
        else if (en == 1'b0) begin
            instr_temp <= instr_i;
            wr_addr_tag_temp <= wr_addr_tag_i;
            rs1_rf_sel_temp <= rs1_rf_sel_i;
            rs2_rf_sel_temp <= rs2_rf_sel_i;
            rs3_rf_sel_temp <= rs3_rf_sel_i;
        end
        else begin
            instr_temp <= instr_temp;
            wr_addr_tag_temp <= wr_addr_tag_temp;
            rs1_rf_sel_temp <= rs1_rf_sel_temp;
            rs2_rf_sel_temp <= rs2_rf_sel_temp;
            rs3_rf_sel_temp <= rs3_rf_sel_temp;
        end
    end

    assign instr = instr_temp;
    assign wr_addr_tag_D = wr_addr_tag_temp;
    assign rs1_rf_sel_d = rs1_rf_sel_temp;
    assign rs2_rf_sel_d = rs2_rf_sel_temp;
    assign rs3_rf_sel_d = rs3_rf_sel_temp;

endmodule: fp_reg_issue_decode