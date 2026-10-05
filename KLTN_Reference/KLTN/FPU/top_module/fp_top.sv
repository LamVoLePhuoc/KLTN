import fp_wire::*;
module fp_top #(
  parameter DataWidth  = 64,	
  parameter NumRegs    = 32,	
  parameter IndexWidth = 5  	
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] instr_i,
    input  logic [4:0]  bridge_fpu_wr_addr_tag_i,
    output logic        stall_i,

    // ====== Memory access ======
    output logic        mem_ld_sel,
    output logic        mem_wren,
    output logic [11:0] mem_addr,
    output logic [63:0] mem_din,
    input  logic [63:0] mem_dout,
    // ===========================

    // ===== Bridge from CPU =====
    // ---- Address/Data bus ----
    input  logic [63:0] bridge_rd_data_i,
    output logic        bridge_wren_o,
    output logic [4:0]  bridge_wr_addr_o,
    output logic [4:0]  bridge_wr_addr_tag_o,
    output logic [63:0] bridge_wr_data_o,

    output logic        bridge_rden_o,
    output logic        bridge_rd_sel_o,
    output logic [4:0]  bridge_rd_addr_o,

    output logic        bridge_CPU_dest_clr_o,
    output logic        bridge_FPU_dest_clr_o,
    output logic [4:0]  bridge_dest_addr_clr_o,
    output logic [4:0]  bridge_dest_ROB_clr_o,

    input  logic [4:0]  bridge_current_wr_addr_tag_i,
    input  logic        bridge_rs1_rf_sel_i,
    input  logic        bridge_rs2_rf_sel_i,
    input  logic        bridge_rs3_rf_sel_i,

    // ---- Control state bus ----
    input  logic        bridge_cpu_busy_i,
    input  logic        bridge_cpu_br_flush_i
    // ===========================
);
    timeunit 1ns; timeprecision 1ps;

    // DEC stage
    logic [31:0]           instr;
    logic [4:0]            wr_addr_tag_D, wr_addr_tag_E, wr_addr_tag_M, wr_addr_tag_W;

    //      fp_control_unit
    logic [19:0]           fp_opcode;
    logic                  en;
    logic                  reg_write;
    logic                  fmt_sel;
    logic                  rm_sel;
    logic                  ld_sel;
    logic                  wb_sel;
    logic                  wren;
    logic [4:0]            shift_reg_addr;
    logic                  bridge_wren;
    logic                  bridge_rden;

    //      fp_reg_file
    logic [IndexWidth-1:0] readAddr1;
    logic [IndexWidth-1:0] readAddr2;
    logic [IndexWidth-1:0] readAddr3;
    logic [DataWidth-1:0]  readData1;
    logic [DataWidth-1:0]  readData2;
    logic [DataWidth-1:0]  readData3;

    //      fp_sign_extend
    logic [11:0]           in_sign_extend;
    logic [63:0]           out_sign_extend;

    // EX stage
    logic [19:0]           fp_opcode_d;
    logic                  en_d;
    logic                  fmt_sel_d;
    logic                  rm_sel_d;
    logic                  wb_sel_d;
    logic                  wren_d;
    logic [4:0]            writeAddr_d;
    logic [2:0]            rm_d;
    logic [1:0]            fmtLS_d;
    logic [1:0]            fmt_d;
    logic [63:0]           rdData1_d;
    logic [63:0]           rdData2_d;
    logic [63:0]           rdData3_d;
    logic [2:0]            dyn_rm_d;
    logic [63:0]           imm_d;
    logic [4:0]            rdAddr1_d;
    logic [4:0]            rdAddr2_d;
    logic [4:0]            rdAddr3_d;
    logic                  bridge_wren_e;
    logic                  bridge_rden_d;
    logic                  reg_write_e;
    logic [4:0]            writeAddr_e;
    logic                  ld_sel_e;
    logic                  wb_sel_e;
    logic                  wren_e;

    //      fp_unit
    logic [1:0]            fmt;
    logic [2:0]            rm;
    logic [63:0]           data1;
    logic [63:0]           data2;
    logic [63:0]           data3;
    fp_unit_in_type        fp_unit_i;
    fp_unit_out_type       fp_unit_o;  
    logic [63:0]           result;
    logic [4:0]            flags;
    logic                  ready; 
    logic [2:0]            mux_sel_rs1;

    //      fp_adder
    logic [63:0]           imm_e;

    // MEM
    logic                  reg_write_m;
    logic [4:0]            writeAddr_m;
    logic                  ld_sel_m;
    logic                  wb_sel_m;
    logic                  wren_m;
    logic [63:0]           res_m;
    logic [4:0]            flag_m;
    logic                  ready_m;
    logic [63:0]           din;
    logic [63:0]           addr;
    logic                  bridge_wren_m;
    logic                  bridge_wren_w;
    logic                  bridge_wren_c;

    //      fp_lsu
    logic [63:0]           mem2lsu;

    // WB stage
    logic                  reg_write_o;
    logic [4:0]            writeAddr_o;
    logic [DataWidth-1:0]  writeData;
    logic                  wb_sel_o;
    logic [63:0]           res_o;
    logic [4:0]            flag_o;
    logic                  ready_o;
    logic [63:0]           data2rf;
    logic                  wr_commit;
    
    // Commit stage
    logic                  reg_write_c;
    logic [4:0]            writeAddr_c;
    logic [4:0]            wr_addr_tag_c;
    logic [63:0]           writeData_c;
    logic                  wr_commit_c;

    //      fp_hazard_unit
    logic                  stall_d;  
    logic                  flush_e;
    logic                  shift_reg_en;
    logic                  occupied;
    logic                  is_raw;
    logic [1:0]            fwd1sel;
    logic [1:0]            fwd2sel;
    logic [1:0]            fwd3sel;
    logic [1:0]            cpu_fwd;

    //      Bridge to CPU
    logic [63:0]           bridge_rd_data;
    logic                  bridge_wren_temp;
    logic [4:0]            bridge_wr_addr_temp;
    logic [63:0]           bridge_wr_data_temp;
    logic                  rs1_rf_sel_d;
    logic                  rs2_rf_sel_d;
    logic                  rs3_rf_sel_d;

    // Decode stage
    fp_reg_issue_decode fp_reg_issue_decode (
        .clk(clk),
        .rst_n(rst_n),
        .en(stall_d),
        .sclr(bridge_cpu_br_flush_i),
        .instr_i(instr_i),
        .wr_addr_tag_i(bridge_fpu_wr_addr_tag_i),
        .rs1_rf_sel_i(bridge_rs1_rf_sel_i),
        .rs2_rf_sel_i(bridge_rs2_rf_sel_i),
        .rs3_rf_sel_i(bridge_rs3_rf_sel_i),
        .instr(instr),
        .wr_addr_tag_D(wr_addr_tag_D),
        .rs1_rf_sel_d(rs1_rf_sel_d),
        .rs2_rf_sel_d(rs2_rf_sel_d),
        .rs3_rf_sel_d(rs3_rf_sel_d)
    );

    fp_control_unit fp_control_unit (
        .opcode(instr[6:0]),
        .funct(instr[31:27]),
        .fcvt_op(instr[24:20]),
        .rm(instr[14:12]),
        .fp_opcode(fp_opcode),
        .en(en),
        .reg_write(reg_write),
        .fmt_sel(fmt_sel),
        .rm_sel(rm_sel),
        .ld_sel(ld_sel),
        .wb_sel(wb_sel),
        .wren(wren),
        .shift_reg_addr(shift_reg_addr),
        .bridge_wren(bridge_wren),
        .bridge_rden(bridge_rden)
    );

    assign readAddr1 = instr[19:15];
    assign readAddr2 = instr[24:20];
    assign readAddr3 = instr[31:27];

    fp_regfile fp_regfile (
        .clk(clk),
        .reset(rst_n),
        .writeEn(reg_write_c),
        .writeCommit(wr_commit_c),
        .writeAddr(writeAddr_c),
        .writeData(writeData_c),
        .readAddr1(readAddr1),
        .readAddr2(readAddr2),
        .readAddr3(readAddr3),
        .rs1_rf_sel(rs1_rf_sel_d),
        .rs2_rf_sel(rs2_rf_sel_d),
        .rs3_rf_sel(rs3_rf_sel_d),
        .readData1(readData1),
        .readData2(readData2),
        .readData3(readData3)
    );

    mux2_1 #(.DataWidth(12)) mux2_to_1_sign_extend (
        .inpA(instr[31:20]),
        .inpB({instr[31:25], instr[11:7]}),
        .sel(instr[5]),
        .outp(in_sign_extend)
    );

    fp_sign_extend fp_sign_extend (
        .in(in_sign_extend),
        .out(out_sign_extend)
    );

    // Execute stage
    fp_reg_decode_execute fp_reg_decode_execute (
        .clk(clk),
        .rst_n(rst_n),
        .sclr(flush_e | bridge_cpu_br_flush_i),
        .fp_opcode(fp_opcode),
        .en(en),
        .fmt_sel(fmt_sel),
        .rm_sel(rm_sel),
        .wb_sel(wb_sel),
        .wren(wren),
        .writeAddr(instr[11:7]),
        .rm(instr[14:12]),
        .fmtLS({instr[14], instr[12]}),
        .fmt(instr[26:25]),
        .rdData1(readData1),
        .rdData2(readData2),
        .rdData3(readData3),
        .dyn_rm(3'b000),    // TODO: need to implement fcsr
        .imm(out_sign_extend),
        .rdAddr1(readAddr1),
        .rdAddr2(readAddr2),
        .rdAddr3(readAddr3),
        .bridge_rden(bridge_rden),
        .fp_opcode_d(fp_opcode_d),
        .en_d(en_d),
        .fmt_sel_d(fmt_sel_d),
        .rm_sel_d(rm_sel_d),
        .wb_sel_d(wb_sel_d),
        .wren_d(wren_d),
        .writeAddr_d(writeAddr_d),
        .rm_d(rm_d),
        .fmtLS_d(fmtLS_d),
        .fmt_d(fmt_d),
        .rdData1_d(rdData1_d),
        .rdData2_d(rdData2_d),
        .rdData3_d(rdData3_d),
        .dyn_rm_d(dyn_rm_d),
        .imm_d(imm_d),
        .rdAddr1_d(rdAddr1_d),
        .rdAddr2_d(rdAddr2_d),
        .rdAddr3_d(rdAddr3_d),
        .bridge_rden_d(bridge_rden_d)
    );

    fp_shift_register fp_shift_register (
        .clk(clk),
        .rst_n(rst_n),
        .enable(shift_reg_en & en & ~bridge_cpu_br_flush_i),
        .has_cmd(en),
        .shift_reg_addr(shift_reg_addr),
        .reg_write_d(reg_write),
        .writeAddr_d(instr[11:7]),
        .ld_sel_d(ld_sel),
        .wb_sel_d(wb_sel),
        .wren_d(wren),
        .opcode_d(fp_opcode),
        .rdAddr1_d(readAddr1),
        .rdAddr2_d(readAddr2),
        .rdAddr3_d(readAddr3),
        .bridge_wren_d(bridge_wren),
        .bridge_rden_d(bridge_rden),
        .wr_addr_tag_D(wr_addr_tag_D),
        .reg_write_e(reg_write_e),
        .writeAddr_e(writeAddr_e),
        .ld_sel_e(ld_sel_e),
        .wb_sel_e(wb_sel_e),
        .wren_e(wren_e),
        .bridge_wren_e(bridge_wren_e),
        .wr_addr_tag_E(wr_addr_tag_E),
        .occupied(occupied),
        .is_raw(is_raw)
    );

    mux2_1 #(.DataWidth(2)) mux2_to_1_fmt_alu (
        .inpA(fmtLS_d),
        .inpB(fmt_d),
        .sel(fmt_sel_d),
        .outp(fmt)
    );
    
    
    mux2_1 #(.DataWidth(3)) mux2_to_1_rm_alu (
        .inpA(rm_d),
        .inpB(dyn_rm_d),
        .sel(rm_sel_d),
        .outp(rm)
    );
    
    always_comb begin
        if (cpu_fwd != 2'b00) begin
            mux_sel_rs1 = {1'b0, cpu_fwd};
        end
        else begin
            mux_sel_rs1 = (bridge_rden_d) ? 3'b100 : {1'b0, fwd1sel};
        end
    end

    mux5_1 #(.DataWidth(64)) mux5_to_1_data1_alu (
        .inpA(rdData1_d),
        .inpB(res_m),
        .inpC(writeData),
        .inpD(writeData_c),
        .inpE(bridge_rd_data),
        .sel(mux_sel_rs1),
        .outp(data1)
    );
    
    mux4_1 #(.DataWidth(64)) mux4_to_1_data2_alu (
        .inpA(rdData2_d),
        .inpB(res_m),
        .inpC(writeData),
        .inpD(writeData_c),
        .sel(fwd2sel),
        .outp(data2)
    );
            
    mux4_1 #(.DataWidth(64)) mux4_to_1_data3_alu (
        .inpA(rdData3_d),
        .inpB(res_m),
        .inpC(writeData),
        .inpD(writeData_c),
        .sel(fwd3sel),
        .outp(data3)
    );

    assign fp_unit_i.fp_exe_i.data1  = data1;
    assign fp_unit_i.fp_exe_i.data2  = data2;
    assign fp_unit_i.fp_exe_i.data3  = data3;
    assign fp_unit_i.fp_exe_i.op     = fp_opcode_d;
    assign fp_unit_i.fp_exe_i.fmt    = fmt;
    assign fp_unit_i.fp_exe_i.rm     = rm;
    assign fp_unit_i.fp_exe_i.enable = en_d;

    fp_unit fp_alu (
        .clock(clk),
        .reset(rst_n),
        .fp_unit_i(fp_unit_i),
        .fp_unit_o(fp_unit_o)
    );

    assign result = fp_unit_o.fp_exe_o.result;
    assign flags  = fp_unit_o.fp_exe_o.flags;
    assign ready  = fp_unit_o.fp_exe_o.ready;

    fp_adder fp_adder (
        .a(bridge_rd_data),
        .b(imm_d),
        .sum(imm_e)
    );

    // Memory access stage
    fp_reg_execute_mem fp_reg_execute_mem (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write_e(reg_write_e),
        .writeAddr_e(writeAddr_e),
        .ld_sel_e(ld_sel_e),
        .wb_sel_e(wb_sel_e),
        .wren_e(wren_e),
        .res_e(result),
        .flags_e(flags),
        .ready_e(ready),
        .data2mem(data2),
        .imm_e(imm_e),
        .bridge_wren_e(bridge_wren_e),
        .wr_addr_tag_E(wr_addr_tag_E),
        .reg_write_m(reg_write_m),
        .writeAddr_m(writeAddr_m),
        .ld_sel_m(ld_sel_m),
        .wb_sel_m(wb_sel_m),
        .wren_m(wren_m),
        .res_m(res_m),
        .flag_m(flag_m),
        .ready_m(ready_m),
        .din(din),
        .addr(addr),
        .bridge_wren_m(bridge_wren_m),
        .wr_addr_tag_M(wr_addr_tag_M)
    );

    assign mem_ld_sel = ld_sel_m;
    assign mem_wren   = wren_m;
    assign mem_addr   = addr[11:0];
    assign mem_din    = din;
    assign mem2lsu    = mem_dout;

    // WB stage
    fp_reg_mem_wb fp_reg_mem_wb (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write_w(reg_write_m),
        .writeAddr_w(writeAddr_m),
        .wb_sel_w(wb_sel_m),
        .res_w(res_m),
        .flag_w(flag_m),
        .ready_w(ready_m),
        .mem2lsu(mem2lsu),
        .wr_addr_tag_M(wr_addr_tag_M),
        .bridge_wren_m(bridge_wren_m),
        .reg_write_o(reg_write_o),
        .writeAddr_o(writeAddr_o),
        .wb_sel_o(wb_sel_o),
        .res_o(res_o),
        .flag_o(flag_o),
        .ready_o(ready_o),
        .data2rf(data2rf),
        .wr_addr_tag_W(wr_addr_tag_W),
        .bridge_wren_w(bridge_wren_w)
    );

    mux2_1 #(.DataWidth(64)) mux2_to_1_writeData(
        .inpA(res_o),
        .inpB(data2rf),
        .sel(wb_sel_o),
        .outp(writeData)
    );

    fp_tag_comparator fp_tag_cmp (
        .wr_addr_tag(wr_addr_tag_W),
        .current_wr_addr_tag(bridge_current_wr_addr_tag_i),
        .wr_commit(wr_commit)
    );

    // Commit stage
    fp_reg_wb_commit fp_reg_wb_commit (
        .clk(clk),
        .rst_n(rst_n),
        .reg_write_w(reg_write_o),
        .writeAddr_w(writeAddr_o),
        .wr_commit_w(wr_commit),
        .bridge_wren_w(bridge_wren_w),
        .writeData_w(writeData),
        .reg_write_c(reg_write_c),
        .writeAddr_c(writeAddr_c),
        .wr_commit_c(wr_commit_c),
        .bridge_wren_c(bridge_wren_c),
        .writeData_c(writeData_c)
    );

    fp_hazard_unit fp_hazard_unit (
        .wren_d(wren),
        .opcode_d(fp_opcode),
        .rdAddr1_d(readAddr1),
        .rdAddr2_d(readAddr2),
        .rdAddr3_d(readAddr3),
        .bridge_rden_d(bridge_rden),
        .wb_sel_e(wb_sel_d),
        .opcode_e(fp_opcode_d),
        .rdAddr1_e(rdAddr1_d),
        .rdAddr2_e(rdAddr2_d),
        .rdAddr3_e(rdAddr3_d),
        .writeAddr_e(writeAddr_d),
        .wren_e(wren_d),
        .bridge_rden_e(bridge_rden_d),
        .reg_write_m(reg_write_m),
        .writeAddr_m(writeAddr_m),
        .bridge_wren_m(bridge_wren_m),
        .reg_write_w(reg_write_o),
        .writeAddr_w(writeAddr_o),
        .bridge_wren_w(bridge_wren_w),
        .reg_write_c(reg_write_c),
        .writeAddr_c(writeAddr_c),
        .bridge_wren_c(bridge_wren_c),
        .occupied(occupied),
        .is_raw((is_raw | bridge_cpu_busy_i)),
        .stall_i(stall_i),
        .stall_d(stall_d),
        .flush_e(flush_e),
        .fwd1sel(fwd1sel),
        .fwd2sel(fwd2sel),
        .fwd3sel(fwd3sel),
        .shift_reg_en(shift_reg_en),
        .cpu_fwd(cpu_fwd)
    );

    fp_bridge fp_bridge (
        .cpu_busy(bridge_cpu_busy_i),
        .bridge_wren_i(bridge_wren_m),
        .bridge_wr_addr_i(writeAddr_m),
        .bridge_wr_data_i(res_m),
        .bridge_rden_i(bridge_rden),
        .bridge_rd_sel_i(rs1_rf_sel_d),
        .bridge_rd_addr_i(readAddr1),
        .bridge_rd_data_i(bridge_rd_data_i),
        .bridge_wren_o(bridge_wren_temp),
        .bridge_wr_addr_o(bridge_wr_addr_temp),
        .bridge_wr_data_o(bridge_wr_data_temp),
        .bridge_rden_o(bridge_rden_o),
        .bridge_rd_sel_o(bridge_rd_sel_o),
        .bridge_rd_addr_o(bridge_rd_addr_o),
        .bridge_rd_data_o(bridge_rd_data)
    );

    assign bridge_CPU_dest_clr_o  = bridge_wren_e;
    assign bridge_FPU_dest_clr_o  = reg_write_e;
    assign bridge_dest_addr_clr_o = writeAddr_e;
    assign bridge_dest_ROB_clr_o  = wr_addr_tag_E;
    assign bridge_wren_o          = bridge_wren_temp;
    assign bridge_wr_addr_o       = bridge_wr_addr_temp;
    assign bridge_wr_addr_tag_o   = wr_addr_tag_W;
    assign bridge_wr_data_o       = (bridge_wren_temp) ? bridge_wr_data_temp : 'z;
endmodule
