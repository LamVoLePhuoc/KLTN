module dual_core #(parameter NO_RESERV = 16) (
    input  logic         clk,
    input  logic         rst_n,

    // ========= AXI-4 Interface =========
    // ------- I-cache Interface -------
    output logic [31:0]  imem_req_addr,
    output logic         imem_req_read,
    output logic         imem_req_write,
    output logic [255:0] imem_req_wdata,
    input  logic [255:0] imem_rdata,
    input  logic         imem_ready,
    // ---------------------------------
    // ------- D-cache Interface -------
    input  logic [255:0] dmem_rdata,
    input  logic         dmem_ready,
    output logic [31:0]  dmem_req_addr,
    output logic         dmem_req_read,
    output logic         dmem_req_write,
    output logic [255:0] dmem_req_wdata
    // ---------------------------------
    // ===================================
);
    timeunit 1ns; timeprecision 1ps;

    logic        bridge_fpu_busy;
    logic [63:0] bridge_rd_data;
    logic        bridge_wren;
    logic [4:0]  bridge_wr_addr;
    logic [4:0]  bridge_wr_addr_tag;
    logic [63:0] bridge_wr_data;
    logic        bridge_rden;
    logic        bridge_rd_sel;
    logic [4:0]  bridge_rd_addr;
    logic        bridge_CPU_dest_clr;
    logic        bridge_FPU_dest_clr;
    logic [4:0]  bridge_dest_addr_clr;
    logic [4:0]  bridge_dest_ROB_clr;

    logic        bridge_cpu_busy;
    logic        bridge_cpu_br_flush;
    logic [31:0] bridge_fpu_instr;
    logic [4:0]  bridge_fpu_wr_addr_tag;

    logic [4:0]  bridge_current_wr_addr_tag;
    logic        bridge_rs1_rf_sel;
    logic        bridge_rs2_rf_sel;
    logic        bridge_rs3_rf_sel;

    logic        cpu_mem_st_en;
    logic        cpu_mem_ld_en;
    logic [11:0] cpu_mem_addr;
    logic [3:0]  cpu_mem_byte_en;
    logic [2:0]  cpu_mem_ld_sel;
    logic [63:0] cpu_mem_st_data;
    logic [63:0] cpu_mem_ld_data;

    logic        fpu_mem_ld_sel;
    logic        fpu_mem_wren;
    logic [11:0] fpu_mem_addr;
    logic [63:0] fpu_mem_din;
    logic [63:0] fpu_mem_dout;

    logic [31:0] pc2cache;
    logic [31:0] cache_instr;
    logic        cache_i_ready;

    logic        core_clk;
    logic        mem_clk;

    `ifdef DEBUG_EN
        longint unsigned core_clock_counter;
        initial begin
            @(posedge rst_n);
            forever @(posedge core_clk) begin
                core_clock_counter++;
            end
        end
    `endif

    clk_divider clk_divider (
        .clk(clk),
        .rst_n(rst_n),
        .core_clk(core_clk),
        .mem_clk(mem_clk)
    );

    fp_top FPU (
        .clk(core_clk),
        .rst_n(rst_n),
        .instr_i(bridge_fpu_instr),
        .bridge_fpu_wr_addr_tag_i(bridge_fpu_wr_addr_tag),
        .stall_i(bridge_fpu_busy),
        .mem_ld_sel(fpu_mem_ld_sel),
        .mem_wren(fpu_mem_wren),
        .mem_addr(fpu_mem_addr),
        .mem_din(fpu_mem_din),
        .mem_dout(fpu_mem_dout),
        .bridge_wren_o(bridge_wren),
        .bridge_wr_addr_o(bridge_wr_addr),
        .bridge_wr_addr_tag_o(bridge_wr_addr_tag),
        .bridge_wr_data_o(bridge_wr_data),
        .bridge_rden_o(bridge_rden),
        .bridge_rd_sel_o(bridge_rd_sel),
        .bridge_rd_addr_o(bridge_rd_addr),
        .bridge_rd_data_i(bridge_rd_data),
        .bridge_CPU_dest_clr_o(bridge_CPU_dest_clr),        
        .bridge_FPU_dest_clr_o(bridge_FPU_dest_clr),
        .bridge_dest_addr_clr_o(bridge_dest_addr_clr),
        .bridge_dest_ROB_clr_o(bridge_dest_ROB_clr),
        .bridge_cpu_busy_i(bridge_cpu_busy),
        .bridge_cpu_br_flush_i(bridge_cpu_br_flush),
        .bridge_current_wr_addr_tag_i(bridge_current_wr_addr_tag),
        .bridge_rs1_rf_sel_i(bridge_rs1_rf_sel),
        .bridge_rs2_rf_sel_i(bridge_rs2_rf_sel),
        .bridge_rs3_rf_sel_i(bridge_rs3_rf_sel)
    );

    rv64im #(.NO_RESERV(NO_RESERV)) CPU (
        .clk_i(core_clk), 
        .rst_ni(rst_n),
        .mem_st_en(cpu_mem_st_en),
        .mem_ld_en(cpu_mem_ld_en),
        .mem_addr(cpu_mem_addr),
        .mem_byte_en(cpu_mem_byte_en),
        .mem_ld_sel(cpu_mem_ld_sel),
        .mem_st_data(cpu_mem_st_data),
        .mem_ld_data(cpu_mem_ld_data),
        .bridge_wren_i(bridge_wren),
        .bridge_wr_addr_i(bridge_wr_addr),
        .bridge_wr_addr_tag_i(bridge_wr_addr_tag),
        .bridge_wr_data_i(bridge_wr_data),
        .bridge_rden_i(bridge_rden),
        .bridge_rd_sel_i(bridge_rd_sel),
        .bridge_rd_addr_i(bridge_rd_addr),
        .bridge_fpu_busy_i(bridge_fpu_busy),
        .bridge_CPU_dest_clr_i(bridge_CPU_dest_clr),
        .bridge_FPU_dest_clr_i(bridge_FPU_dest_clr),  
        .bridge_dest_addr_clr_i(bridge_dest_addr_clr),
        .bridge_dest_ROB_clr_i(bridge_dest_ROB_clr),
        .bridge_rd_data_o(bridge_rd_data),
        .bridge_cpu_busy_o(bridge_cpu_busy),
        .bridge_cpu_br_flush_o(bridge_cpu_br_flush),
        .bridge_fpu_instr_o(bridge_fpu_instr),
        .bridge_fpu_wr_addr_tag_o(bridge_fpu_wr_addr_tag),
        .bridge_fpu_current_wr_addr_tag_o(bridge_current_wr_addr_tag),
        .bridge_rs1_rf_sel_o(bridge_rs1_rf_sel),
        .bridge_rs2_rf_sel_o(bridge_rs2_rf_sel),
        .bridge_rs3_rf_sel_o(bridge_rs3_rf_sel),
        .pc2cache_o(pc2cache),
        .cache_instr_i(cache_instr),
        .cache_i_ready_i(cache_i_ready)
    );

    MMU MMU (
        .clk(mem_clk),
        .rst_n(rst_n),
        .i_cpu_addr(pc2cache),
        .i_cpu_rdata(cache_instr),
        .i_cpu_ready(cache_i_ready),
        .i_mem_req_addr(imem_req_addr),
        .i_mem_req_read(imem_req_read),
        .i_mem_req_write(imem_req_write),
        .i_mem_req_wdata(imem_req_wdata),
        .i_mem_rdata(imem_rdata),
        .i_mem_ready(imem_ready),
        .d_cpu_mem_st_en(cpu_mem_st_en),
        .d_cpu_mem_ld_en(cpu_mem_ld_en),
        .d_cpu_mem_addr(cpu_mem_addr),
        .d_cpu_mem_byte_en(cpu_mem_byte_en),
        .d_cpu_mem_ld_sel(cpu_mem_ld_sel),
        .d_cpu_mem_st_data(cpu_mem_st_data),
        .d_cpu_mem_ld_data(cpu_mem_ld_data),
        .d_fpu_mem_ld_sel(fpu_mem_ld_sel),
        .d_fpu_mem_wren(fpu_mem_wren),
        .d_fpu_mem_addr(fpu_mem_addr),
        .d_fpu_mem_din(fpu_mem_din),
        .d_fpu_mem_dout(fpu_mem_dout),
        .d_mem_req_addr(dmem_req_addr),
        .d_mem_req_read(dmem_req_read),
        .d_mem_req_write(dmem_req_write),
        .d_mem_req_wdata(dmem_req_wdata),
        .d_mem_rdata(dmem_rdata),
        .d_mem_ready(dmem_ready)
    );

endmodule: dual_core