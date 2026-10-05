module dual_top #(parameter NO_RESERV = 16) (
    input logic clk,
    input logic rst_n
);

    timeunit 1ns; timeprecision 1ps;

    // AXI-4 Write Address Channel signals
    wire [31:0] awaddr;    // Write address
    wire awvalid;          // Valid signal from Master
    wire awready;          // Ready signal from Slave
    wire [7:0] awlen;      // Burst length
    wire [2:0] awsize;     // Size per transfer
    wire [1:0] awburst;    // Burst type
    wire [3:0] awid;       // Transaction ID

    // AXI-4 Write Data Channel signals
    wire [255:0] wdata;    // Write data
    wire wvalid;           // Valid signal from Master
    wire wready;           // Ready signal from Slave
    wire [31:0] wstrb;     // Byte enable
    wire wlast;            // Last beat in burst
    wire [3:0] wid;        // Transaction ID

    // AXI-4 Write Response Channel signals
    wire bvalid;           // Valid response from Slave
    wire bready;           // Master ready to receive response
    wire [1:0] bresp;      // Response code
    wire [3:0] bid;        // Transaction ID

    // AXI-4 Read Address Channel signals
    wire [63:0] araddr;    // Read address 63->32: i-mem, 31->0: d-mem
    wire arvalid;          // Valid signal from Master
    wire arready;          // Ready signal from Slave
    wire [7:0] arlen;      // Burst length
    wire [2:0] arsize;     // Size per transfer
    wire [1:0] arburst;    // Burst type
    wire [3:0] arid;       // Transaction ID

    // AXI-4 Read Data Channel signals
    wire [511:0] rdata;    // Read data 511->256: i-mem, 255->0: d-mem
    wire rvalid;           // Valid signal from Slave
    wire rready;           // Master ready to receive data
    wire [1:0] rresp;      // Response code
    wire rlast;            // Last beat in burst
    wire [3:0] rid;        // Transaction ID

    dual_wrapper #(.NO_RESERV(NO_RESERV)) dual_core_inst (
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

    sdram_wrapper sdram_inst (
        .clk(clk),
        .rst_n(rst_n),
        // Write Address Channel
        .AWVALID(awvalid), .AWREADY(awready), .AWADDR(awaddr), .AWLEN(awlen), .AWSIZE(awsize), .AWBURST(awburst), .AWID(awid), .AWPROT('0), .AWCACHE('0), .AWLOCK('0), .AWQOS('0), .AWREGION('0),
        // Write Data Channel
        .WVALID(wvalid), .WREADY(wready), .WDATA(wdata), .WSTRB(wstrb), .WLAST(wlast), .WID(wid),
        // Write Response Channel
        .BVALID(bvalid), .BREADY(bready), .BRESP(bresp), .BID(bid),
        // Read Address Channel
        .ARVALID(arvalid), .ARREADY(arready), .ARADDR(araddr), .ARLEN(arlen), .ARSIZE(arsize), .ARBURST(arburst), .ARID(arid), .ARPROT('0), .ARCACHE('0), .ARLOCK('0), .ARQOS('0), .ARREGION('0),
        // Read Data Channel
        .RVALID(rvalid), .RREADY(rready), .RDATA(rdata), .RRESP(rresp), .RLAST(rlast), .RID(rid)
    );
    
endmodule: dual_top