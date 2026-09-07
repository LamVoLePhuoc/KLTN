// Module Name: AXI_Interconnect
// Project Name: AXI4 Interconnect
// Description: AXI4 Interconnect module
// Function: AXI4 Interconnect module that connects multiple AXI4 masters to multiple AXI4 slaves.

`timescale 1ns/1ns

module AXI_Interconnect (
    /********* Clock & Reset *********/
    input                       ACLK,
    input      	                ARESETn,
    /********** Master 0 **********/
    //Write address channel
    input      [31:0]   m0_AWID,
    input	   [31:0] m0_AWADDR,
    input      [7:0]            m0_AWLEN,                                                                                                                                                                                                                                                                                                                                       
    input      [2:0]            m0_AWSIZE,
    input      [1:0]            m0_AWBURST,
    input                       m0_AWLOCK,
    input      [3:0]            m0_AWCACHE,
    input      [2:0]            m0_AWPROT,
    input      [3:0]            m0_AWQOS,
    input      [3:0]            m0_AWREGION,
    input      [1023:0] m0_AWUSER,
    input                       m0_AWVALID,
    output                      m0_AWREADY,
    //Write data channel
    input      [31:0]   m0_WID,
    input      [31:0] m0_WDATA,
    input      [3:0] m0_WSTRB,
    input                       m0_WLAST,
    input      [1023:0] m0_WUSER,
    input                       m0_WVALID,
    output                      m0_WREADY,
    //Write response channel
    output                      m0_BVALID,
    input                       m0_BREADY,
    //Read address channel
    input      [31:0]   m0_ARID,
    input      [31:0] m0_ARADDR,
    input      [7:0]            m0_ARLEN,
    input      [2:0]            m0_ARSIZE,
    input      [1:0]            m0_ARBURST,
    input                       m0_ARLOCK,
    input      [3:0]            m0_ARCACHE,
    input      [2:0]            m0_ARPROT,
    input      [3:0]            m0_ARQOS,
    input      [3:0]            m0_ARREGION,
    input      [1023:0] m0_ARUSER,
    input                       m0_ARVALID,
    output                      m0_ARREADY,
    //Read data channel
    output                      m0_RVALID,
    input                       m0_RREADY,
    /********** Master 1 **********/
    //Write address channel
    input      [31:0]   m1_AWID,
    input	   [31:0]	m1_AWADDR,
    input      [7:0]            m1_AWLEN,
    input      [2:0]            m1_AWSIZE,
    input      [1:0]            m1_AWBURST,
    input                       m1_AWLOCK,
    input      [3:0]            m1_AWCACHE,
    input      [2:0]            m1_AWPROT,
    input      [3:0]            m1_AWQOS,
    input      [3:0]            m1_AWREGION,
    input      [1023:0] m1_AWUSER,
    input                       m1_AWVALID,
    output                      m1_AWREADY,
    //Write data channel
    input      [31:0]   m1_WID,
    input      [31:0] m1_WDATA,
    input      [3:0] m1_WSTRB,
    input                       m1_WLAST,
    input      [1023:0] m1_WUSER,
    input                       m1_WVALID,
    output                      m1_WREADY,
    //Write response channel
    output                      m1_BVALID,
    input                       m1_BREADY,
    //Read address channel
    input      [31:0]   m1_ARID,
    input      [31:0] m1_ARADDR,
    input      [7:0]            m1_ARLEN,
    input      [2:0]            m1_ARSIZE,
    input      [1:0]            m1_ARBURST,
    input                       m1_ARLOCK,
    input      [3:0]            m1_ARCACHE,
    input      [2:0]            m1_ARPROT,
    input      [3:0]            m1_ARQOS,
    input      [3:0]            m1_ARREGION,
    input      [1023:0] m1_ARUSER,
    input                       m1_ARVALID,
    output                      m1_ARREADY,
    //Read data channel
    output                      m1_RVALID,
    input                       m1_RREADY,
    /********** Master 2 **********/
    //Write address channel
    input      [31:0]   m2_AWID,
    input	   [31:0]	m2_AWADDR,
    input      [7:0]            m2_AWLEN,
    input      [2:0]            m2_AWSIZE,
    input      [1:0]            m2_AWBURST,
    input                       m2_AWLOCK,
    input      [3:0]            m2_AWCACHE,
    input      [2:0]            m2_AWPROT,
    input      [3:0]            m2_AWQOS,
    input      [3:0]            m2_AWREGION,
    input      [1023:0] m2_AWUSER,
    input                       m2_AWVALID,
    output                      m2_AWREADY,
    //Write data channel
    input      [31:0]   m2_WID,
    input      [31:0] m2_WDATA,
    input      [3:0] m2_WSTRB,
    input                       m2_WLAST,
    input      [1023:0] m2_WUSER,
    input                       m2_WVALID,
    output                      m2_WREADY,
    //Write response channel
    output                      m2_BVALID,
    input                       m2_BREADY,
    //Read address channel
    input      [31:0]   m2_ARID,
    input      [31:0] m2_ARADDR,
    input      [7:0]            m2_ARLEN,
    input      [2:0]            m2_ARSIZE,
    input      [1:0]            m2_ARBURST,
    input                       m2_ARLOCK,
    input      [3:0]            m2_ARCACHE,
    input      [2:0]            m2_ARPROT,
    input      [3:0]            m2_ARQOS,
    input      [3:0]            m2_ARREGION,
    input      [1023:0] m2_ARUSER,
    input                       m2_ARVALID,
    output                      m2_ARREADY,
    //Read data channel
    output                      m2_RVALID,
    input                       m2_RREADY,
    /********** Master 3 **********/
    //Write address channel
    input      [31:0]   m3_AWID,
    input	   [31:0]	m3_AWADDR,
    input      [7:0]            m3_AWLEN,
    input      [2:0]            m3_AWSIZE,
    input      [1:0]            m3_AWBURST,
    input                       m3_AWLOCK,
    input      [3:0]            m3_AWCACHE,
    input      [2:0]            m3_AWPROT,
    input      [3:0]            m3_AWQOS,
    input      [3:0]            m3_AWREGION,
    input      [1023:0] m3_AWUSER,
    input                       m3_AWVALID,
    output                      m3_AWREADY,
    //Write data channel
    input      [31:0]   m3_WID,
    input      [31:0] m3_WDATA,
    input      [3:0] m3_WSTRB,
    input                       m3_WLAST,
    input      [1023:0] m3_WUSER,
    input                       m3_WVALID,
    output                      m3_WREADY,
    //Write response channel
    output                      m3_BVALID,
    input                       m3_BREADY,
    //Read address channel
    input      [31:0]   m3_ARID,
    input      [31:0] m3_ARADDR,
    input      [7:0]            m3_ARLEN,
    input      [2:0]            m3_ARSIZE,
    input      [1:0]            m3_ARBURST,
    input                       m3_ARLOCK,
    input      [3:0]            m3_ARCACHE,
    input      [2:0]            m3_ARPROT,
    input      [3:0]            m3_ARQOS,
    input      [3:0]            m3_ARREGION,
    input      [1023:0] m3_ARUSER,
    input                       m3_ARVALID,
    output                      m3_ARREADY,
    //Read data channel
    output                      m3_RVALID,
    input                       m3_RREADY,
    /******** Common Master Signals ********/
    //Write response channel
    output     [31:0]	m_BID,
    output     [1:0]	        m_BRESP,
    output     [1023:0] m_BUSER,
    //Read data channel
    output     [31:0]   m_RID,
    output     [31:0] m_RDATA,
    output     [1:0]	        m_RRESP,
    output                      m_RLAST,
    output     [1023:0]	m_RUSER,
    /********** Slave 0 **********/
    //Write address channel
    output                      s0_AWVALID,
    input	   	                s0_AWREADY,
    //Write data channel
    output                      s0_WVALID,
    input	  		            s0_WREADY,
    //Write response channel
    input	   [31:0]	s0_BID,
    input	   [1:0]	        s0_BRESP,
    input	   [1023:0] s0_BUSER,
    input	     		        s0_BVALID,
    output                      s0_BREADY,
    //Read address channel
    output                      s0_ARVALID,
    input	  		            s0_ARREADY,
    //Read data channel
    input	   [31:0]   s0_RID,
    input	   [31:0] s0_RDATA,
    input	   [1:0]	        s0_RRESP,
    input	  		            s0_RLAST,
    input	   [1023:0]	s0_RUSER,
    input	 		            s0_RVALID, 
    output                      s0_RREADY, 
    /********** Slave 1 **********/
    //Write address channel
    output                      s1_AWVALID,
    input	   	                s1_AWREADY,
    //Write data channel
    output                      s1_WVALID,
    input	  		            s1_WREADY,
    //Write response channel
    input	   [31:0]	s1_BID,
    input	   [1:0]	        s1_BRESP,
    input	   [1023:0] s1_BUSER,
    input	     		        s1_BVALID,
    output                      s1_BREADY,
    //Read address channel
    output                      s1_ARVALID,
    input	  		            s1_ARREADY,
    //Read data channel
    input	   [31:0]   s1_RID,
    input	   [31:0] s1_RDATA,
    input	   [1:0]	        s1_RRESP,
    input	  		            s1_RLAST,
    input	   [1023:0]	s1_RUSER,
    input	 		            s1_RVALID,
    output                      s1_RREADY,
    /********** Slave 2 **********/
    //Write address channel
    output                      s2_AWVALID,
    input	   	                s2_AWREADY,
    //Write data channel
    output                      s2_WVALID,
    input	  		            s2_WREADY,
    //Write response channel
    input	   [31:0]	s2_BID,
    input	   [1:0]	        s2_BRESP,
    input	   [1023:0] s2_BUSER,
    input	     		        s2_BVALID,
    output                      s2_BREADY,
    //Read address channel
    output                      s2_ARVALID,
    input	  		            s2_ARREADY,
    //Read data channel
    input	   [31:0]   s2_RID,
    input	   [31:0] s2_RDATA,
    input	   [1:0]	        s2_RRESP,
    input	  		            s2_RLAST,
    input	   [1023:0]	s2_RUSER,
    input	 		            s2_RVALID,
    output                      s2_RREADY,
    /********** Slave 3 **********/
    //Write address channel
    output                      s3_AWVALID,
    input	   	                s3_AWREADY,
    //Write data channel
    output                      s3_WVALID,
    input	  		            s3_WREADY,
    //Write response channel
    input	   [31:0]	s3_BID,
    input	   [1:0]	        s3_BRESP,
    input	   [1023:0] s3_BUSER,
    input	     		        s3_BVALID,
    output                      s3_BREADY,
    //Read address channel
    output                      s3_ARVALID,
    input	  		            s3_ARREADY,
    //Read data channel
    input	   [31:0]   s3_RID,
    input	   [31:0] s3_RDATA,
    input	   [1:0]	        s3_RRESP,
    input	  		            s3_RLAST,
    input	   [1023:0]	s3_RUSER,
    input	 		            s3_RVALID, 
    output                      s3_RREADY,
    /********** Slave 4 **********/
    //Write address channel
    output                      s4_AWVALID,
    input	   	                s4_AWREADY,
    //Write data channel
    output                      s4_WVALID,
    input	  		            s4_WREADY,
    //Write response channel
    input	   [31:0]	s4_BID,
    input	   [1:0]	        s4_BRESP,
    input	   [1023:0] s4_BUSER,
    input	     		        s4_BVALID,
    output                      s4_BREADY,
    //Read address channel
    output                      s4_ARVALID,
    input	  		            s4_ARREADY,
    //Read data channel
    input	   [31:0]   s4_RID,
    input	   [31:0] s4_RDATA,
    input	   [1:0]	        s4_RRESP,
    input	  		            s4_RLAST,
    input	   [1023:0]	s4_RUSER,
    input	 		            s4_RVALID, 
    output                      s4_RREADY,
    /********** Slave 5 **********/
    //Write address channel
    output                      s5_AWVALID,
    input	   	                s5_AWREADY,
    //Write data channel
    output                      s5_WVALID,
    input	  		            s5_WREADY,
    //Write response channel
    input	   [31:0]	s5_BID,
    input	   [1:0]	        s5_BRESP,
    input	   [1023:0] s5_BUSER,
    input	     		        s5_BVALID,
    output                      s5_BREADY,
    //Read address channel
    output                      s5_ARVALID,
    input	  		            s5_ARREADY,
    //Read data channel
    input	   [31:0]   s5_RID,
    input	   [31:0] s5_RDATA,
    input	   [1:0]	        s5_RRESP,
    input	  		            s5_RLAST,
    input	   [1023:0]	s5_RUSER,
    input	 		            s5_RVALID,
    output                      s5_RREADY,
    /********** Slave 6 **********/
    //Write address channel
    output                      s6_AWVALID,
    input	   	                s6_AWREADY,
    //Write data channel
    output                      s6_WVALID,
    input	  		            s6_WREADY,
    //Write response channel
    input	   [31:0]	s6_BID,
    input	   [1:0]	        s6_BRESP,
    input	   [1023:0] s6_BUSER,
    input	     		        s6_BVALID,
    output                      s6_BREADY,
    //Read address channel
    output                      s6_ARVALID,
    input	  		            s6_ARREADY,
    //Read data channel
    input	   [31:0]   s6_RID,
    input	   [31:0] s6_RDATA,
    input	   [1:0]	        s6_RRESP,
    input	  		            s6_RLAST,
    input	   [1023:0]	s6_RUSER,
    input	 		            s6_RVALID, 
    output                      s6_RREADY, 
    /********** Slave 7 **********/
    //Write address channel
    output                      s7_AWVALID,
    input	   	                s7_AWREADY,
    //Write data channel
    output                      s7_WVALID,
    input	  		            s7_WREADY,
    //Write response channel
    input	   [31:0]	s7_BID,
    input	   [1:0]	        s7_BRESP,
    input	   [1023:0] s7_BUSER,
    input	     		        s7_BVALID,
    output                      s7_BREADY,
    //Read address channel
    output                      s7_ARVALID,
    input	  		            s7_ARREADY,
    //Read data channel
    input	   [31:0]   s7_RID,
    input	   [31:0] s7_RDATA,
    input	   [1:0]	        s7_RRESP,
    input	  		            s7_RLAST,
    input	   [1023:0]	s7_RUSER,
    input	 		            s7_RVALID, 
    output                      s7_RREADY,
    /******** Common Slave Signals ********/
    //Write address channel
    output     [31:0]   s_AWID,
    output     [31:0]	s_AWADDR,
    output     [7:0]            s_AWLEN,
    output     [7:0]            s_AWSIZE,
    output     [2:0]            s_AWBURST,
    output                      s_AWLOCK,
    output     [3:0]            s_AWCACHE,
    output     [2:0]            s_AWPROT,
    output     [3:0]            s_AWQOS,
    output     [3:0]            s_AWREGION,
    output     [1023:0] s_AWUSER,  
    //Write data channel
    output     [31:0]   s_WID,
    output     [31:0] s_WDATA,
    output     [3:0] s_WSTRB,
    output                      s_WLAST,
    output     [1023:0] s_WUSER,
    //Read address channel
    output     [31:0]   s_ARID,    
    output     [31:0] s_ARADDR,
    output     [7:0]            s_ARLEN,
    output     [2:0]            s_ARSIZE,
    output     [1:0]            s_ARBURST,
    output                      s_ARLOCK,
    output     [3:0]            s_ARCACHE,
    output     [2:0]            s_ARPROT,
    output     [3:0]            s_ARQOS,
    output     [3:0]            s_ARREGION,
    output     [1023:0] s_ARUSER   
);


    //=========================================================
    //Internal signals
    wire       m0_wgrnt;
    wire       m1_wgrnt;
    wire       m2_wgrnt;
    wire       m3_wgrnt;
    wire       m0_rgrnt;
    wire       m1_rgrnt;
    wire       m2_rgrnt;
    wire       m3_rgrnt;

    wire       m_AWREADY;
    wire       m_WREADY;
    wire       m_BVALID;
    wire       m_ARREADY;
    wire       m_RVALID;

    wire       s_AWVALID;
    wire       s_WVALID;
    wire       s_BREADY; 
    wire       s_ARVALID;
    wire       s_RREADY;  

    //=========================================================
    //Write channel arbiter instantiation
    AXI_Arbiter_W u_AXI_Arbiter_W(
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        // Master 0 write request/grant signals
        .m0_AWVALID(m0_AWVALID),
        .m0_WVALID(m0_WVALID),
        .m0_BREADY(m0_BREADY),
        .m0_wgrnt(m0_wgrnt),
        // Master 1 write request/grant signals
        .m1_AWVALID(m1_AWVALID),
        .m1_WVALID(m1_WVALID),
        .m1_BREADY(m1_BREADY),
        .m1_wgrnt(m1_wgrnt),
        // Master 2 write request/grant signals
        .m2_AWVALID(m2_AWVALID),
        .m2_WVALID(m2_WVALID),
        .m2_BREADY(m2_BREADY),
        .m2_wgrnt(m2_wgrnt),
        // Master 3 write request/grant signals
        .m3_AWVALID(m3_AWVALID),
        .m3_WVALID(m3_WVALID),
        .m3_BREADY(m3_BREADY),
        .m3_wgrnt(m3_wgrnt),
        // Slave interface signals
        .m_AWREADY(m_AWREADY),
        .m_WREADY(m_WREADY),
        .m_BVALID(m_BVALID)
    );

    //=========================================================
    //Read channel arbiter instantiation
    AXI_Arbiter_R u_AXI_Arbiter_R(
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        // Master 0 read request/grant signals
        .m0_ARVALID(m0_ARVALID),
        .m0_RREADY(m0_RREADY),
        .m0_rgrnt(m0_rgrnt),
        // Master 1 read request/grant signals
        .m1_ARVALID(m1_ARVALID),
        .m1_RREADY(m1_RREADY),
        .m1_rgrnt(m1_rgrnt),
        // Master 2 read request/grant signals
        .m2_ARVALID(m2_ARVALID),
        .m2_RREADY(m2_RREADY),
        .m2_rgrnt(m2_rgrnt),
        // Master 3 read request/grant signals
        .m3_ARVALID(m3_ARVALID),
        .m3_RREADY(m3_RREADY),
        .m3_rgrnt(m3_rgrnt),
        // Master common signals
        .m_RVALID(m_RVALID),
        .m_RLAST(m_RLAST)
    );

    //=========================================================
    //Write channel master multiplexer
    AXI_Master_Mux_W  u_AXI_Master_Mux_W (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        // Master 0 signals
        .m0_AWID(m0_AWID),
        .m0_AWADDR(m0_AWADDR),
        .m0_AWLEN(m0_AWLEN),
        .m0_AWSIZE(m0_AWSIZE),
        .m0_AWBURST(m0_AWBURST),
        .m0_AWLOCK(m0_AWLOCK),
        .m0_AWCACHE(m0_AWCACHE),
        .m0_AWPROT(m0_AWPROT),
        .m0_AWQOS(m0_AWQOS),
        .m0_AWREGION(m0_AWREGION),
        .m0_AWUSER(m0_AWUSER),
        .m0_AWVALID(m0_AWVALID),
        .m0_AWREADY(m0_AWREADY),
        .m0_WID(m0_WID),
        .m0_WDATA(m0_WDATA),
        .m0_WSTRB(m0_WSTRB),
        .m0_WLAST(m0_WLAST),
        .m0_WUSER(m0_WUSER),
        .m0_WVALID(m0_WVALID),
        .m0_WREADY(m0_WREADY),
        .m0_wgrnt(m0_wgrnt),
        .m0_BVALID(m0_BVALID),
        .m0_BREADY(m0_BREADY),
        // Master 1 signals
        .m1_AWID(m1_AWID),
        .m1_AWADDR(m1_AWADDR),
        .m1_AWLEN(m1_AWLEN),
        .m1_AWSIZE(m1_AWSIZE),
        .m1_AWBURST(m1_AWBURST),
        .m1_AWLOCK(m1_AWLOCK),
        .m1_AWCACHE(m1_AWCACHE),
        .m1_AWPROT(m1_AWPROT),
        .m1_AWQOS(m1_AWQOS),
        .m1_AWREGION(m1_AWREGION),
        .m1_AWUSER(m1_AWUSER),
        .m1_AWVALID(m1_AWVALID),
        .m1_AWREADY(m1_AWREADY),
        .m1_WID(m1_WID),
        .m1_WDATA(m1_WDATA),
        .m1_WSTRB(m1_WSTRB),
        .m1_WLAST(m1_WLAST),
        .m1_WUSER(m1_WUSER),
        .m1_WVALID(m1_WVALID),
        .m1_WREADY(m1_WREADY),
        .m1_wgrnt(m1_wgrnt),
        .m1_BVALID(m1_BVALID),
        .m1_BREADY(m1_BREADY),
        // Master 2 signals
        .m2_AWID(m2_AWID),
        .m2_AWADDR(m2_AWADDR),
        .m2_AWLEN(m2_AWLEN),
        .m2_AWSIZE(m2_AWSIZE),
        .m2_AWBURST(m2_AWBURST),
        .m2_AWLOCK(m2_AWLOCK),
        .m2_AWCACHE(m2_AWCACHE),
        .m2_AWPROT(m2_AWPROT),
        .m2_AWQOS(m2_AWQOS),
        .m2_AWREGION(m2_AWREGION),
        .m2_AWUSER(m2_AWUSER),
        .m2_AWVALID(m2_AWVALID),
        .m2_AWREADY(m2_AWREADY),
        .m2_WID(m2_WID),
        .m2_WDATA(m2_WDATA),
        .m2_WSTRB(m2_WSTRB),
        .m2_WLAST(m2_WLAST),
        .m2_WUSER(m2_WUSER),
        .m2_WVALID(m2_WVALID),
        .m2_WREADY(m2_WREADY),
        .m2_wgrnt(m2_wgrnt),
        .m2_BVALID(m2_BVALID),
        .m2_BREADY(m2_BREADY),
        // Master 3 signals
        .m3_AWID(m3_AWID),
        .m3_AWADDR(m3_AWADDR),
        .m3_AWLEN(m3_AWLEN),
        .m3_AWSIZE(m3_AWSIZE),
        .m3_AWBURST(m3_AWBURST),
        .m3_AWLOCK(m3_AWLOCK),
        .m3_AWCACHE(m3_AWCACHE),
        .m3_AWPROT(m3_AWPROT),
        .m3_AWQOS(m3_AWQOS),
        .m3_AWREGION(m3_AWREGION),
        .m3_AWUSER(m3_AWUSER),
        .m3_AWVALID(m3_AWVALID),
        .m3_AWREADY(m3_AWREADY),
        .m3_WID(m3_WID),
        .m3_WDATA(m3_WDATA),
        .m3_WSTRB(m3_WSTRB),
        .m3_WLAST(m3_WLAST),
        .m3_WUSER(m3_WUSER),
        .m3_WVALID(m3_WVALID),
        .m3_WREADY(m3_WREADY),
        .m3_wgrnt(m3_wgrnt),
        .m3_BVALID(m3_BVALID),
        .m3_BREADY(m3_BREADY),
        // Slave common signals
        .s_AWID(s_AWID),
        .s_AWADDR(s_AWADDR),
        .s_AWLEN(s_AWLEN),
        .s_AWSIZE(s_AWSIZE),
        .s_AWBURST(s_AWBURST),
        .s_AWLOCK(s_AWLOCK),
        .s_AWCACHE(s_AWCACHE),
        .s_AWPROT(s_AWPROT),
        .s_AWQOS(s_AWQOS),
        .s_AWREGION(s_AWREGION),
        .s_AWUSER(s_AWUSER),
        .s_WID(s_WID),
        .s_WDATA(s_WDATA),
        .s_WSTRB(s_WSTRB),
        .s_WLAST(s_WLAST),
        .s_WUSER(s_WUSER),
        // Control signals
        .s_AWVALID(s_AWVALID),
        .s_WVALID(s_WVALID),
        .m_AWREADY(m_AWREADY),
        .m_WREADY(m_WREADY)
    );

    //=========================================================
    //Read channel master multiplexer
    AXI_Master_Mux_R u_AXI_Master_Mux_R (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        // Master 0 signals
        .m0_ARID(m0_ARID),
        .m0_ARADDR(m0_ARADDR),
        .m0_ARLEN(m0_ARLEN),
        .m0_ARSIZE(m0_ARSIZE),
        .m0_ARBURST(m0_ARBURST),
        .m0_ARLOCK(m0_ARLOCK),
        .m0_ARCACHE(m0_ARCACHE),
        .m0_ARPROT(m0_ARPROT),
        .m0_ARQOS(m0_ARQOS),
        .m0_ARREGION(m0_ARREGION),
        .m0_ARUSER(m0_ARUSER),
        .m0_ARVALID(m0_ARVALID),
        .m0_ARREADY(m0_ARREADY),
        .m0_RVALID(m0_RVALID),
        .m0_RREADY(m0_RREADY),
        .m0_rgrnt(m0_rgrnt),
        // Master 1 signals
        .m1_ARID(m1_ARID),
        .m1_ARADDR(m1_ARADDR),
        .m1_ARLEN(m1_ARLEN),
        .m1_ARSIZE(m1_ARSIZE),
        .m1_ARBURST(m1_ARBURST),
        .m1_ARLOCK(m1_ARLOCK),
        .m1_ARCACHE(m1_ARCACHE),
        .m1_ARPROT(m1_ARPROT),
        .m1_ARQOS(m1_ARQOS),
        .m1_ARREGION(m1_ARREGION),
        .m1_ARUSER(m1_ARUSER),
        .m1_ARVALID(m1_ARVALID),
        .m1_ARREADY(m1_ARREADY),
        .m1_RVALID(m1_RVALID),
        .m1_RREADY(m1_RREADY),
        .m1_rgrnt(m1_rgrnt),
        // Master 2 signals
        .m2_ARID(m2_ARID),
        .m2_ARADDR(m2_ARADDR),
        .m2_ARLEN(m2_ARLEN),
        .m2_ARSIZE(m2_ARSIZE),
        .m2_ARBURST(m2_ARBURST),
        .m2_ARLOCK(m2_ARLOCK),
        .m2_ARCACHE(m2_ARCACHE),
        .m2_ARPROT(m2_ARPROT),
        .m2_ARQOS(m2_ARQOS),
        .m2_ARREGION(m2_ARREGION),
        .m2_ARUSER(m2_ARUSER),
        .m2_ARVALID(m2_ARVALID),
        .m2_ARREADY(m2_ARREADY),
        .m2_RVALID(m2_RVALID),
        .m2_RREADY(m2_RREADY),
        .m2_rgrnt(m2_rgrnt),
        // Master 3 signals
        .m3_ARID(m3_ARID),
        .m3_ARADDR(m3_ARADDR),
        .m3_ARLEN(m3_ARLEN),
        .m3_ARSIZE(m3_ARSIZE),
        .m3_ARBURST(m3_ARBURST),
        .m3_ARLOCK(m3_ARLOCK),
        .m3_ARCACHE(m3_ARCACHE),
        .m3_ARPROT(m3_ARPROT),
        .m3_ARQOS(m3_ARQOS),
        .m3_ARREGION(m3_ARREGION),
        .m3_ARUSER(m3_ARUSER),
        .m3_ARVALID(m3_ARVALID),
        .m3_ARREADY(m3_ARREADY),
        .m3_RVALID(m3_RVALID),
        .m3_RREADY(m3_RREADY),
        .m3_rgrnt(m3_rgrnt),
        // Slave common signals
        .s_ARID(s_ARID),
        .s_ARADDR(s_ARADDR),
        .s_ARLEN(s_ARLEN),
        .s_ARSIZE(s_ARSIZE),
        .s_ARBURST(s_ARBURST),
        .s_ARLOCK(s_ARLOCK),
        .s_ARCACHE(s_ARCACHE),
        .s_ARPROT(s_ARPROT),
        .s_ARQOS(s_ARQOS),
        .s_ARREGION(s_ARREGION),
        .s_ARUSER(s_ARUSER),
        .s_ARVALID(s_ARVALID),
        .s_RREADY(s_RREADY),
        // Master common signals
        .m_ARREADY(m_ARREADY),
        .m_RVALID(m_RVALID)
    );

    //=========================================================
    //Write channel slave multiplexer
    AXI_Slave_Mux_W u_AXI_Slave_Mux_W (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        // Slave 0 connections
        .s0_AWREADY(s0_AWREADY),
        .s0_WREADY(s0_WREADY),
        .s0_BID(s0_BID),
        .s0_BRESP(s0_BRESP),
        .s0_BUSER(s0_BUSER),
        .s0_BVALID(s0_BVALID),
        .s0_AWVALID(s0_AWVALID),
        .s0_WVALID(s0_WVALID),
        .s0_BREADY(s0_BREADY),
        // Slave 1 connections
        .s1_AWREADY(s1_AWREADY),
        .s1_WREADY(s1_WREADY),
        .s1_BID(s1_BID),
        .s1_BRESP(s1_BRESP),
        .s1_BUSER(s1_BUSER),
        .s1_BVALID(s1_BVALID),
        .s1_AWVALID(s1_AWVALID),
        .s1_WVALID(s1_WVALID),
        .s1_BREADY(s1_BREADY),
        // Slave 2 connections
        .s2_AWREADY(s2_AWREADY),
        .s2_WREADY(s2_WREADY),
        .s2_BID(s2_BID),
        .s2_BRESP(s2_BRESP),
        .s2_BUSER(s2_BUSER),
        .s2_BVALID(s2_BVALID),
        .s2_AWVALID(s2_AWVALID),
        .s2_WVALID(s2_WVALID),
        .s2_BREADY(s2_BREADY),
        // Slave 3 connections
        .s3_AWREADY(s3_AWREADY),
        .s3_WREADY(s3_WREADY),
        .s3_BID(s3_BID),
        .s3_BRESP(s3_BRESP),
        .s3_BUSER(s3_BUSER),
        .s3_BVALID(s3_BVALID),
        .s3_AWVALID(s3_AWVALID),
        .s3_WVALID(s3_WVALID),
        .s3_BREADY(s3_BREADY),
        // Slave 4 connections
        .s4_AWREADY(s4_AWREADY),
        .s4_WREADY(s4_WREADY),
        .s4_BID(s4_BID),
        .s4_BRESP(s4_BRESP),
        .s4_BUSER(s4_BUSER),
        .s4_BVALID(s4_BVALID),
        .s4_AWVALID(s4_AWVALID),
        .s4_WVALID(s4_WVALID),
        .s4_BREADY(s4_BREADY),
        // Slave 5 connections
        .s5_AWREADY(s5_AWREADY),
        .s5_WREADY(s5_WREADY),
        .s5_BID(s5_BID),
        .s5_BRESP(s5_BRESP),
        .s5_BUSER(s5_BUSER),
        .s5_BVALID(s5_BVALID),
        .s5_AWVALID(s5_AWVALID),
        .s5_WVALID(s5_WVALID),
        .s5_BREADY(s5_BREADY),
        // Slave 6 connections
        .s6_AWREADY(s6_AWREADY),
        .s6_WREADY(s6_WREADY),
        .s6_BID(s6_BID),
        .s6_BRESP(s6_BRESP),
        .s6_BUSER(s6_BUSER),
        .s6_BVALID(s6_BVALID),
        .s6_AWVALID(s6_AWVALID),
        .s6_WVALID(s6_WVALID),
        .s6_BREADY(s6_BREADY),
        // Slave 7 connections
        .s7_AWREADY(s7_AWREADY),
        .s7_WREADY(s7_WREADY),
        .s7_BID(s7_BID),
        .s7_BRESP(s7_BRESP),
        .s7_BUSER(s7_BUSER),
        .s7_BVALID(s7_BVALID),
        .s7_AWVALID(s7_AWVALID),
        .s7_WVALID(s7_WVALID),
        .s7_BREADY(s7_BREADY),
        // Master common signals
        .m_AWREADY(m_AWREADY),
        .m_WREADY(m_WREADY),
        .m_BID(m_BID),
        .m_BRESP(m_BRESP),
        .m_BUSER(m_BUSER),
        .m_BVALID(m_BVALID),

        // Slave common signals
        .s_AWADDR(s_AWADDR),
        .s_AWVALID(s_AWVALID),
        .s_WVALID(s_WVALID),
        .s_BREADY(s_BREADY)
    );

    //=========================================================
    //Read channel slave multiplexer
    AXI_Slave_Mux_R u_AXI_Slave_Mux_R (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        // Slave 0 connections
        .s0_ARREADY(s0_ARREADY),
        .s0_RID(s0_RID),
        .s0_RDATA(s0_RDATA),
        .s0_RRESP(s0_RRESP),
        .s0_RLAST(s0_RLAST),
        .s0_RUSER(s0_RUSER),
        .s0_RVALID(s0_RVALID),
        .s0_ARVALID(s0_ARVALID),
        .s0_RREADY(s0_RREADY),
        // Slave 1 connections
        .s1_ARREADY(s1_ARREADY),
        .s1_RID(s1_RID),
        .s1_RDATA(s1_RDATA),
        .s1_RRESP(s1_RRESP),
        .s1_RLAST(s1_RLAST),
        .s1_RUSER(s1_RUSER),
        .s1_RVALID(s1_RVALID),
        .s1_ARVALID(s1_ARVALID),
        .s1_RREADY(s1_RREADY),
        // Slave 2 connections
        .s2_ARREADY(s2_ARREADY),
        .s2_RID(s2_RID),
        .s2_RDATA(s2_RDATA),
        .s2_RRESP(s2_RRESP),
        .s2_RLAST(s2_RLAST),
        .s2_RUSER(s2_RUSER),
        .s2_RVALID(s2_RVALID),
        .s2_ARVALID(s2_ARVALID),
        .s2_RREADY(s2_RREADY),
        // Slave 3 connections
        .s3_ARREADY(s3_ARREADY),
        .s3_RID(s3_RID),
        .s3_RDATA(s3_RDATA),
        .s3_RRESP(s3_RRESP),
        .s3_RLAST(s3_RLAST),
        .s3_RUSER(s3_RUSER),
        .s3_RVALID(s3_RVALID),
        .s3_ARVALID(s3_ARVALID),
        .s3_RREADY(s3_RREADY),
        // Slave 4 connections
        .s4_ARREADY(s4_ARREADY),
        .s4_RID(s4_RID),
        .s4_RDATA(s4_RDATA),
        .s4_RRESP(s4_RRESP),
        .s4_RLAST(s4_RLAST),
        .s4_RUSER(s4_RUSER),
        .s4_RVALID(s4_RVALID),
        .s4_ARVALID(s4_ARVALID),
        .s4_RREADY(s4_RREADY),
        // Slave 5 connections
        .s5_ARREADY(s5_ARREADY),
        .s5_RID(s5_RID),
        .s5_RDATA(s5_RDATA),
        .s5_RRESP(s5_RRESP),
        .s5_RLAST(s5_RLAST),
        .s5_RUSER(s5_RUSER),
        .s5_RVALID(s5_RVALID),
        .s5_ARVALID(s5_ARVALID),
        .s5_RREADY(s5_RREADY),
        // Slave 6 connections
        .s6_ARREADY(s6_ARREADY),
        .s6_RID(s6_RID),
        .s6_RDATA(s6_RDATA),
        .s6_RRESP(s6_RRESP),
        .s6_RLAST(s6_RLAST),
        .s6_RUSER(s6_RUSER),
        .s6_RVALID(s6_RVALID),
        .s6_ARVALID(s6_ARVALID),
        .s6_RREADY(s6_RREADY),
        // Slave 7 connections
        .s7_ARREADY(s7_ARREADY),
        .s7_RID(s7_RID),
        .s7_RDATA(s7_RDATA),
        .s7_RRESP(s7_RRESP),
        .s7_RLAST(s7_RLAST),
        .s7_RUSER(s7_RUSER),
        .s7_RVALID(s7_RVALID),
        .s7_ARVALID(s7_ARVALID),
        .s7_RREADY(s7_RREADY),
        // Master common signals
        .m_RID(m_RID),
        .m_RDATA(m_RDATA),
        .m_RRESP(m_RRESP),
        .m_RLAST(m_RLAST),
        .m_RUSER(m_RUSER),
        .m_RVALID(m_RVALID),
        .m_ARREADY(m_ARREADY),
        // Slave common signals
        .s_ARVALID(s_ARVALID),
        .s_RREADY(s_RREADY),
        .s_ARADDR(s_ARADDR)
    );

endmodule
