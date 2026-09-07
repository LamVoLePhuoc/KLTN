`timescale 1ps / 1ps
//
// multicore_top: Phase-2 top level. 4x core_top (each with its own
// private L1 I-cache + D-cache, per core_top.sv / MMU.sv) sharing one
// L2_Cache (512KB) through `interconnect`, backed by one DRAM behavioral
// model. The interconnect also carries the coherence snoop-invalidate
// broadcast back to each core's private D-cache.
//
//                core_top[0..3]
//                 i_mem*  d_mem*
//                    \      /
//                 interconnect (8:1 arbiter + snoop broadcast)
//                       |
//                    L2_Cache (512KB)
//                       |
//                  mem_model256 (DRAM)
//
module multicore_top #(
    parameter NUM_CORES = 4
) (
    input clk,
    input rst_n,

    // Debug/verification taps, one set per core (used by the testbench)
    output [31:0] dbg_pc           [0:NUM_CORES-1],
    output [31:0] dbg_instr        [0:NUM_CORES-1],
    output        dbg_instr_retire [0:NUM_CORES-1]
);

    // ------------------------------------------------------------------
    // Per-core <-> interconnect wiring. Requester index k: 0..3 = I-cache
    // of core k, 4..7 = D-cache of core (k-4).
    // ------------------------------------------------------------------
    wire [31:0]  req_addr  [0:7];
    wire         req_read  [0:7];
    wire         req_write [0:7];
    wire [255:0] req_wdata [0:7];
    wire [255:0] req_rdata [0:7];
    wire         req_ready [0:7];

    wire [31:0]  l2_addr;
    wire         l2_read, l2_write;
    wire [255:0] l2_wdata;
    wire [255:0] l2_rdata;
    wire         l2_ready;

    wire [NUM_CORES-1:0] snoop_en;
    wire [31:0]           snoop_addr;

    wire [31:0]  dram_addr;
    wire         dram_read, dram_write;
    wire [255:0] dram_wdata;
    wire [255:0] dram_rdata;
    wire         dram_ready;

    genvar c;
    generate
        for (c = 0; c < NUM_CORES; c = c + 1) begin : CORE
            wire dbg_i_cpu_ready_unused, dbg_d_cpu_ready_unused;
            wire dbg_needs_mem_unused, dbg_mem_read_unused, dbg_mem_write_unused;

            // Each core boots into its own 4KB-aligned program region
            // (0x0000, 0x1000, 0x2000, 0x3000 for cores 0..3) — see
            // tb_multicore_top.sv for what's preloaded at each.
            core_top #(.RESET_PC(32'h0000_1000 * c)) u_core (
                .clk(clk), .rst_n(rst_n),

                .i_mem_req_addr(req_addr[c]), .i_mem_req_read(req_read[c]),
                .i_mem_req_write(req_write[c]), .i_mem_req_wdata(req_wdata[c]),
                .i_mem_rdata(req_rdata[c]), .i_mem_ready(req_ready[c]),

                .d_mem_req_addr(req_addr[c+4]), .d_mem_req_read(req_read[c+4]),
                .d_mem_req_write(req_write[c+4]), .d_mem_req_wdata(req_wdata[c+4]),
                .d_mem_rdata(req_rdata[c+4]), .d_mem_ready(req_ready[c+4]),

                .snoop_en(snoop_en[c]), .snoop_addr(snoop_addr),

                .dbg_pc(dbg_pc[c]), .dbg_instr(dbg_instr[c]), .dbg_instr_retire(dbg_instr_retire[c]),
                .dbg_i_cpu_ready(dbg_i_cpu_ready_unused), .dbg_d_cpu_ready(dbg_d_cpu_ready_unused),
                .dbg_needs_mem(dbg_needs_mem_unused), .dbg_mem_read(dbg_mem_read_unused),
                .dbg_mem_write(dbg_mem_write_unused)
            );
            // Note: req_write[c] (the I-cache slot) is driven by
            // core_top's i_mem_req_write output above, which I_Cache
            // always ties to 0 internally (instruction fetches never
            // write) — no separate tie-off needed here.
        end
    endgenerate

    mc_interconnect #(.NUM_CORES(NUM_CORES)) u_interconnect (
        .clk(clk), .rst_n(rst_n),
        .req_addr(req_addr), .req_read(req_read), .req_write(req_write),
        .req_wdata(req_wdata), .req_rdata(req_rdata), .req_ready(req_ready),
        .l2_addr(l2_addr), .l2_read(l2_read), .l2_write(l2_write),
        .l2_wdata(l2_wdata), .l2_rdata(l2_rdata), .l2_ready(l2_ready),
        .snoop_en(snoop_en), .snoop_addr(snoop_addr)
    );

    L2_Cache u_l2 (
        .clk(clk), .reset(~rst_n),
        .cpu_addr(l2_addr), .cpu_read(l2_read), .cpu_write(l2_write),
        .cpu_wdata(l2_wdata), .cpu_rdata(l2_rdata), .cpu_ready(l2_ready),
        .mem_req_addr(dram_addr), .mem_req_read(dram_read), .mem_req_write(dram_write),
        .mem_req_wdata(dram_wdata), .mem_rdata(dram_rdata), .mem_ready(dram_ready)
    );

    mem_model256 #(.LINES(4096), .LAT_CYCLES(2)) u_dram (
        .clk(clk), .rst_n(rst_n),
        .mem_req_addr(dram_addr), .mem_req_read(dram_read), .mem_req_write(dram_write),
        .mem_req_wdata(dram_wdata), .mem_rdata(dram_rdata), .mem_ready(dram_ready)
    );

endmodule
