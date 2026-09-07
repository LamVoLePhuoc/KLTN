module rv32_quad_cache_soc #(
    parameter int NUM_CORES  = 4,
    parameter int ADDR_WIDTH = 32,
    parameter int LINE_WIDTH = 256
) (
    input  wire                      clk,
    input  wire                      rst_n,

    output wire [ADDR_WIDTH-1:0]     dram_req_addr,
    output wire                      dram_req_read,
    output wire                      dram_req_write,
    output wire [LINE_WIDTH-1:0]     dram_req_wdata,
    input  wire [LINE_WIDTH-1:0]     dram_rdata,
    input  wire                      dram_ready
);

    timeunit 1ns; timeprecision 1ps;

    localparam int PORTS_PER_CORE = 2;
    localparam int NUM_L1_PORTS = NUM_CORES * PORTS_PER_CORE;

    wire [NUM_L1_PORTS*ADDR_WIDTH-1:0] l1_req_addr;
    wire [NUM_L1_PORTS-1:0]            l1_req_read;
    wire [NUM_L1_PORTS-1:0]            l1_req_write;
    wire [NUM_L1_PORTS*LINE_WIDTH-1:0] l1_req_wdata;
    wire [NUM_L1_PORTS*LINE_WIDTH-1:0] l1_resp_rdata;
    wire [NUM_L1_PORTS-1:0]            l1_resp_ready;

    genvar core_idx;
    generate
        for (core_idx = 0; core_idx < NUM_CORES; core_idx = core_idx + 1) begin : gen_core
            localparam int I_PORT = core_idx * PORTS_PER_CORE;
            localparam int D_PORT = core_idx * PORTS_PER_CORE + 1;

            rv32i core (
                .clk(clk),
                .rst_n(rst_n),
                .imem_rdata(l1_resp_rdata[I_PORT*LINE_WIDTH +: LINE_WIDTH]),
                .imem_ready(l1_resp_ready[I_PORT]),
                .imem_req_addr(l1_req_addr[I_PORT*ADDR_WIDTH +: ADDR_WIDTH]),
                .imem_req_read(l1_req_read[I_PORT]),
                .imem_req_write(l1_req_write[I_PORT]),
                .imem_req_wdata(l1_req_wdata[I_PORT*LINE_WIDTH +: LINE_WIDTH]),
                .dmem_rdata(l1_resp_rdata[D_PORT*LINE_WIDTH +: LINE_WIDTH]),
                .dmem_ready(l1_resp_ready[D_PORT]),
                .dmem_req_addr(l1_req_addr[D_PORT*ADDR_WIDTH +: ADDR_WIDTH]),
                .dmem_req_read(l1_req_read[D_PORT]),
                .dmem_req_write(l1_req_write[D_PORT]),
                .dmem_req_wdata(l1_req_wdata[D_PORT*LINE_WIDTH +: LINE_WIDTH])
            );
        end
    endgenerate

    RV32SharedL2Subsystem #(
        .NUM_PORTS(NUM_L1_PORTS),
        .ADDR_WIDTH(ADDR_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .L2_NUM_SETS(8192)
    ) shared_l2_subsystem (
        .clk(clk),
        .reset_n(rst_n),
        .l1_req_addr(l1_req_addr),
        .l1_req_read(l1_req_read),
        .l1_req_write(l1_req_write),
        .l1_req_wdata(l1_req_wdata),
        .l1_resp_rdata(l1_resp_rdata),
        .l1_resp_ready(l1_resp_ready),
        .dram_req_addr(dram_req_addr),
        .dram_req_read(dram_req_read),
        .dram_req_write(dram_req_write),
        .dram_req_wdata(dram_req_wdata),
        .dram_rdata(dram_rdata),
        .dram_ready(dram_ready)
    );

endmodule
