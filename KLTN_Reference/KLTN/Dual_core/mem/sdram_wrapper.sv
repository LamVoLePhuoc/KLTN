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
    input  [255:0]  WDATA,
    input  [31:0]   WSTRB,
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
    input  [63:0]   ARADDR,  // 63->32: i-mem, 31->0: d-mem
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
    output [511:0]  RDATA,  // 511->256: i-mem, 255->0: d-mem
    output [1:0]    RRESP,
    output          RLAST,
    output [3:0]    RID
);

    timeunit 1ns; timeprecision 1ps;	

    // Signals connecting between Wrapper and Memory
    logic         i_mem_ren;
    logic [31:0]  i_mem_addr;
    logic [255:0] i_mem_rdata;
    // Connection to D Main Memory
    logic         d_mem_wen;
    logic         d_mem_ren;
    logic [31:0]  d_mem_addr;
    logic [255:0] d_mem_wdata;
    logic [255:0] d_mem_rdata;

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
        // Connection to I Main Memory
        .i_mem_ren(i_mem_ren),
        .i_mem_addr(i_mem_addr),
        .i_mem_rdata(i_mem_rdata),
        // Connection to D Main Memory
        .d_mem_wen(d_mem_wen),
        .d_mem_ren(d_mem_ren),
        .d_mem_addr(d_mem_addr),
        .d_mem_wdata(d_mem_wdata),
        .d_mem_rdata(d_mem_rdata)
    );

    // Instantiate Main Memory
    i_main_memory i_mem_inst (
        .clk(clk),
        .rst_n(rst_n),
        .addr(i_mem_addr),
        .wen(1'b0),
        .ren(i_mem_ren),
        .wdata(32'd0),
        .rdata(i_mem_rdata)
    );

    d_main_memory d_mem_inst (
        .clk(clk),
        .rst_n(rst_n),
        .addr(d_mem_addr),
        .wen(d_mem_wen),
        .ren(d_mem_ren),
        .wdata(d_mem_wdata),
        .rdata(d_mem_rdata)
    );

endmodule


module i_main_memory (
    input           clk,        // Clock
    input           rst_n,      // Reset (active low)
    input  [31:0]   addr,       // Address
    input           wen,        // Write enable
    input           ren,        // Read enable
    input  [31:0]   wdata,      // Write data
    output [255:0]  rdata       // Read data
);

    timeunit 1ns; timeprecision 1ps;	

    // Memory array: 1024 words, each 32-bit
    (* ram_style = "block" *) reg [31:0] mem [0:1023];

    initial $readmemh("../mem/ALL_test.mem", mem);

    // Synchronous write logic
    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset memory if needed (optional depending on application)
        end else if (wen) begin
            mem[addr[9:0]] <= wdata; // Use lower 10 bits of address
        end
    end
    
    // Read logic
    assign rdata = ren ? {
    mem[addr[9:2] + 0],
    mem[addr[9:2] + 1],
    mem[addr[9:2] + 2],
    mem[addr[9:2] + 3],
    mem[addr[9:2] + 4],
    mem[addr[9:2] + 5],
    mem[addr[9:2] + 6],
    mem[addr[9:2] + 7]} : 256'b0;
endmodule

module d_main_memory (
    input           clk,        // Clock
    input           rst_n,      // Reset (active low)
    input  [31:0]   addr,       // Address
    input           wen,        // Write enable
    input           ren,        // Read enable
    input  [255:0]  wdata,      // Write data
    output [255:0]  rdata       // Read data
);

    timeunit 1ns; timeprecision 1ps;	

    // Memory array: 1024 words, each 64-bit
    (* ram_style = "block" *) reg [63:0] mem [0:1023];

    // Synchronous write logic
    always @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < 1024; i = i + 1) begin
                mem[i] <= 64'd0;
            end
        end 
        else if (wen) begin
            mem[addr[11:3] + 0] <= wdata[255:192]; // Use lower 10 bits of address
            mem[addr[11:3] + 1] <= wdata[191:128];
            mem[addr[11:3] + 2] <= wdata[127:64];
            mem[addr[11:3] + 3] <= wdata[63:0];
        end
    end
    
    // Read logic
    assign rdata = ren ? {
    mem[addr[11:3] + 0],
    mem[addr[11:3] + 1],
    mem[addr[11:3] + 2],
    mem[addr[11:3] + 3] } : 256'b0;
endmodule