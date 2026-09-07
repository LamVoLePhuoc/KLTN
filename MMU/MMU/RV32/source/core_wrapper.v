`timescale 1ps/1ps 
module core_wrapper (
    // System signals
    input           clk,
    input           rst_n,

    // AXI-4 Master Write Address Channel
    output          AWVALID,        // Valid signal for write address channel
    input           AWREADY,        // Ready signal from slave
    output [31:0]   AWADDR,         // Write address
    output [7:0]    AWLEN,          // Burst length
    output [2:0]    AWSIZE,         // Size of each beat (e.g., 32-bit, 256-bit)
    output [1:0]    AWBURST,        // Burst type (INCR, WRAP, FIXED)
    output [3:0]    AWID,           // Write transaction ID

    // AXI-4 Master Write Data Channel
    output          WVALID,         // Valid signal for write data channel
    input           WREADY,         // Ready signal from slave
    output [31:0]  WDATA,          // Write data (example: 256-bit)
    output [3:0]   WSTRB,          // Byte strobe (enables writing per byte)
    output          WLAST,          // Indicates the last beat in the burst
    output [3:0]    WID,            // Write data ID

    // AXI-4 Master Write Response Channel
    input           BVALID,         // Valid signal from slave
    output          BREADY,         // Ready signal from master
    input  [1:0]    BRESP,          // Response code (OKAY, EXOKAY, SLVERR, DECERR)
    input  [3:0]    BID,            // Response ID

    // AXI-4 Master Read Address Channel
    output          ARVALID,        // Valid signal for read address channel
    input           ARREADY,        // Ready signal from slave
    output [31:0]   ARADDR,         // Read address
    output [7:0]    ARLEN,          // Burst length
    output [2:0]    ARSIZE,         // Size of each beat
    output [1:0]    ARBURST,        // Burst type
    output [3:0]    ARID,           // Read transaction ID

    // AXI-4 Master Read Data Channel
    input           RVALID,         // Valid signal from slave
    output          RREADY,         // Ready signal from master
    input  [31:0]  RDATA,          // Read data (example: 256-bit)
    input  [1:0]    RRESP,          // Response code
    input           RLAST,          // Indicates the last beat in the burst
    input  [3:0]    RID             // Read data ID
);

    // Internal signals connecting RV32I Core and axi4_master_wrapper
    wire [31:0]   imem_req_addr;    // i-mem request address
    wire          imem_req_read;    // i-mem read request
    wire          imem_req_write;   // i-mem write request
    wire [255:0]  imem_req_wdata;   // i-mem write data
    wire [255:0]  imem_rdata;       // i-mem read data
    wire          imem_ready;       // i-mem ready signal

    wire [31:0]   dmem_req_addr;    // d-mem request address
    wire          dmem_req_read;    // d-mem read request
    wire          dmem_req_write;   // d-mem write request
    wire [255:0]  dmem_req_wdata;   // d-mem write data
    wire [255:0]  dmem_rdata;       // d-mem read data
    wire          dmem_ready;       // d-mem ready signal

    // Instantiate RV32I Core
    rv32i core (
        .clk(clk),
        .rst_n(rst_n),
        // i-mem interface
        .imem_rdata(imem_rdata),
        .imem_ready(imem_ready),
        .imem_req_addr(imem_req_addr),
        .imem_req_read(imem_req_read),
        .imem_req_write(imem_req_write),
        .imem_req_wdata(imem_req_wdata),
        // d-mem interface
        .dmem_rdata(dmem_rdata),
        .dmem_ready(dmem_ready),
        .dmem_req_addr(dmem_req_addr),
        .dmem_req_read(dmem_req_read),
        .dmem_req_write(dmem_req_write),
        .dmem_req_wdata(dmem_req_wdata)
    );

    // Instantiate axi4_master_wrapper
    if_master axi_wrapper (
        .clk(clk),
        .rst_n(rst_n),
        // i-mem interface from RV32I Core
        .imem_req_addr(imem_req_addr),
        .imem_req_read(imem_req_read),
        .imem_req_write(imem_req_write),
        .imem_req_wdata(imem_req_wdata),
        .imem_rdata(imem_rdata),
        .imem_ready(imem_ready),
        // d-mem interface from RV32I Core
        .dmem_req_addr(dmem_req_addr),
        .dmem_req_read(dmem_req_read),
        .dmem_req_write(dmem_req_write),
        .dmem_req_wdata(dmem_req_wdata),
        .dmem_rdata(dmem_rdata),
        .dmem_ready(dmem_ready),
        // // AXI-4 Master Write Channel
        // .AWVALID(AWVALID), .AWREADY(AWREADY), .AWADDR(AWADDR), .AWLEN(AWLEN), .AWSIZE(AWSIZE), .AWBURST(AWBURST),.AWID(AWID),
        // .WVALID(WVALID), .WREADY(WREADY), .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST), .WID(WID),
        // .BVALID(BVALID), .BREADY(BREADY), .BRESP(BRESP), .BID(BID),
        // // AXI-4 Master Read Channel
        // .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR), .ARLEN(ARLEN), .ARSIZE(ARSIZE), .ARBURST(ARBURST), .ARID(ARID),
        // .RVALID(RVALID), .RREADY(RREADY), .RDATA(RDATA), .RRESP(RRESP), .RLAST(RLAST), .RID(RID)
        
        // Write Address Channel
        .AWVALID(AWVALID), .AWREADY(AWREADY), .AWADDR(AWADDR), .AWLEN(AWLEN), .AWSIZE(AWSIZE), .AWBURST(AWBURST), .AWID(AWID),
        // Write Data Channel
        .WVALID(WVALID), .WREADY(WREADY), .WDATA(WDATA), .WSTRB(WSTRB), .WLAST(WLAST), .WID(WID),
        // Write Response Channel
        .BVALID(BVALID), .BREADY(BREADY), .BRESP(BRESP), .BID(BID),
        // Read Address Channel
        .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR), .ARLEN(ARLEN), .ARSIZE(ARSIZE), .ARBURST(ARBURST), .ARID(ARID),
        // Read Data Channel
        .RVALID(RVALID), .RREADY(RREADY), .RDATA(RDATA), .RRESP(RRESP), .RLAST(RLAST), .RID(RID)
    );

endmodule
