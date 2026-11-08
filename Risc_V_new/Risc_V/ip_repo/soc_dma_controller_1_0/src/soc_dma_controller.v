`timescale 1ns / 1ps

// Source-level DMA subsystem for the quad-core SoC.  It combines an APB4
// programming interface, mandatory pre/post cache maintenance, and a bounded
// burst AXI4 memory-to-memory datapath.  The module is independent of generated
// Vivado IP and can later be connected as one master of the system AXI fabric.
module soc_dma_controller #(
    parameter MAX_BURST_LEN = 16,
    parameter [31:0] TIMEOUT_CYCLES = 32'd1000000
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_APB:M_AXI, ASSOCIATED_RESET rst" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire        rst,
    input  wire        buffer_quiesced,

    output wire        cache_flush,
    input  wire        cache_flush_busy,
    input  wire        cache_flush_done,
    input  wire        cache_flush_error,

    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PADDR" *)
    input  wire [31:0] paddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PSEL" *)
    input  wire        psel,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PENABLE" *)
    input  wire        penable,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PWRITE" *)
    input  wire        pwrite,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PWDATA" *)
    input  wire [31:0] pwdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PSTRB" *)
    input  wire [3:0]  pstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PPROT" *)
    input  wire [2:0]  pprot,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PRDATA" *)
    output wire [31:0] prdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PREADY" *)
    output wire        pready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:apb:1.0 S_APB PSLVERR" *)
    output wire        pslverr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
    (* X_INTERFACE_PARAMETER = "PROTOCOL AXI4, DATA_WIDTH 32, ADDR_WIDTH 32, READ_WRITE_MODE READ_WRITE, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 16, SUPPORTS_NARROW_BURST 0" *)
    output wire [31:0] m_axi_araddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
    output wire [7:0]  m_axi_arlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
    output wire [2:0]  m_axi_arsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
    output wire [1:0]  m_axi_arburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
    output wire        m_axi_arvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
    input  wire        m_axi_arready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
    input  wire [31:0] m_axi_rdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
    input  wire [1:0]  m_axi_rresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
    input  wire        m_axi_rlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
    input  wire        m_axi_rvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
    output wire        m_axi_rready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
    output wire [31:0] m_axi_awaddr,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
    output wire [7:0]  m_axi_awlen,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
    output wire [2:0]  m_axi_awsize,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
    output wire [1:0]  m_axi_awburst,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
    output wire        m_axi_awvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
    input  wire        m_axi_awready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
    output wire [31:0] m_axi_wdata,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
    output wire [3:0]  m_axi_wstrb,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
    output wire        m_axi_wlast,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
    output wire        m_axi_wvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
    input  wire        m_axi_wready,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
    input  wire [1:0]  m_axi_bresp,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
    input  wire        m_axi_bvalid,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
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

    apb_dma_regs regs (
        .pclk(clk), .presetn(~rst),
        .paddr(paddr[5:0]), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .pstrb(pstrb), .pprot(pprot),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
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
