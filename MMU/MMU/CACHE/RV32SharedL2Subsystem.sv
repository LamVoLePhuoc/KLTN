module RV32SharedL2Subsystem #(
    parameter int NUM_PORTS          = 8,
    parameter int ADDR_WIDTH         = 32,
    parameter int LINE_WIDTH         = 256,
    parameter int L2_NUM_SETS        = 8192,
    parameter int AXI_ID_WIDTH       = 5,
    parameter int AXI_MST_ID_WIDTH   = $clog2(NUM_PORTS),
    parameter int AXI_SLV_SEL_WIDTH  = 1,
    parameter int AXI_SLV_ID_WIDTH   = AXI_ID_WIDTH + AXI_MST_ID_WIDTH,
    parameter int AXI_LEN_WIDTH      = 3,
    parameter int AXI_SIZE_WIDTH     = 3,
    parameter int AXI_BURST_WIDTH    = 2,
    parameter int AXI_RESP_WIDTH     = 2
) (
    input  wire                               clk,
    input  wire                               reset_n,

    input  wire [NUM_PORTS*ADDR_WIDTH-1:0]   l1_req_addr,
    input  wire [NUM_PORTS-1:0]              l1_req_read,
    input  wire [NUM_PORTS-1:0]              l1_req_write,
    input  wire [NUM_PORTS*LINE_WIDTH-1:0]   l1_req_wdata,
    output wire [NUM_PORTS*LINE_WIDTH-1:0]   l1_resp_rdata,
    output wire [NUM_PORTS-1:0]              l1_resp_ready,

    output wire [ADDR_WIDTH-1:0]             dram_req_addr,
    output wire                              dram_req_read,
    output wire                              dram_req_write,
    output wire [LINE_WIDTH-1:0]             dram_req_wdata,
    input  wire [LINE_WIDTH-1:0]             dram_rdata,
    input  wire                              dram_ready
);

    timeunit 1ns; timeprecision 1ps;

    localparam int L2_SLV_AMT = 1;
    localparam int L2_TAG_WIDTH = ADDR_WIDTH - $clog2(L2_NUM_SETS) - $clog2(LINE_WIDTH / 8);

    wire reset;
    assign reset = ~reset_n;

    wire [NUM_PORTS*AXI_ID_WIDTH-1:0]      m_AWID_i;
    wire [NUM_PORTS*ADDR_WIDTH-1:0]        m_AWADDR_i;
    wire [NUM_PORTS*AXI_BURST_WIDTH-1:0]   m_AWBURST_i;
    wire [NUM_PORTS*AXI_LEN_WIDTH-1:0]     m_AWLEN_i;
    wire [NUM_PORTS*AXI_SIZE_WIDTH-1:0]    m_AWSIZE_i;
    wire [NUM_PORTS-1:0]                   m_AWVALID_i;
    wire [NUM_PORTS*LINE_WIDTH-1:0]        m_WDATA_i;
    wire [NUM_PORTS-1:0]                   m_WLAST_i;
    wire [NUM_PORTS-1:0]                   m_WVALID_i;
    wire [NUM_PORTS-1:0]                   m_BREADY_i;
    wire [NUM_PORTS*AXI_ID_WIDTH-1:0]      m_ARID_i;
    wire [NUM_PORTS*ADDR_WIDTH-1:0]        m_ARADDR_i;
    wire [NUM_PORTS*AXI_BURST_WIDTH-1:0]   m_ARBURST_i;
    wire [NUM_PORTS*AXI_LEN_WIDTH-1:0]     m_ARLEN_i;
    wire [NUM_PORTS*AXI_SIZE_WIDTH-1:0]    m_ARSIZE_i;
    wire [NUM_PORTS-1:0]                   m_ARVALID_i;
    wire [NUM_PORTS-1:0]                   m_RREADY_i;

    wire [NUM_PORTS-1:0]                   m_AWREADY_o;
    wire [NUM_PORTS-1:0]                   m_WREADY_o;
    wire [NUM_PORTS*AXI_ID_WIDTH-1:0]      m_BID_o;
    wire [NUM_PORTS*AXI_RESP_WIDTH-1:0]    m_BRESP_o;
    wire [NUM_PORTS-1:0]                   m_BVALID_o;
    wire [NUM_PORTS-1:0]                   m_ARREADY_o;
    wire [NUM_PORTS*AXI_ID_WIDTH-1:0]      m_RID_o;
    wire [NUM_PORTS*LINE_WIDTH-1:0]        m_RDATA_o;
    wire [NUM_PORTS*AXI_RESP_WIDTH-1:0]    m_RRESP_o;
    wire [NUM_PORTS-1:0]                   m_RLAST_o;
    wire [NUM_PORTS-1:0]                   m_RVALID_o;

    wire [AXI_SLV_ID_WIDTH-1:0]            s_AWID_o;
    wire [ADDR_WIDTH-1:0]                  s_AWADDR_o;
    wire [AXI_BURST_WIDTH-1:0]             s_AWBURST_o;
    wire [AXI_LEN_WIDTH-1:0]               s_AWLEN_o;
    wire [AXI_SIZE_WIDTH-1:0]              s_AWSIZE_o;
    wire                                   s_AWVALID_o;
    wire                                   s_AWREADY_i;
    wire [LINE_WIDTH-1:0]                  s_WDATA_o;
    wire                                   s_WLAST_o;
    wire                                   s_WVALID_o;
    wire                                   s_WREADY_i;
    wire [AXI_SLV_ID_WIDTH-1:0]            s_BID_i;
    wire [AXI_RESP_WIDTH-1:0]              s_BRESP_i;
    wire                                   s_BVALID_i;
    wire                                   s_BREADY_o;
    wire [AXI_SLV_ID_WIDTH-1:0]            s_ARID_o;
    wire [ADDR_WIDTH-1:0]                  s_ARADDR_o;
    wire [AXI_BURST_WIDTH-1:0]             s_ARBURST_o;
    wire [AXI_LEN_WIDTH-1:0]               s_ARLEN_o;
    wire [AXI_SIZE_WIDTH-1:0]              s_ARSIZE_o;
    wire                                   s_ARVALID_o;
    wire                                   s_ARREADY_i;
    wire [AXI_SLV_ID_WIDTH-1:0]            s_RID_i;
    wire [LINE_WIDTH-1:0]                  s_RDATA_i;
    wire [AXI_RESP_WIDTH-1:0]              s_RRESP_i;
    wire                                   s_RLAST_i;
    wire                                   s_RVALID_i;
    wire                                   s_RREADY_o;

    genvar port_idx;
    generate
        for (port_idx = 0; port_idx < NUM_PORTS; port_idx = port_idx + 1) begin : gen_l1_axi
            SimpleCacheToAxiMaster #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .DATA_WIDTH(LINE_WIDTH),
                .AXI_ID_WIDTH(AXI_ID_WIDTH),
                .AXI_LEN_WIDTH(AXI_LEN_WIDTH),
                .AXI_SIZE_WIDTH(AXI_SIZE_WIDTH),
                .AXI_BURST_WIDTH(AXI_BURST_WIDTH),
                .AXI_RESP_WIDTH(AXI_RESP_WIDTH),
                .MASTER_ID(port_idx)
            ) l1_axi_master (
                .clk(clk),
                .reset(reset),
                .req_addr(l1_req_addr[port_idx*ADDR_WIDTH +: ADDR_WIDTH]),
                .req_read(l1_req_read[port_idx]),
                .req_write(l1_req_write[port_idx]),
                .req_wdata(l1_req_wdata[port_idx*LINE_WIDTH +: LINE_WIDTH]),
                .resp_rdata(l1_resp_rdata[port_idx*LINE_WIDTH +: LINE_WIDTH]),
                .resp_ready(l1_resp_ready[port_idx]),
                .m_AWID(m_AWID_i[port_idx*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_AWADDR(m_AWADDR_i[port_idx*ADDR_WIDTH +: ADDR_WIDTH]),
                .m_AWBURST(m_AWBURST_i[port_idx*AXI_BURST_WIDTH +: AXI_BURST_WIDTH]),
                .m_AWLEN(m_AWLEN_i[port_idx*AXI_LEN_WIDTH +: AXI_LEN_WIDTH]),
                .m_AWSIZE(m_AWSIZE_i[port_idx*AXI_SIZE_WIDTH +: AXI_SIZE_WIDTH]),
                .m_AWVALID(m_AWVALID_i[port_idx]),
                .m_AWREADY(m_AWREADY_o[port_idx]),
                .m_WDATA(m_WDATA_i[port_idx*LINE_WIDTH +: LINE_WIDTH]),
                .m_WLAST(m_WLAST_i[port_idx]),
                .m_WVALID(m_WVALID_i[port_idx]),
                .m_WREADY(m_WREADY_o[port_idx]),
                .m_BID(m_BID_o[port_idx*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_BRESP(m_BRESP_o[port_idx*AXI_RESP_WIDTH +: AXI_RESP_WIDTH]),
                .m_BVALID(m_BVALID_o[port_idx]),
                .m_BREADY(m_BREADY_i[port_idx]),
                .m_ARID(m_ARID_i[port_idx*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_ARADDR(m_ARADDR_i[port_idx*ADDR_WIDTH +: ADDR_WIDTH]),
                .m_ARBURST(m_ARBURST_i[port_idx*AXI_BURST_WIDTH +: AXI_BURST_WIDTH]),
                .m_ARLEN(m_ARLEN_i[port_idx*AXI_LEN_WIDTH +: AXI_LEN_WIDTH]),
                .m_ARSIZE(m_ARSIZE_i[port_idx*AXI_SIZE_WIDTH +: AXI_SIZE_WIDTH]),
                .m_ARVALID(m_ARVALID_i[port_idx]),
                .m_ARREADY(m_ARREADY_o[port_idx]),
                .m_RID(m_RID_o[port_idx*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_RDATA(m_RDATA_o[port_idx*LINE_WIDTH +: LINE_WIDTH]),
                .m_RRESP(m_RRESP_o[port_idx*AXI_RESP_WIDTH +: AXI_RESP_WIDTH]),
                .m_RLAST(m_RLAST_o[port_idx]),
                .m_RVALID(m_RVALID_o[port_idx]),
                .m_RREADY(m_RREADY_i[port_idx])
            );
        end
    endgenerate

    axi_interconnect #(
        .MST_AMT(NUM_PORTS),
        .SLV_AMT(L2_SLV_AMT),
        .OUTSTANDING_AMT(8),
        .MST_WEIGHT({NUM_PORTS{32'd1}}),
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
    ) l1_to_l2_interconnect (
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
        .error_out()
    );

endmodule
