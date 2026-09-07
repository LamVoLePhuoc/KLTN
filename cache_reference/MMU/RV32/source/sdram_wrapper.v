module sdram_wrapper (
    // Clock and Reset
    input           clk,
    input           rst_n,
    
    // Write Address Channel (AW)
    input           AWVALID,
    output          AWREADY,
    input  [31:0]   AWADDR,
    input  [7:0]    AWLEN,
    input  [2:0]    AWSIZE,
    input  [1:0]    AWBURST,
    input  [3:0]    AWID,
    input  [2:0]    AWPROT,
    input  [3:0]    AWCACHE,
    input           AWLOCK,
    input  [3:0]    AWQOS,
    input  [3:0]    AWREGION,
    
    // Write Data Channel (W)
    input           WVALID,
    output          WREADY,
    input  [31:0]   WDATA,
    input  [3:0]    WSTRB,
    input           WLAST,
    input  [3:0]    WID,
    
    // Write Response Channel (B)
    output          BVALID,
    input           BREADY,
    output [1:0]    BRESP,
    output [3:0]    BID,
    
    // Read Address Channel (AR)
    input           ARVALID,
    output          ARREADY,
    input  [31:0]   ARADDR,
    input  [7:0]    ARLEN,
    input  [2:0]    ARSIZE,
    input  [1:0]    ARBURST,
    input  [3:0]    ARID,
    input  [2:0]    ARPROT,
    input  [3:0]    ARCACHE,
    input           ARLOCK,
    input  [3:0]    ARQOS,
    input  [3:0]    ARREGION,
    
    // Read Data Channel (R)
    output          RVALID,
    input           RREADY,
    output [31:0]   RDATA,
    output [1:0]    RRESP,
    output          RLAST,
    output [3:0]    RID
);

    // Signals connecting between Wrapper and Memory
    wire        mem_wen, mem_ren;
    wire [31:0] mem_addr, mem_wdata, mem_rdata;

    // Instantiate AXI-4 Wrapper
    if_slave axi_wrapper_inst (
        .clk(clk),
        .rst_n(rst_n),
        .AWVALID(AWVALID), .AWREADY(AWREADY), .AWADDR(AWADDR), .AWLEN(AWLEN),
        .AWSIZE(AWSIZE), .AWBURST(AWBURST), .AWID(AWID), .AWPROT(AWPROT),
        .AWCACHE(AWCACHE), .AWLOCK(AWLOCK), .AWQOS(AWQOS), .AWREGION(AWREGION),
        .WVALID(WVALID), .WREADY(WREADY), .WDATA(WDATA), .WSTRB(WSTRB),
        .WLAST(WLAST), .WID(WID),
        .BVALID(BVALID), .BREADY(BREADY), .BRESP(BRESP), .BID(BID),
        .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR), .ARLEN(ARLEN),
        .ARSIZE(ARSIZE), .ARBURST(ARBURST), .ARID(ARID), .ARPROT(ARPROT),
        .ARCACHE(ARCACHE), .ARLOCK(ARLOCK), .ARQOS(ARQOS), .ARREGION(ARREGION),
        .RVALID(RVALID), .RREADY(RREADY), .RDATA(RDATA), .RRESP(RRESP),
        .RLAST(RLAST), .RID(RID),
        .mem_wen(mem_wen), .mem_ren(mem_ren),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata)
    );

    // Instantiate Main Memory
    main_memory mem_inst (
        .clk(clk),
        .rst_n(rst_n),
        .addr(mem_addr),
        .wen(mem_wen),
        .ren(mem_ren),
        .wdata(mem_wdata),
        .rdata(mem_rdata)
    );

endmodule


module main_memory (
    input           clk,        // Clock
    input           rst_n,      // Reset (active low)
    input  [31:0]   addr,       // Address
    input           wen,        // Write enable
    input           ren,        // Read enable
    input  [31:0]   wdata,      // Write data
    output [31:0]   rdata       // Read data
);

    // Memory array: 1024 words, each 32-bit
    reg [31:0] mem [0:1023];
    
    // Synchronous write logic
    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset memory if needed (optional depending on application)
        end else if (wen) begin
            mem[addr[9:0]] <= wdata; // Use lower 10 bits of address
        end
    end
    
    // Read logic
    assign rdata = (ren) ? mem[addr[9:0]] : 32'b0;
endmodule
