`timescale 1ns/1ps
module soc (
    input clk,      // System clock
    input rst_n     // Active-low reset
);

    // AXI-4 Write Address Channel signals
    wire [31:0] awaddr;    // Write address
    wire awvalid;          // Valid signal from Master
    wire awready;          // Ready signal from Slave
    wire [7:0] awlen;      // Burst length
    wire [2:0] awsize;     // Size per transfer
    wire [1:0] awburst;    // Burst type
    wire [3:0] awid;       // Transaction ID

    // AXI-4 Write Data Channel signals
    wire [31:0] wdata;    // Write data
    wire wvalid;           // Valid signal from Master
    wire wready;           // Ready signal from Slave
    wire [3:0] wstrb;     // Byte enable
    wire wlast;            // Last beat in burst
    wire [3:0] wid;        // Transaction ID

    // AXI-4 Write Response Channel signals
    wire bvalid;           // Valid response from Slave
    wire bready;           // Master ready to receive response
    wire [1:0] bresp;      // Response code
    wire [3:0] bid;        // Transaction ID

    // AXI-4 Read Address Channel signals
    wire [31:0] araddr;    // Read address
    wire arvalid;          // Valid signal from Master
    wire arready;          // Ready signal from Slave
    wire [7:0] arlen;      // Burst length
    wire [2:0] arsize;     // Size per transfer
    wire [1:0] arburst;    // Burst type
    wire [3:0] arid;       // Transaction ID

    // AXI-4 Read Data Channel signals
    wire [31:0] rdata;    // Read data
    wire rvalid;           // Valid signal from Slave
    wire rready;           // Master ready to receive data
    wire [1:0] rresp;      // Response code
    wire rlast;            // Last beat in burst
    wire [3:0] rid;        // Transaction ID

    // Instantiate core_wrapper module (AXI-4 Master)
    core_wrapper core_inst (
        .clk(clk),
        .rst_n(rst_n),
        // Write Address Channel
        .AWVALID(awvalid), .AWREADY(awready), .AWADDR(awaddr), .AWLEN(awlen), .AWSIZE(awsize), .AWBURST(awburst), .AWID(awid),
        // Write Data Channel
        .WVALID(wvalid), .WREADY(wready), .WDATA(wdata), .WSTRB(wstrb), .WLAST(wlast), .WID(wid),
        // Write Response Channel
        .BVALID(bvalid), .BREADY(bready), .BRESP(bresp), .BID(bid),
        // Read Address Channel
        .ARVALID(arvalid), .ARREADY(arready), .ARADDR(araddr), .ARLEN(arlen), .ARSIZE(arsize), .ARBURST(arburst), .ARID(arid),
        // Read Data Channel
        .RVALID(rvalid), .RREADY(rready), .RDATA(rdata), .RRESP(rresp), .RLAST(rlast), .RID(rid)
    );

    // Instantiate memory module (AXI-4 Slave)
    AXI_Interconnect interconnect_inst(
        .ACLK(clk),
        .ARESETN(rst_n),
        // Write Address Channel
        .m0_AWID(awid), .m0_AWADDR(awaddr), .m0_AWLEN(awlen), .m0_AWSIZE(awsize), .m0_AWBURST(awburst), .m0_AWLOCK(1'b0),
        .m0_AWCACHE(4'b0), .m0_AWREGION(4'b0), .m0_AWUSER(1'b0), m0_AWVALID(awvalid), .m0_AWREADY(awready),
        // Write Data Channel
        .m0_WID(wid), .m0_WDATA(wdata), .m0_WSTRB(wstrb), .m0_WLAST(wlast), m0_WUSER(1'b0), m0_WVALID(wvalid), .m0_WREADY(wready),
        // Write Response Channel
        .m0_BVALID(bvalid), .m0_BREADY(bready),
        // Read Address Channel
        .m0_ARID(arid), .m0_ARADDR(araddr), .m0_ARLEN(arlen), .m0_ARSIZE(arsize), .m0_ARBURST(arburst), .m0_ARLOCK(1'b0),
        .m0_ARCACHE(4'b0), .m0_ARREGION(4'b0), .m0_ARUSER(1'b0), m0_ARVALID(arvalid), .m0_ARREADY(arready),
        // Read Data Channel
        .m0_RVALID(rvalid), .m0_RREADY(rready),
        .s0_AWVALID(awvalid), .s0_AWREADY(awready), .s0_WVALLID(wvalid), .s0_BID(bid), .s0_BRESP(bresp), .s0_BUSER(1'b0),
        .s0_BVALID(bvalid), .s0_BREADY(bready), .s0_RID(rid), .s0_RDATA(rdata), .s0_RRESP(rresp), .s0_RLAST(rlast), s0_RUSER(1'b0),
        .s0_RVALID(rvalid), .s0_RREADY(rready)
    );

    // Instantiate sdram_wrapper module (AXI-4 Slave)
    sdram_wrapper sdram_inst (
        .clk(clk),
        .rst_n(rst_n),
        // Write Address Channel
        .AWVALID(awvalid), .AWREADY(awready), .AWADDR(awaddr), .AWLEN(awlen), .AWSIZE(awsize), .AWBURST(awburst), .AWID(awid),
        // Write Data Channel
        .WVALID(wvalid), .WREADY(wready), .WDATA(wdata), .WSTRB(wstrb), .WLAST(wlast), .WID(wid),
        // Write Response Channel
        .BVALID(bvalid), .BREADY(bready), .BRESP(bresp), .BID(bid),
        // Read Address Channel
        .ARVALID(arvalid), .ARREADY(arready), .ARADDR(araddr), .ARLEN(arlen), .ARSIZE(arsize), .ARBURST(arburst), .ARID(arid),
        // Read Data Channel
        .RVALID(rvalid), .RREADY(rready), .RDATA(rdata), .RRESP(rresp), .RLAST(rlast), .RID(rid)
    );

endmodule
