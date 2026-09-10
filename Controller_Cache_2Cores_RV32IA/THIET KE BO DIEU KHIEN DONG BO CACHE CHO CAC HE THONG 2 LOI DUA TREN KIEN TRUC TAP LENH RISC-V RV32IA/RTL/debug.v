`timescale 1 ns / 1 ps

	module debug #(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32
	,   parameter integer C_S00_AXI_ADDR_WIDTH	= 4
	)
	(
		// Users to add ports here
        output                                      o_debug_core_sel
    ,   output  [4:0]                               o_debug_reg_addr
    ,   output                                      o_debug_ren
    ,   input   [31:0]                              i_debug_reg_data
		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
	,   input                                       s00_axi_aclk
	,   input                                       s00_axi_aresetn
	
    ,   input   [C_S00_AXI_ADDR_WIDTH-1 : 0]        s00_axi_araddr
	,   input   [2 : 0]                             s00_axi_arprot
	,   input                                       s00_axi_arvalid
	,   output                                      s00_axi_arready

	,   input   [C_S00_AXI_ADDR_WIDTH-1 : 0]        s00_axi_awaddr
	,   input   [2 : 0]                             s00_axi_awprot
	,   input                                       s00_axi_awvalid
	,   output                                      s00_axi_awready

	,   input   [C_S00_AXI_DATA_WIDTH-1 : 0]        s00_axi_wdata
	,   input   [(C_S00_AXI_DATA_WIDTH/8)-1 : 0]    s00_axi_wstrb
	,   input                                       s00_axi_wvalid
	,   output                                      s00_axi_wready

	,   output  [1 : 0]                             s00_axi_bresp
	,   output                                      s00_axi_bvalid
	,   input                                       s00_axi_bready

	,   output  [C_S00_AXI_DATA_WIDTH-1 : 0]        s00_axi_rdata
	,   output  [1 : 0]                             s00_axi_rresp
	,   output                                      s00_axi_rvalid
	,   input                                       s00_axi_rready
	);
// Instantiation of Axi Bus Interface S00_AXI
	axi_slave_if # ( 
		.C_S_AXI_DATA_WIDTH (C_S00_AXI_DATA_WIDTH)
	,   .C_S_AXI_ADDR_WIDTH (C_S00_AXI_ADDR_WIDTH)
	) axi_slave_if_S00_inst (
        .o_debug_core_sel   (o_debug_core_sel)
    ,   .o_debug_reg_addr   (o_debug_reg_addr)
    ,   .o_debug_ren        (o_debug_ren)
    ,   .i_debug_reg_data   (i_debug_reg_data)

	,	.S_AXI_ACLK         (s00_axi_aclk)
	,   .S_AXI_ARESETN      (s00_axi_aresetn)
	,   .S_AXI_AWADDR       (s00_axi_awaddr)
	,   .S_AXI_AWPROT       (s00_axi_awprot)
	,   .S_AXI_AWVALID      (s00_axi_awvalid)
	,   .S_AXI_AWREADY      (s00_axi_awready)
	,   .S_AXI_WDATA        (s00_axi_wdata)
	,   .S_AXI_WSTRB        (s00_axi_wstrb)
	,   .S_AXI_WVALID       (s00_axi_wvalid)
	,   .S_AXI_WREADY       (s00_axi_wready)
	,   .S_AXI_BRESP        (s00_axi_bresp)
	,   .S_AXI_BVALID       (s00_axi_bvalid)
	,   .S_AXI_BREADY       (s00_axi_bready)
	,   .S_AXI_ARADDR       (s00_axi_araddr)
	,   .S_AXI_ARPROT       (s00_axi_arprot)
	,   .S_AXI_ARVALID      (s00_axi_arvalid)
	,   .S_AXI_ARREADY      (s00_axi_arready)
	,   .S_AXI_RDATA        (s00_axi_rdata)
	,   .S_AXI_RRESP        (s00_axi_rresp)
	,   .S_AXI_RVALID       (s00_axi_rvalid)
	,   .S_AXI_RREADY       (s00_axi_rready)
	);

	// Add user logic here

	// User logic ends

	endmodule
