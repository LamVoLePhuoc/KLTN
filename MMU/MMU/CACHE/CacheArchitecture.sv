module CacheArchitecture #(
    parameter int NUM_CORES         = 4,
    parameter int ADDR_WIDTH        = 32,
    parameter int LINE_WIDTH        = 256,
    parameter int L1I_CPU_WIDTH     = 32,
    parameter int L1D_CPU_WIDTH     = 64,
    parameter int L1_NUM_SETS       = 512,
    parameter int L2_NUM_SETS       = 8192,
    parameter int AXI_ID_WIDTH      = 5,
    parameter int AXI_MST_ID_WIDTH  = $clog2(NUM_CORES * 2),
    parameter int AXI_SLV_SEL_WIDTH = 1,
    parameter int AXI_SLV_ID_WIDTH  = AXI_ID_WIDTH + AXI_MST_ID_WIDTH,
    parameter int AXI_LEN_WIDTH     = 3,
    parameter int AXI_SIZE_WIDTH    = 3,
    parameter int AXI_BURST_WIDTH   = 2,
    parameter int AXI_RESP_WIDTH    = 2,
    parameter int L1_MASTER_AMT     = NUM_CORES * 2
) (
    input  wire                                      clk,
    input  wire                                      reset_n,

    input  wire [NUM_CORES*ADDR_WIDTH-1:0]           core_i_addr,
    input  wire [NUM_CORES-1:0]                      core_i_read,
    output wire [NUM_CORES*L1I_CPU_WIDTH-1:0]        core_i_rdata,
    output wire [NUM_CORES-1:0]                      core_i_ready,

    input  wire [NUM_CORES*ADDR_WIDTH-1:0]           core_d_addr,
    input  wire [NUM_CORES-1:0]                      core_d_read,
    input  wire [NUM_CORES-1:0]                      core_d_write,
    input  wire [NUM_CORES*L1D_CPU_WIDTH-1:0]        core_d_wdata,
    output wire [NUM_CORES*L1D_CPU_WIDTH-1:0]        core_d_rdata,
    output wire [NUM_CORES-1:0]                      core_d_ready,

    output wire [ADDR_WIDTH-1:0]                     dram_req_addr,
    output wire                                      dram_req_read,
    output wire                                      dram_req_write,
    output wire [LINE_WIDTH-1:0]                     dram_req_wdata,
    input  wire [LINE_WIDTH-1:0]                     dram_rdata,
    input  wire                                      dram_ready
);

    timeunit 1ns; timeprecision 1ps;

    localparam int L2_SLV_AMT = 1;
    localparam int L1I_TAG_WIDTH = ADDR_WIDTH - $clog2(L1_NUM_SETS) - $clog2(LINE_WIDTH / 8);
    localparam int L1D_TAG_WIDTH = L1I_TAG_WIDTH;
    localparam int L2_TAG_WIDTH  = ADDR_WIDTH - $clog2(L2_NUM_SETS) - $clog2(LINE_WIDTH / 8);

    wire reset;
    assign reset = ~reset_n;

    wire [L1_MASTER_AMT*AXI_ID_WIDTH-1:0]      m_AWID_i;
    wire [L1_MASTER_AMT*ADDR_WIDTH-1:0]        m_AWADDR_i;
    wire [L1_MASTER_AMT*AXI_BURST_WIDTH-1:0]   m_AWBURST_i;
    wire [L1_MASTER_AMT*AXI_LEN_WIDTH-1:0]     m_AWLEN_i;
    wire [L1_MASTER_AMT*AXI_SIZE_WIDTH-1:0]    m_AWSIZE_i;
    wire [L1_MASTER_AMT-1:0]                   m_AWVALID_i;
    wire [L1_MASTER_AMT*LINE_WIDTH-1:0]        m_WDATA_i;
    wire [L1_MASTER_AMT-1:0]                   m_WLAST_i;
    wire [L1_MASTER_AMT-1:0]                   m_WVALID_i;
    wire [L1_MASTER_AMT-1:0]                   m_BREADY_i;
    wire [L1_MASTER_AMT*AXI_ID_WIDTH-1:0]      m_ARID_i;
    wire [L1_MASTER_AMT*ADDR_WIDTH-1:0]        m_ARADDR_i;
    wire [L1_MASTER_AMT*AXI_BURST_WIDTH-1:0]   m_ARBURST_i;
    wire [L1_MASTER_AMT*AXI_LEN_WIDTH-1:0]     m_ARLEN_i;
    wire [L1_MASTER_AMT*AXI_SIZE_WIDTH-1:0]    m_ARSIZE_i;
    wire [L1_MASTER_AMT-1:0]                   m_ARVALID_i;
    wire [L1_MASTER_AMT-1:0]                   m_RREADY_i;

    wire [L1_MASTER_AMT-1:0]                   m_AWREADY_o;
    wire [L1_MASTER_AMT-1:0]                   m_WREADY_o;
    wire [L1_MASTER_AMT*AXI_ID_WIDTH-1:0]      m_BID_o;
    wire [L1_MASTER_AMT*AXI_RESP_WIDTH-1:0]    m_BRESP_o;
    wire [L1_MASTER_AMT-1:0]                   m_BVALID_o;
    wire [L1_MASTER_AMT-1:0]                   m_ARREADY_o;
    wire [L1_MASTER_AMT*AXI_ID_WIDTH-1:0]      m_RID_o;
    wire [L1_MASTER_AMT*LINE_WIDTH-1:0]        m_RDATA_o;
    wire [L1_MASTER_AMT*AXI_RESP_WIDTH-1:0]    m_RRESP_o;
    wire [L1_MASTER_AMT-1:0]                   m_RLAST_o;
    wire [L1_MASTER_AMT-1:0]                   m_RVALID_o;

    wire [AXI_SLV_ID_WIDTH-1:0]                s_AWID_o;
    wire [ADDR_WIDTH-1:0]                      s_AWADDR_o;
    wire [AXI_BURST_WIDTH-1:0]                 s_AWBURST_o;
    wire [AXI_LEN_WIDTH-1:0]                   s_AWLEN_o;
    wire [AXI_SIZE_WIDTH-1:0]                  s_AWSIZE_o;
    wire                                       s_AWVALID_o;
    wire                                       s_AWREADY_i;
    wire [LINE_WIDTH-1:0]                      s_WDATA_o;
    wire                                       s_WLAST_o;
    wire                                       s_WVALID_o;
    wire                                       s_WREADY_i;
    wire [AXI_SLV_ID_WIDTH-1:0]                s_BID_i;
    wire [AXI_RESP_WIDTH-1:0]                  s_BRESP_i;
    wire                                       s_BVALID_i;
    wire                                       s_BREADY_o;
    wire [AXI_SLV_ID_WIDTH-1:0]                s_ARID_o;
    wire [ADDR_WIDTH-1:0]                      s_ARADDR_o;
    wire [AXI_BURST_WIDTH-1:0]                 s_ARBURST_o;
    wire [AXI_LEN_WIDTH-1:0]                   s_ARLEN_o;
    wire [AXI_SIZE_WIDTH-1:0]                  s_ARSIZE_o;
    wire                                       s_ARVALID_o;
    wire                                       s_ARREADY_i;
    wire [AXI_SLV_ID_WIDTH-1:0]                s_RID_i;
    wire [LINE_WIDTH-1:0]                      s_RDATA_i;
    wire [AXI_RESP_WIDTH-1:0]                  s_RRESP_i;
    wire                                       s_RLAST_i;
    wire                                       s_RVALID_i;
    wire                                       s_RREADY_o;

    wire [L1_MASTER_AMT*LINE_WIDTH-1:0]        l1_mem_rdata;
    wire [L1_MASTER_AMT-1:0]                   l1_mem_ready;
    wire [L1_MASTER_AMT*ADDR_WIDTH-1:0]        l1_mem_addr;
    wire [L1_MASTER_AMT-1:0]                   l1_mem_read;
    wire [L1_MASTER_AMT-1:0]                   l1_mem_write;
    wire [L1_MASTER_AMT*LINE_WIDTH-1:0]        l1_mem_wdata;

    // Phase-3 coherence: CoherenceManager broadcasts one invalidate per
    // core (d-cache only -- instructions aren't written by other cores).
    // The broadcast is driven off store_committed/store_committed_addr
    // (pulses when a store's write-through to L2 actually lands), not
    // off the raw core_d_write request, so an invalidated peer's re-read
    // is guaranteed to find the fresh value already at L2.
    wire [NUM_CORES-1:0]              l1d_snoop_en;
    wire [NUM_CORES*ADDR_WIDTH-1:0]   l1d_snoop_addr;
    wire [NUM_CORES-1:0]              l1d_store_committed;
    wire [NUM_CORES*ADDR_WIDTH-1:0]   l1d_store_committed_addr;

    genvar core_idx;
    generate
        for (core_idx = 0; core_idx < NUM_CORES; core_idx = core_idx + 1) begin : gen_l1
            localparam int I_MST = core_idx * 2;
            localparam int D_MST = core_idx * 2 + 1;

            SetAssociativeCache #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .CPU_DATA_WIDTH(L1I_CPU_WIDTH),
                .READ_ONLY(1'b1),
                .LINE_WIDTH(LINE_WIDTH),
                .NUM_SETS(L1_NUM_SETS),
                .TAG_WIDTH(L1I_TAG_WIDTH)
            ) l1_i_cache (
                .clk(clk),
                .reset(reset),
                .cpu_addr(core_i_addr[core_idx*ADDR_WIDTH +: ADDR_WIDTH]),
                .cpu_read(core_i_read[core_idx]),
                .cpu_write(1'b0),
                .cpu_wdata('0),
                .cpu_rdata(core_i_rdata[core_idx*L1I_CPU_WIDTH +: L1I_CPU_WIDTH]),
                .cpu_ready(core_i_ready[core_idx]),
                .mem_req_addr(l1_mem_addr[I_MST*ADDR_WIDTH +: ADDR_WIDTH]),
                .mem_req_read(l1_mem_read[I_MST]),
                .mem_req_write(l1_mem_write[I_MST]),
                .mem_req_wdata(l1_mem_wdata[I_MST*LINE_WIDTH +: LINE_WIDTH]),
                .mem_rdata(l1_mem_rdata[I_MST*LINE_WIDTH +: LINE_WIDTH]),
                .mem_ready(l1_mem_ready[I_MST]),
                .error_out(),
                .snoop_en(1'b0),
                .snoop_addr('0),
                .store_committed(),
                .store_committed_addr()
            );

            SetAssociativeCache #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .CPU_DATA_WIDTH(L1D_CPU_WIDTH),
                .READ_ONLY(1'b0),
                .LINE_WIDTH(LINE_WIDTH),
                .NUM_SETS(L1_NUM_SETS),
                .TAG_WIDTH(L1D_TAG_WIDTH)
            ) l1_d_cache (
                .clk(clk),
                .reset(reset),
                .cpu_addr(core_d_addr[core_idx*ADDR_WIDTH +: ADDR_WIDTH]),
                .cpu_read(core_d_read[core_idx]),
                .cpu_write(core_d_write[core_idx]),
                .cpu_wdata(core_d_wdata[core_idx*L1D_CPU_WIDTH +: L1D_CPU_WIDTH]),
                .cpu_rdata(core_d_rdata[core_idx*L1D_CPU_WIDTH +: L1D_CPU_WIDTH]),
                .cpu_ready(core_d_ready[core_idx]),
                .mem_req_addr(l1_mem_addr[D_MST*ADDR_WIDTH +: ADDR_WIDTH]),
                .mem_req_read(l1_mem_read[D_MST]),
                .mem_req_write(l1_mem_write[D_MST]),
                .mem_req_wdata(l1_mem_wdata[D_MST*LINE_WIDTH +: LINE_WIDTH]),
                .mem_rdata(l1_mem_rdata[D_MST*LINE_WIDTH +: LINE_WIDTH]),
                .mem_ready(l1_mem_ready[D_MST]),
                .error_out(),
                .snoop_en(l1d_snoop_en[core_idx]),
                .snoop_addr(l1d_snoop_addr[core_idx*ADDR_WIDTH +: ADDR_WIDTH]),
                .store_committed(l1d_store_committed[core_idx]),
                .store_committed_addr(l1d_store_committed_addr[core_idx*ADDR_WIDTH +: ADDR_WIDTH])
            );

            SimpleCacheToAxiMaster #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(LINE_WIDTH),
                .AXI_ID_WIDTH(AXI_ID_WIDTH),
                .AXI_LEN_WIDTH(AXI_LEN_WIDTH),
                .AXI_SIZE_WIDTH(AXI_SIZE_WIDTH),
                .AXI_BURST_WIDTH(AXI_BURST_WIDTH),
                .AXI_RESP_WIDTH(AXI_RESP_WIDTH),
                .MASTER_ID(I_MST)
            ) i_axi_master (
                .clk(clk),
                .reset(reset),
                .req_addr(l1_mem_addr[I_MST*ADDR_WIDTH +: ADDR_WIDTH]),
                .req_read(l1_mem_read[I_MST]),
                .req_write(l1_mem_write[I_MST]),
                .req_wdata(l1_mem_wdata[I_MST*LINE_WIDTH +: LINE_WIDTH]),
                .resp_rdata(l1_mem_rdata[I_MST*LINE_WIDTH +: LINE_WIDTH]),
                .resp_ready(l1_mem_ready[I_MST]),
                .m_AWID(m_AWID_i[I_MST*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_AWADDR(m_AWADDR_i[I_MST*ADDR_WIDTH +: ADDR_WIDTH]),
                .m_AWBURST(m_AWBURST_i[I_MST*AXI_BURST_WIDTH +: AXI_BURST_WIDTH]),
                .m_AWLEN(m_AWLEN_i[I_MST*AXI_LEN_WIDTH +: AXI_LEN_WIDTH]),
                .m_AWSIZE(m_AWSIZE_i[I_MST*AXI_SIZE_WIDTH +: AXI_SIZE_WIDTH]),
                .m_AWVALID(m_AWVALID_i[I_MST]),
                .m_AWREADY(m_AWREADY_o[I_MST]),
                .m_WDATA(m_WDATA_i[I_MST*LINE_WIDTH +: LINE_WIDTH]),
                .m_WLAST(m_WLAST_i[I_MST]),
                .m_WVALID(m_WVALID_i[I_MST]),
                .m_WREADY(m_WREADY_o[I_MST]),
                .m_BID(m_BID_o[I_MST*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_BRESP(m_BRESP_o[I_MST*AXI_RESP_WIDTH +: AXI_RESP_WIDTH]),
                .m_BVALID(m_BVALID_o[I_MST]),
                .m_BREADY(m_BREADY_i[I_MST]),
                .m_ARID(m_ARID_i[I_MST*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_ARADDR(m_ARADDR_i[I_MST*ADDR_WIDTH +: ADDR_WIDTH]),
                .m_ARBURST(m_ARBURST_i[I_MST*AXI_BURST_WIDTH +: AXI_BURST_WIDTH]),
                .m_ARLEN(m_ARLEN_i[I_MST*AXI_LEN_WIDTH +: AXI_LEN_WIDTH]),
                .m_ARSIZE(m_ARSIZE_i[I_MST*AXI_SIZE_WIDTH +: AXI_SIZE_WIDTH]),
                .m_ARVALID(m_ARVALID_i[I_MST]),
                .m_ARREADY(m_ARREADY_o[I_MST]),
                .m_RID(m_RID_o[I_MST*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_RDATA(m_RDATA_o[I_MST*LINE_WIDTH +: LINE_WIDTH]),
                .m_RRESP(m_RRESP_o[I_MST*AXI_RESP_WIDTH +: AXI_RESP_WIDTH]),
                .m_RLAST(m_RLAST_o[I_MST]),
                .m_RVALID(m_RVALID_o[I_MST]),
                .m_RREADY(m_RREADY_i[I_MST])
            );

            SimpleCacheToAxiMaster #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(LINE_WIDTH),
                .AXI_ID_WIDTH(AXI_ID_WIDTH),
                .AXI_LEN_WIDTH(AXI_LEN_WIDTH),
                .AXI_SIZE_WIDTH(AXI_SIZE_WIDTH),
                .AXI_BURST_WIDTH(AXI_BURST_WIDTH),
                .AXI_RESP_WIDTH(AXI_RESP_WIDTH),
                .MASTER_ID(D_MST)
            ) d_axi_master (
                .clk(clk),
                .reset(reset),
                .req_addr(l1_mem_addr[D_MST*ADDR_WIDTH +: ADDR_WIDTH]),
                .req_read(l1_mem_read[D_MST]),
                .req_write(l1_mem_write[D_MST]),
                .req_wdata(l1_mem_wdata[D_MST*LINE_WIDTH +: LINE_WIDTH]),
                .resp_rdata(l1_mem_rdata[D_MST*LINE_WIDTH +: LINE_WIDTH]),
                .resp_ready(l1_mem_ready[D_MST]),
                .m_AWID(m_AWID_i[D_MST*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_AWADDR(m_AWADDR_i[D_MST*ADDR_WIDTH +: ADDR_WIDTH]),
                .m_AWBURST(m_AWBURST_i[D_MST*AXI_BURST_WIDTH +: AXI_BURST_WIDTH]),
                .m_AWLEN(m_AWLEN_i[D_MST*AXI_LEN_WIDTH +: AXI_LEN_WIDTH]),
                .m_AWSIZE(m_AWSIZE_i[D_MST*AXI_SIZE_WIDTH +: AXI_SIZE_WIDTH]),
                .m_AWVALID(m_AWVALID_i[D_MST]),
                .m_AWREADY(m_AWREADY_o[D_MST]),
                .m_WDATA(m_WDATA_i[D_MST*LINE_WIDTH +: LINE_WIDTH]),
                .m_WLAST(m_WLAST_i[D_MST]),
                .m_WVALID(m_WVALID_i[D_MST]),
                .m_WREADY(m_WREADY_o[D_MST]),
                .m_BID(m_BID_o[D_MST*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_BRESP(m_BRESP_o[D_MST*AXI_RESP_WIDTH +: AXI_RESP_WIDTH]),
                .m_BVALID(m_BVALID_o[D_MST]),
                .m_BREADY(m_BREADY_i[D_MST]),
                .m_ARID(m_ARID_i[D_MST*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_ARADDR(m_ARADDR_i[D_MST*ADDR_WIDTH +: ADDR_WIDTH]),
                .m_ARBURST(m_ARBURST_i[D_MST*AXI_BURST_WIDTH +: AXI_BURST_WIDTH]),
                .m_ARLEN(m_ARLEN_i[D_MST*AXI_LEN_WIDTH +: AXI_LEN_WIDTH]),
                .m_ARSIZE(m_ARSIZE_i[D_MST*AXI_SIZE_WIDTH +: AXI_SIZE_WIDTH]),
                .m_ARVALID(m_ARVALID_i[D_MST]),
                .m_ARREADY(m_ARREADY_o[D_MST]),
                .m_RID(m_RID_o[D_MST*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_RDATA(m_RDATA_o[D_MST*LINE_WIDTH +: LINE_WIDTH]),
                .m_RRESP(m_RRESP_o[D_MST*AXI_RESP_WIDTH +: AXI_RESP_WIDTH]),
                .m_RLAST(m_RLAST_o[D_MST]),
                .m_RVALID(m_RVALID_o[D_MST]),
                .m_RREADY(m_RREADY_i[D_MST])
            );
        end
    endgenerate

    axi_interconnect #(
        .MST_AMT(L1_MASTER_AMT),
        .SLV_AMT(L2_SLV_AMT),
        .OUTSTANDING_AMT(8),
        .MST_WEIGHT({L1_MASTER_AMT{32'd1}}),
        .MST_ID_W(AXI_MST_ID_WIDTH),
        .SLV_ID_W(AXI_SLV_SEL_WIDTH),
        .DATA_WIDTH(LINE_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .TRANS_MST_ID_W(AXI_ID_WIDTH),
        .TRANS_SLV_ID_W(AXI_SLV_ID_WIDTH),
        .TRANS_BURST_W(AXI_BURST_WIDTH),
        .TRANS_DATA_LEN_W(AXI_LEN_WIDTH),
        .TRANS_DATA_SIZE_W(AXI_SIZE_WIDTH),
        .TRANS_WR_RESP_W(AXI_RESP_WIDTH),
        .SLV_ID_MSB_IDX(0),
        .SLV_ID_LSB_IDX(0)
    ) l1_interconnect (
        .ACLK_i(clk),
        .ARESETn_i(reset_n),
        .m_AWID_i(m_AWID_i),
        .m_AWADDR_i(m_AWADDR_i),
        .m_AWBURST_i(m_AWBURST_i),
        .m_AWLEN_i(m_AWLEN_i),
        .m_AWSIZE_i(m_AWSIZE_i),
        .m_AWVALID_i(m_AWVALID_i),
        .m_WDATA_i(m_WDATA_i),
        .m_WLAST_i(m_WLAST_i),
        .m_WVALID_i(m_WVALID_i),
        .m_BREADY_i(m_BREADY_i),
        .m_ARID_i(m_ARID_i),
        .m_ARADDR_i(m_ARADDR_i),
        .m_ARBURST_i(m_ARBURST_i),
        .m_ARLEN_i(m_ARLEN_i),
        .m_ARSIZE_i(m_ARSIZE_i),
        .m_ARVALID_i(m_ARVALID_i),
        .m_RREADY_i(m_RREADY_i),
        .s_AWREADY_i(s_AWREADY_i),
        .s_WREADY_i(s_WREADY_i),
        .s_BID_i(s_BID_i),
        .s_BRESP_i(s_BRESP_i),
        .s_BVALID_i(s_BVALID_i),
        .s_ARREADY_i(s_ARREADY_i),
        .s_RID_i(s_RID_i),
        .s_RDATA_i(s_RDATA_i),
        .s_RRESP_i(s_RRESP_i),
        .s_RLAST_i(s_RLAST_i),
        .s_RVALID_i(s_RVALID_i),
        .m_AWREADY_o(m_AWREADY_o),
        .m_WREADY_o(m_WREADY_o),
        .m_BID_o(m_BID_o),
        .m_BRESP_o(m_BRESP_o),
        .m_BVALID_o(m_BVALID_o),
        .m_ARREADY_o(m_ARREADY_o),
        .m_RID_o(m_RID_o),
        .m_RDATA_o(m_RDATA_o),
        .m_RRESP_o(m_RRESP_o),
        .m_RLAST_o(m_RLAST_o),
        .m_RVALID_o(m_RVALID_o),
        .s_AWID_o(s_AWID_o),
        .s_AWADDR_o(s_AWADDR_o),
        .s_AWBURST_o(s_AWBURST_o),
        .s_AWLEN_o(s_AWLEN_o),
        .s_AWSIZE_o(s_AWSIZE_o),
        .s_AWVALID_o(s_AWVALID_o),
        .s_WDATA_o(s_WDATA_o),
        .s_WLAST_o(s_WLAST_o),
        .s_WVALID_o(s_WVALID_o),
        .s_BREADY_o(s_BREADY_o),
        .s_ARID_o(s_ARID_o),
        .s_ARADDR_o(s_ARADDR_o),
        .s_ARBURST_o(s_ARBURST_o),
        .s_ARLEN_o(s_ARLEN_o),
        .s_ARSIZE_o(s_ARSIZE_o),
        .s_ARVALID_o(s_ARVALID_o),
        .s_RREADY_o(s_RREADY_o)
    );

    wire [ADDR_WIDTH-1:0] l2_cpu_addr;
    wire l2_cpu_read;
    wire l2_cpu_write;
    wire [LINE_WIDTH-1:0] l2_cpu_wdata;
    wire [LINE_WIDTH-1:0] l2_cpu_rdata;
    wire l2_cpu_ready;

    AxiSlaveToSimpleCache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(LINE_WIDTH),
        .AXI_ID_WIDTH(AXI_SLV_ID_WIDTH),
        .AXI_LEN_WIDTH(AXI_LEN_WIDTH),
        .AXI_SIZE_WIDTH(AXI_SIZE_WIDTH),
        .AXI_BURST_WIDTH(AXI_BURST_WIDTH),
        .AXI_RESP_WIDTH(AXI_RESP_WIDTH)
    ) l2_axi_slave (
        .clk(clk),
        .reset(reset),
        .s_AWID(s_AWID_o),
        .s_AWADDR(s_AWADDR_o),
        .s_AWBURST(s_AWBURST_o),
        .s_AWLEN(s_AWLEN_o),
        .s_AWSIZE(s_AWSIZE_o),
        .s_AWVALID(s_AWVALID_o),
        .s_AWREADY(s_AWREADY_i),
        .s_WDATA(s_WDATA_o),
        .s_WLAST(s_WLAST_o),
        .s_WVALID(s_WVALID_o),
        .s_WREADY(s_WREADY_i),
        .s_BID(s_BID_i),
        .s_BRESP(s_BRESP_i),
        .s_BVALID(s_BVALID_i),
        .s_BREADY(s_BREADY_o),
        .s_ARID(s_ARID_o),
        .s_ARADDR(s_ARADDR_o),
        .s_ARBURST(s_ARBURST_o),
        .s_ARLEN(s_ARLEN_o),
        .s_ARSIZE(s_ARSIZE_o),
        .s_ARVALID(s_ARVALID_o),
        .s_ARREADY(s_ARREADY_i),
        .s_RID(s_RID_i),
        .s_RDATA(s_RDATA_i),
        .s_RRESP(s_RRESP_i),
        .s_RLAST(s_RLAST_i),
        .s_RVALID(s_RVALID_i),
        .s_RREADY(s_RREADY_o),
        .cache_addr(l2_cpu_addr),
        .cache_read(l2_cpu_read),
        .cache_write(l2_cpu_write),
        .cache_wdata(l2_cpu_wdata),
        .cache_rdata(l2_cpu_rdata),
        .cache_ready(l2_cpu_ready)
    );

    SetAssociativeCache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .CPU_DATA_WIDTH(LINE_WIDTH),
        .READ_ONLY(1'b0),
        .LINE_WIDTH(LINE_WIDTH),
        .NUM_SETS(L2_NUM_SETS),
        .TAG_WIDTH(L2_TAG_WIDTH)
    ) shared_l2_cache (
        .clk(clk),
        .reset(reset),
        .cpu_addr(l2_cpu_addr),
        .cpu_read(l2_cpu_read),
        .cpu_write(l2_cpu_write),
        .cpu_wdata(l2_cpu_wdata),
        .cpu_rdata(l2_cpu_rdata),
        .cpu_ready(l2_cpu_ready),
        .mem_req_addr(dram_req_addr),
        .mem_req_read(dram_req_read),
        .mem_req_write(dram_req_write),
        .mem_req_wdata(dram_req_wdata),
        .mem_rdata(dram_rdata),
        .mem_ready(dram_ready),
        .error_out(),
        .snoop_en(1'b0),
        .snoop_addr('0),
        .store_committed(),
        .store_committed_addr()
    );

    CoherenceManager #(
        .NUM_CORES(NUM_CORES),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) coherence_manager (
        .clk(clk),
        .reset(reset),
        .dcache_store_valid(l1d_store_committed),
        .dcache_store_addr(l1d_store_committed_addr),
        .l1_invalidate_valid(l1d_snoop_en),
        .l1_invalidate_addr(l1d_snoop_addr)
    );

endmodule
