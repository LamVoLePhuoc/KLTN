module arbiter (
    input  logic [31:0] instr_CPU_i,
    input  logic [31:0] instr_FPU_i,
    input  logic [4:0]  wr_addr_tag_CPU_i,
    input  logic [4:0]  wr_addr_tag_FPU_i,
    input  logic        rs1_rf_sel_CPU_i,
    input  logic        rs2_rf_sel_CPU_i,
    input  logic        rs1_rf_sel_FPU_i,
    input  logic        rs2_rf_sel_FPU_i,
    input  logic        rs3_rf_sel_FPU_i,

    output logic        hold_CPU,
    output logic        hold_FPU,

    output logic [31:0] instr_CPU_o,
    output logic [31:0] instr_FPU_o,
    output logic [4:0]  wr_addr_tag_CPU_o,
    output logic [4:0]  wr_addr_tag_FPU_o,
    output logic        rs1_rf_sel_CPU_o,
    output logic        rs2_rf_sel_CPU_o,
    output logic        rs1_rf_sel_FPU_o,
    output logic        rs2_rf_sel_FPU_o,
    output logic        rs3_rf_sel_FPU_o
);
    timeunit 1ns; timeprecision 1ps;

    always_comb begin
        // ================= Default =================
        hold_CPU = 1'b0;
        hold_FPU = 1'b0;
    
        instr_CPU_o         = instr_CPU_i;
        instr_FPU_o         = instr_FPU_i;
        wr_addr_tag_CPU_o   = wr_addr_tag_CPU_i;
        wr_addr_tag_FPU_o   = wr_addr_tag_FPU_i;
        rs1_rf_sel_CPU_o    = rs1_rf_sel_CPU_i;
        rs2_rf_sel_CPU_o    = rs2_rf_sel_CPU_i;
        rs1_rf_sel_FPU_o    = rs1_rf_sel_FPU_i;
        rs2_rf_sel_FPU_o    = rs2_rf_sel_FPU_i;
        rs3_rf_sel_FPU_o    = rs3_rf_sel_FPU_i;
    
        // ================= Check both instr valid =================
        if ((instr_CPU_i != 32'b0) && (instr_FPU_i != 32'b0)) begin
            if (wr_addr_tag_CPU_i < wr_addr_tag_FPU_i) begin
                // CPU wins, hold FPU
                hold_FPU          = 1'b1;
                instr_FPU_o       = 32'b0;
                wr_addr_tag_FPU_o = '0;
                rs1_rf_sel_FPU_o  = '0;
                rs2_rf_sel_FPU_o  = '0;
                rs3_rf_sel_FPU_o  = '0;
            end
            else begin
                // FPU wins, hold CPU
                hold_CPU          = 1'b1;
                instr_CPU_o       = 32'b0;
                wr_addr_tag_CPU_o = '0;
                rs1_rf_sel_CPU_o  = '0;
                rs2_rf_sel_CPU_o  = '0;
            end
        end
    end

endmodule: arbiter