module dispatch #(parameter NO_RESERV = 5) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] instr_f,
    input  logic        stall_f,

    input  logic        bridge_CPU_reg_write,
    input  logic        bridge_FPU_reg_write,
    input  logic [4:0]  bridge_reg_addr,
    input  logic [4:0]  bridge_reg_ROB,

    input  logic        reg_write_CPU,
    input  logic [4:0]  reg_addr_CPU,
    input  logic [4:0]  reg_ROB_CPU,

    input  logic [4:0]  rd_addrW_CPU,
    output logic [4:0]  current_wr_addr_tag_CPU,
    input  logic [4:0]  rd_addrW_FPU,
    output logic [4:0]  current_wr_addr_tag_FPU,

    output logic [31:0] instr_CPU,
    output logic [31:0] instr_FPU,
    output logic [4:0]  wr_addr_tag_CPU,
    output logic [4:0]  wr_addr_tag_FPU,
    output logic        rs1_rf_sel_CPU,
    output logic        rs2_rf_sel_CPU,
    output logic        rs1_rf_sel_FPU,
    output logic        rs2_rf_sel_FPU,
    output logic        rs3_rf_sel_FPU,
    output wor          stall
);
    timeunit 1ns; timeprecision 1ps;

    logic        CPU_reserv_en;
    logic        FPU_reserv_en;
    logic [31:0] instr_CDB;
    logic [4:0]  rd_addr_CDB;
    logic        rd_exist_CPU_CDB;
    logic        rd_exist_FPU_CDB;
    logic        rd_long_cmd_CDB;
    logic [4:0]  rs1_addr_CDB;
    logic [4:0]  rs1_tag_CDB;
    logic        rs1_exist_CPU_CDB;
    logic        rs1_exist_FPU_CDB;
    logic        rs1_busy_CDB;
    logic [4:0]  rs2_addr_CDB;
    logic [4:0]  rs2_tag_CDB;
    logic        rs2_exist_CDB;
    logic        rs2_busy_CDB;
    logic [4:0]  rs3_addr_CDB;
    logic [4:0]  rs3_tag_CDB;
    logic        rs3_exist_CDB;
    logic        rs3_busy_CDB;
    
    logic        rs1_busy_CPU_CDB;
    logic        rs1_busy_FPU_CDB;
    logic        rs2_busy_CPU_CDB;
    logic        rs2_busy_FPU_CDB;
    logic        rs3_busy_CPU_CDB;
    logic        rs3_busy_FPU_CDB;
    logic [4:0]  rs1_tag_CPU_CDB;
    logic [4:0]  rs1_tag_FPU_CDB;
    logic [4:0]  rs2_tag_CPU_CDB;
    logic [4:0]  rs2_tag_FPU_CDB;
    logic [4:0]  rs3_tag_CPU_CDB;
    logic [4:0]  rs3_tag_FPU_CDB;
    logic        CPU2FPU_CDB;
    logic        FPU2CPU_CDB;

    logic        backdoor_busy_CPU2FPU;
    logic        backdoor_long_cmd_CPU2FPU;
    logic        backdoor_busy_FPU2CPU;
    logic        backdoor_long_cmd_FPU2CPU;

    logic        all_busy_CPU;
    logic        all_busy_FPU;

    logic [4:0]  ROB_tag;
    logic [4:0]  rs1_tag_to_cmp_CPU;
    logic [4:0]  current_rs1_tag_to_cmp_CPU;
    logic [4:0]  rs1_addr_to_cmp_CPU;
    logic [4:0]  rs2_tag_to_cmp_CPU;
    logic [4:0]  current_rs2_tag_to_cmp_CPU;
    logic [4:0]  rs2_addr_to_cmp_CPU;
    
    logic        rs1_exist_to_cmp_FPU;
    logic [4:0]  rs1_tag_to_cmp_FPU;
    logic [4:0]  current_rs1_tag_to_cmp_FPU;
    logic [4:0]  current_rs1_tag_to_cmp;
    logic [4:0]  rs1_addr_to_cmp_FPU;
    logic [4:0]  rs2_tag_to_cmp_FPU;
    logic [4:0]  current_rs2_tag_to_cmp_FPU;
    logic [4:0]  rs2_addr_to_cmp_FPU;
    logic [4:0]  rs3_tag_to_cmp_FPU;
    logic [4:0]  current_rs3_tag_to_cmp_FPU;
    logic [4:0]  rs3_addr_to_cmp_FPU;

    logic [31:0] instr_CPU_to_arb;
    logic [31:0] instr_FPU_to_arb;
    logic [4:0]  wr_addr_tag_CPU_to_arb;
    logic [4:0]  wr_addr_tag_FPU_to_arb;
    logic        rs1_rf_sel_CPU_to_arb;
    logic        rs2_rf_sel_CPU_to_arb;
    logic        rs1_rf_sel_FPU_to_arb;
    logic        rs2_rf_sel_FPU_to_arb;
    logic        rs3_rf_sel_FPU_to_arb;
    logic        hold_CPU;
    logic        hold_FPU;

    assign stall = all_busy_CPU;
    assign stall = all_busy_FPU;

    pre_decoder pre_decoder (
        .instr_f(instr_f),
        .CPU_reserv_busy(CPU_reserv_en),
        .FPU_reserv_busy(FPU_reserv_en),
        .instr_o(instr_CDB),
        .rd_addr_o(rd_addr_CDB),
        .rd_long_cmd_o(rd_long_cmd_CDB),
        .rd_exist_CPU_o(rd_exist_CPU_CDB),
        .rd_exist_FPU_o(rd_exist_FPU_CDB),
        .rs1_addr_o(rs1_addr_CDB),
        .rs1_exist_CPU_o(rs1_exist_CPU_CDB),
        .rs1_exist_FPU_o(rs1_exist_FPU_CDB),
        .rs2_addr_o(rs2_addr_CDB),
        .rs2_exist_o(rs2_exist_CDB),
        .rs3_addr_o(rs3_addr_CDB),
        .rs3_exist_o(rs3_exist_CDB),
        .CPU2FPU_o(CPU2FPU_CDB),
        .FPU2CPU_o(FPU2CPU_CDB)
    );

    ROB_counter ROB_counter (
        .clk(clk),
        .rst_n(rst_n),
        .stall(stall_f),
        .opcode(instr_f[6:0]),
        .ROB(ROB_tag)
    );

    CPU_reg_manager CPU_reg_manager (
        .clk(clk),
        .rst_n(rst_n),
        .CPU2FPU(CPU2FPU_CDB),
        .FPU2CPU(FPU2CPU_CDB),
        .rd_en(rd_exist_CPU_CDB),
        .rd_long_cmd(rd_long_cmd_CDB),
        .rd_addr(rd_addr_CDB),
        .rd_ROB_tag(ROB_tag),
        .rs1_addr(rs1_addr_CDB),
        .rs2_addr(rs2_addr_CDB),
        .rs3_addr(rs3_addr_CDB),
        .rs1_exist(rs1_exist_CPU_CDB),
        .rs2_exist(rs2_exist_CDB),
        .rs3_exist(rs3_exist_CDB),
        .rd_clr(reg_write_CPU),
        .rd_addr_clr(reg_addr_CPU),
        .rd_ROB_clr(reg_ROB_CPU),
        .rd_clr_FPU(bridge_CPU_reg_write),
        .rd_addr_clr_FPU(bridge_reg_addr),
        .rd_ROB_clr_FPU(bridge_reg_ROB),
        .backdoor_busy_i(backdoor_busy_CPU2FPU),
        .backdoor_long_cmd_i(backdoor_long_cmd_CPU2FPU),
        .backdoor_busy_o(backdoor_busy_FPU2CPU),
        .backdoor_long_cmd_o(backdoor_long_cmd_FPU2CPU),
        .rd_addrW_CPU(rd_addrW_CPU),
        .current_wr_addr_tag_CPU(current_wr_addr_tag_CPU),
        .rs1_addr2cmp(rs1_addr_to_cmp_CPU),
        .rs1_addr2cmp_FPU(rs1_addr_to_cmp_FPU),
        .rs2_addr2cmp(rs2_addr_to_cmp_CPU),
        .rs1_tag2cmp(current_rs1_tag_to_cmp_CPU),
        .rs1_tag2cmp_FPU(current_rs1_tag_to_cmp),
        .rs2_tag2cmp(current_rs2_tag_to_cmp_CPU),
        .rs1_busy(rs1_busy_CPU_CDB),
        .rs2_busy(rs2_busy_CPU_CDB),
        .rs3_busy(rs3_busy_CPU_CDB),
        .rs1_tag(rs1_tag_CPU_CDB),
        .rs2_tag(rs2_tag_CPU_CDB),
        .rs3_tag(rs3_tag_CPU_CDB)
    );

    FPU_reg_manager FPU_reg_manager (
        .clk(clk),
        .rst_n(rst_n),
        .CPU2FPU(CPU2FPU_CDB),
        .FPU2CPU(FPU2CPU_CDB),
        .rd_en(rd_exist_FPU_CDB),
        .rd_long_cmd(rd_long_cmd_CDB),
        .rd_addr(rd_addr_CDB),
        .rd_ROB_tag(ROB_tag),
        .rs1_addr(rs1_addr_CDB),
        .rs2_addr(rs2_addr_CDB),
        .rs3_addr(rs3_addr_CDB),
        .rs1_exist(rs1_exist_FPU_CDB),
        .rs2_exist(rs2_exist_CDB),
        .rs3_exist(rs3_exist_CDB),
        .rd_clr(bridge_FPU_reg_write),
        .rd_addr_clr(bridge_reg_addr),
        .rd_ROB_clr(bridge_reg_ROB),
        .backdoor_busy_i(backdoor_busy_FPU2CPU),
        .backdoor_long_cmd_i(backdoor_long_cmd_FPU2CPU),
        .backdoor_busy_o(backdoor_busy_CPU2FPU),
        .backdoor_long_cmd_o(backdoor_long_cmd_CPU2FPU),
        .rd_addrW(rd_addrW_FPU),
        .current_wr_addr_tag(current_wr_addr_tag_FPU),
        .rs1_addr2cmp(rs1_addr_to_cmp_FPU),
        .rs2_addr2cmp(rs2_addr_to_cmp_FPU),
        .rs3_addr2cmp(rs3_addr_to_cmp_FPU),
        .rs1_tag2cmp(current_rs1_tag_to_cmp_FPU),
        .rs2_tag2cmp(current_rs2_tag_to_cmp_FPU),
        .rs3_tag2cmp(current_rs3_tag_to_cmp_FPU),
        .rs1_busy(rs1_busy_FPU_CDB),
        .rs2_busy(rs2_busy_FPU_CDB),
        .rs3_busy(rs3_busy_FPU_CDB),
        .rs1_tag(rs1_tag_FPU_CDB),
        .rs2_tag(rs2_tag_FPU_CDB),
        .rs3_tag(rs3_tag_FPU_CDB)
    );

    assign rs1_busy_CDB = (rs1_exist_FPU_CDB == 1'b1) ? rs1_busy_FPU_CDB : ((rs1_exist_CPU_CDB == 1'b1) ? rs1_busy_CPU_CDB : 1'b0);
    assign rs2_busy_CDB = (FPU_reserv_en == 1'b1) ? rs2_busy_FPU_CDB : rs2_busy_CPU_CDB;
    assign rs3_busy_CDB = (FPU_reserv_en == 1'b1) ? rs3_busy_FPU_CDB : rs3_busy_CPU_CDB;
    assign rs1_tag_CDB  = (rs1_exist_FPU_CDB == 1'b1) ? rs1_tag_FPU_CDB : ((rs1_exist_CPU_CDB == 1'b1) ? rs1_tag_CPU_CDB : 1'b0);
    assign rs2_tag_CDB  = (FPU_reserv_en == 1'b1) ? rs2_tag_FPU_CDB : rs2_tag_CPU_CDB;
    assign rs3_tag_CDB  = (FPU_reserv_en == 1'b1) ? rs3_tag_FPU_CDB : rs3_tag_CPU_CDB;

    CPU_reservation_station #(.NO_RESERV(NO_RESERV)) CPU_reservation_station (
        .clk(clk),
        .rst_n(rst_n),
        .en(CPU_reserv_en),
        .stall(stall_f),
        .hold(hold_CPU),
        .instr_i(instr_CDB),
        .rd_addr_i(rd_addr_CDB),
        .rd_exist_i(rd_exist_CPU_CDB),
        .rd_ROB_tag_i(ROB_tag),
        .rs1_addr_i(rs1_addr_CDB),
        .rs1_tag_i(rs1_tag_CDB),
        .rs1_exist_i(rs1_exist_CPU_CDB),
        .rs1_busy_i(rs1_busy_CDB),
        .rs2_addr_i(rs2_addr_CDB),
        .rs2_tag_i(rs2_tag_CDB),
        .rs2_exist_i(rs2_exist_CDB),
        .rs2_busy_i(rs2_busy_CDB),
        .rd_addr_clr(reg_addr_CPU),
        .rd_ROB_clr(reg_ROB_CPU),
        .rd_clr(reg_write_CPU),
        .rd_addr_FPU_clr(bridge_reg_addr),
        .rd_ROB_FPU_clr(bridge_reg_ROB),
        .rd_FPU_clr(bridge_CPU_reg_write),
        .instr_o(instr_CPU_to_arb),
        .wr_addr_tag_o(wr_addr_tag_CPU_to_arb),
        .rs1_tag_o(rs1_tag_to_cmp_CPU),
        .rs1_addr_o(rs1_addr_to_cmp_CPU),
        .rs2_tag_o(rs2_tag_to_cmp_CPU),
        .rs2_addr_o(rs2_addr_to_cmp_CPU),
        .all_busy(all_busy_CPU)
    );

    CPU_rs_tag_comparator CPU_rs_tag_cmp (
        .rs1_tag(rs1_tag_to_cmp_CPU),
        .rs2_tag(rs2_tag_to_cmp_CPU),
        .current_rs1_tag(current_rs1_tag_to_cmp_CPU),
        .current_rs2_tag(current_rs2_tag_to_cmp_CPU),
        .rs1_rf_sel(rs1_rf_sel_CPU_to_arb),
        .rs2_rf_sel(rs2_rf_sel_CPU_to_arb)
    );

    FPU_reservation_station #(.NO_RESERV(NO_RESERV)) FPU_reservation_station (
        .clk(clk),
        .rst_n(rst_n),
        .en(FPU_reserv_en),
        .stall(stall_f),
        .hold(hold_FPU),
        .instr_i(instr_CDB),
        .rd_addr_i(rd_addr_CDB),
        .rd_exist_i(rd_exist_FPU_CDB),
        .rd_ROB_tag_i(ROB_tag),
        .rs1_addr_i(rs1_addr_CDB),
        .rs1_tag_i(rs1_tag_CDB),
        .rs1_exist_i(rs1_exist_FPU_CDB),
        .rs1_busy_i(rs1_busy_CDB),
        .rs2_addr_i(rs2_addr_CDB),
        .rs2_tag_i(rs2_tag_CDB),
        .rs2_exist_i(rs2_exist_CDB),
        .rs2_busy_i(rs2_busy_CDB),
        .rs3_addr_i(rs3_addr_CDB),
        .rs3_tag_i(rs3_tag_CDB),
        .rs3_exist_i(rs3_exist_CDB),
        .rs3_busy_i(rs3_busy_CDB),
        .rd_addr_clr(bridge_reg_addr),
        .rd_ROB_clr(bridge_reg_ROB),
        .rd_clr(bridge_FPU_reg_write | bridge_CPU_reg_write),
        .rd_addr_CPU_clr(reg_addr_CPU),
        .rd_ROB_CPU_clr(reg_ROB_CPU),
        .rd_CPU_clr(reg_write_CPU),
        .instr_o(instr_FPU_to_arb),
        .wr_addr_tag_o(wr_addr_tag_FPU_to_arb),
        .rs1_tag_o(rs1_tag_to_cmp_FPU),
        .rs1_addr_o(rs1_addr_to_cmp_FPU),
        .rs1_exist_o(rs1_exist_to_cmp_FPU),
        .rs2_tag_o(rs2_tag_to_cmp_FPU),
        .rs2_addr_o(rs2_addr_to_cmp_FPU),
        .rs3_tag_o(rs3_tag_to_cmp_FPU),
        .rs3_addr_o(rs3_addr_to_cmp_FPU),
        .all_busy(all_busy_FPU)
    );

    FPU_rs_tag_comparator FPU_rs_tag_cmp (
        .rs1_tag(rs1_tag_to_cmp_FPU),
        .rs2_tag(rs2_tag_to_cmp_FPU),
        .rs3_tag(rs3_tag_to_cmp_FPU),
        .current_rs1_tag((rs1_exist_to_cmp_FPU) ? current_rs1_tag_to_cmp_FPU : current_rs1_tag_to_cmp),
        .current_rs2_tag(current_rs2_tag_to_cmp_FPU),
        .current_rs3_tag(current_rs3_tag_to_cmp_FPU),
        .rs1_rf_sel(rs1_rf_sel_FPU_to_arb),
        .rs2_rf_sel(rs2_rf_sel_FPU_to_arb),
        .rs3_rf_sel(rs3_rf_sel_FPU_to_arb)
    );

    arbiter arbiter (
        .instr_CPU_i(instr_CPU_to_arb),
        .instr_FPU_i(instr_FPU_to_arb),
        .wr_addr_tag_CPU_i(wr_addr_tag_CPU_to_arb),
        .wr_addr_tag_FPU_i(wr_addr_tag_FPU_to_arb),
        .rs1_rf_sel_CPU_i(rs1_rf_sel_CPU_to_arb),
        .rs2_rf_sel_CPU_i(rs2_rf_sel_CPU_to_arb),
        .rs1_rf_sel_FPU_i(rs1_rf_sel_FPU_to_arb),
        .rs2_rf_sel_FPU_i(rs2_rf_sel_FPU_to_arb),
        .rs3_rf_sel_FPU_i(rs3_rf_sel_FPU_to_arb),
        .hold_CPU(hold_CPU),
        .hold_FPU(hold_FPU),
        .instr_CPU_o(instr_CPU),
        .instr_FPU_o(instr_FPU),
        .wr_addr_tag_CPU_o(wr_addr_tag_CPU),
        .wr_addr_tag_FPU_o(wr_addr_tag_FPU),
        .rs1_rf_sel_CPU_o(rs1_rf_sel_CPU),
        .rs2_rf_sel_CPU_o(rs2_rf_sel_CPU),
        .rs1_rf_sel_FPU_o(rs1_rf_sel_FPU),
        .rs2_rf_sel_FPU_o(rs2_rf_sel_FPU),
        .rs3_rf_sel_FPU_o(rs3_rf_sel_FPU)
    );

endmodule: dispatch