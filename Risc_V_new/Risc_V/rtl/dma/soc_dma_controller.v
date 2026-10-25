`timescale 1ns / 1ps

// Source-level DMA subsystem for the quad-core SoC.  It combines an AXI4-Lite
// programming interface, mandatory pre/post cache maintenance, and a bounded
// burst AXI4 memory-to-memory datapath.  The module is independent of generated
// Vivado IP and can later be connected as one master of the system AXI fabric.
module soc_dma_controller #(
    parameter MAX_BURST_LEN = 16,
    parameter [31:0] TIMEOUT_CYCLES = 32'd1000000
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        buffer_quiesced,

    output wire        cache_flush,
    input  wire        cache_flush_busy,
    input  wire        cache_flush_done,
    input  wire        cache_flush_error,

    input  wire [5:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [5:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    output wire [31:0] m_axi_araddr,
    output wire [7:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire        m_axi_arvalid,
    input  wire        m_axi_arready,
    input  wire [31:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,
    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [31:0] m_axi_wdata,
    output wire [3:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,

    output wire        status_busy,
    output wire        status_done,
    output wire        status_error,
    output wire [2:0]  status_error_code
);
    wire request_valid;
    wire request_ready;
    wire [31:0] request_src_addr;
    wire [31:0] request_dst_addr;
    wire [31:0] request_length_bytes;
    wire coord_done;
    wire coord_error;
    wire [2:0] coord_error_code;
    wire coordinator_busy;

    wire dma_cmd_valid;
    wire dma_cmd_ready;
    wire [31:0] dma_cmd_src_addr;
    wire [31:0] dma_cmd_dst_addr;
    wire [31:0] dma_cmd_length_bytes;
    wire dma_busy;
    wire dma_done;
    wire dma_error;
    wire dma_progress;

    // A software start waiting for buffer_quiesced is already an active DMA
    // operation from the programming interface's perspective.
    assign status_busy = coordinator_busy | request_valid;

    axi_lite_dma_regs regs (
        .clk(clk), .rst(rst),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .request_valid(request_valid), .request_ready(request_ready),
        .request_src_addr(request_src_addr), .request_dst_addr(request_dst_addr),
        .request_length_bytes(request_length_bytes),
        .status_busy(status_busy), .status_done_pulse(coord_done),
        .status_error(coord_error), .status_error_code(coord_error_code),
        .done_sticky(status_done), .error_sticky(status_error),
        .error_code_sticky(status_error_code)
    );

    dma_cache_coordinator #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) coordinator (
        .clk(clk), .rst(rst),
        .request_valid(request_valid), .request_ready(request_ready),
        .request_src_addr(request_src_addr), .request_dst_addr(request_dst_addr),
        .request_length_bytes(request_length_bytes),
        .buffer_quiesced(buffer_quiesced),
        .cache_flush(cache_flush), .cache_flush_busy(cache_flush_busy),
        .cache_flush_done(cache_flush_done), .cache_flush_error(cache_flush_error),
        .dma_cmd_valid(dma_cmd_valid), .dma_cmd_ready(dma_cmd_ready),
        .dma_cmd_src_addr(dma_cmd_src_addr), .dma_cmd_dst_addr(dma_cmd_dst_addr),
        .dma_cmd_length_bytes(dma_cmd_length_bytes),
        .dma_busy(dma_busy), .dma_done(dma_done), .dma_error(dma_error),
        .dma_progress(dma_progress),
        .busy(coordinator_busy), .done(coord_done), .error(coord_error),
        .error_code(coord_error_code)
    );

    axi_memcpy_dma #(.ADDR_WIDTH(32), .DATA_WIDTH(32),
                     .MAX_BURST_LEN(MAX_BURST_LEN)) engine (
        .clk(clk), .rst(rst),
        .cmd_valid(dma_cmd_valid), .cmd_ready(dma_cmd_ready),
        .cmd_src_addr(dma_cmd_src_addr), .cmd_dst_addr(dma_cmd_dst_addr),
        .cmd_length_bytes(dma_cmd_length_bytes),
        .busy(dma_busy), .done(dma_done), .error(dma_error),
        .progress(dma_progress),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready)
    );
endmodule
