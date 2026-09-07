module MMU (
    input          clk,
    input          rst_n,

    // CPU instruction interface
    input  [31:0]  i_cpu_addr,
    output [31:0]  i_cpu_rdata,
    output         i_cpu_ready,

    // CPU data interface
    input          d_cpu_mem_st_en,
    input          d_cpu_mem_ld_en,
    input  [11:0]  d_cpu_mem_addr,
    input  [3:0]   d_cpu_mem_byte_en,
    input  [2:0]   d_cpu_mem_ld_sel,
    input  [63:0]  d_cpu_mem_st_data,
    output [63:0]  d_cpu_mem_ld_data,
    output         d_cpu_ready,

    // FPU data interface
    input          d_fpu_mem_ld_sel,
    input          d_fpu_mem_wren,
    input  [11:0]  d_fpu_mem_addr,
    input  [63:0]  d_fpu_mem_din,
    output [63:0]  d_fpu_mem_dout,

    // Instruction memory interface
    output [31:0]  i_mem_req_addr,
    output         i_mem_req_read,
    output         i_mem_req_write,
    output [255:0] i_mem_req_wdata,
    input  [255:0] i_mem_rdata,
    input          i_mem_ready,

    // Data memory interface
    output [31:0]  d_mem_req_addr,
    output         d_mem_req_read,
    output         d_mem_req_write,
    output [255:0] d_mem_req_wdata,
    input  [255:0] d_mem_rdata,
    input          d_mem_ready
);

    timeunit 1ns; timeprecision 1ps;

    wire reset;
    wire [31:0] i_cpu_wdata;
    wire        i_cpu_read;
    wire        i_cpu_write;

    logic [31:0] d_cache_addr;
    logic        d_cache_read;
    logic        d_cache_write;
    logic [63:0] d_cache_wdata;
    logic [63:0] d_cache_rdata;

    assign reset       = ~rst_n;
    assign i_cpu_read  = 1'b1;
    assign i_cpu_write = 1'b0;
    assign i_cpu_wdata = 32'h0000_0000;

    Cache #(
        .CPU_DATA_WIDTH(32),
        .READ_ONLY(1'b1),
        .LINE_WIDTH(256),
        .NUM_SETS(32),
        .NUM_WAYS(2),
        .TAG_WIDTH(22)
    ) i_cache (
        .clk(clk),
        .reset(reset),
        .cpu_addr(i_cpu_addr),
        .cpu_read(i_cpu_read),
        .cpu_write(i_cpu_write),
        .cpu_wdata(i_cpu_wdata),
        .cpu_rdata(i_cpu_rdata),
        .cpu_ready(i_cpu_ready),
        .mem_req_addr(i_mem_req_addr),
        .mem_req_read(i_mem_req_read),
        .mem_req_write(i_mem_req_write),
        .mem_req_wdata(i_mem_req_wdata),
        .mem_rdata(i_mem_rdata),
        .mem_ready(i_mem_ready)
    );

    lsu_controller lsu_ctrl (
        .cpu_mem_st_en(d_cpu_mem_st_en),
        .cpu_mem_ld_en(d_cpu_mem_ld_en),
        .cpu_mem_addr(d_cpu_mem_addr),
        .cpu_mem_byte_en(d_cpu_mem_byte_en),
        .cpu_mem_ld_sel(d_cpu_mem_ld_sel),
        .cpu_mem_st_data(d_cpu_mem_st_data),
        .cpu_mem_ld_data(d_cpu_mem_ld_data),
        .fpu_mem_ld_sel(d_fpu_mem_ld_sel),
        .fpu_mem_wren(d_fpu_mem_wren),
        .fpu_mem_addr(d_fpu_mem_addr),
        .fpu_mem_din(d_fpu_mem_din),
        .fpu_mem_dout(d_fpu_mem_dout),
        .d_cache_addr(d_cache_addr),
        .d_cache_read(d_cache_read),
        .d_cache_write(d_cache_write),
        .d_cache_wdata(d_cache_wdata),
        .d_cache_rdata(d_cache_rdata)
    );

    Cache #(
        .CPU_DATA_WIDTH(64),
        .READ_ONLY(1'b0),
        .LINE_WIDTH(256),
        .NUM_SETS(32),
        .NUM_WAYS(2),
        .TAG_WIDTH(22)
    ) d_cache (
        .clk(clk),
        .reset(reset),
        .cpu_addr(d_cache_addr),
        .cpu_read(d_cache_read),
        .cpu_write(d_cache_write),
        .cpu_wdata(d_cache_wdata),
        .cpu_rdata(d_cache_rdata),
        .cpu_ready(d_cpu_ready),
        .mem_req_addr(d_mem_req_addr),
        .mem_req_read(d_mem_req_read),
        .mem_req_write(d_mem_req_write),
        .mem_req_wdata(d_mem_req_wdata),
        .mem_rdata(d_mem_rdata),
        .mem_ready(d_mem_ready)
    );

endmodule

module lsu_controller (
    input  logic        cpu_mem_st_en,
    input  logic        cpu_mem_ld_en,
    input  logic [11:0] cpu_mem_addr,
    input  logic [3:0]  cpu_mem_byte_en,
    input  logic [2:0]  cpu_mem_ld_sel,
    input  logic [63:0] cpu_mem_st_data,
    output logic [63:0] cpu_mem_ld_data,

    input  logic        fpu_mem_ld_sel,
    input  logic        fpu_mem_wren,
    input  logic [11:0] fpu_mem_addr,
    input  logic [63:0] fpu_mem_din,
    output logic [63:0] fpu_mem_dout,

    output logic [31:0] d_cache_addr,
    output logic        d_cache_read,
    input  logic [63:0] d_cache_rdata,
    output logic        d_cache_write,
    output logic [63:0] d_cache_wdata
);

    timeunit 1ns; timeprecision 1ps;

    logic [3:0]  byte_en;
    logic [2:0]  ld_sel;
    logic [63:0] st_data;
    logic [63:0] ld_data;

    logic [63:0] ld;
    logic [31:0] lw;
    logic [31:0] lwu;
    logic [15:0] lh;
    logic [15:0] lhu;
    logic [7:0]  lb;
    logic [7:0]  lbu;

    assign d_cache_write   = cpu_mem_st_en | fpu_mem_wren;
    assign d_cache_read    = cpu_mem_ld_en | fpu_mem_ld_sel;
    assign d_cache_addr    = (fpu_mem_ld_sel | fpu_mem_wren) ? {20'd0, fpu_mem_addr} : {20'd0, cpu_mem_addr};
    assign byte_en         = fpu_mem_wren ? 4'b0111 : cpu_mem_byte_en;
    assign ld_sel          = fpu_mem_ld_sel ? 3'h3 : cpu_mem_ld_sel;
    assign st_data         = fpu_mem_wren ? fpu_mem_din : cpu_mem_st_data;
    assign cpu_mem_ld_data = cpu_mem_ld_en ? ld_data : '0;
    assign fpu_mem_dout    = fpu_mem_ld_sel ? ld_data : '0;

    always_comb begin
        unique case (byte_en)
            4'b0001: d_cache_wdata = {56'b0, st_data[7:0]};
            4'b0011: d_cache_wdata = {48'b0, st_data[15:0]};
            4'b1111: d_cache_wdata = {32'b0, st_data[31:0]};
            4'b0111: d_cache_wdata = st_data;
            default: d_cache_wdata = st_data;
        endcase
    end

    assign ld  = d_cache_rdata;
    assign lw  = d_cache_rdata[31:0];
    assign lwu = d_cache_rdata[31:0];
    assign lh  = d_cache_rdata[15:0];
    assign lhu = d_cache_rdata[15:0];
    assign lb  = d_cache_rdata[7:0];
    assign lbu = d_cache_rdata[7:0];

    always_comb begin
        unique case (ld_sel)
            3'h0: ld_data = {56'b0, lbu};
            3'h1: ld_data = {48'b0, lhu};
            3'h2: ld_data = {{56{lb[7]}}, lb};
            3'h3: ld_data = ld;
            3'h4: ld_data = {{48{lh[15]}}, lh};
            3'h5: ld_data = {32'b0, lwu};
            3'h6: ld_data = {{32{lw[31]}}, lw};
            default: ld_data = ld;
        endcase
    end

endmodule
