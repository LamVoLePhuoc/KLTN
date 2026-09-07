// Module Name: AXI_Master_Mux_W
// Project Name: AXI4 Interconnect
// Description: AXI4 Write Address Channel Multiplexer
// Function: AXI bus write channel master multiplexer module. 
//      It multiplexes the write address and data channels from four masters to a single slave. 
//      The module also handles the write response channel from the slave to the selected master. 
//      The module uses round-robin arbitration to select the active master based on their request signals.

`timescale 1ns/1ns

module AXI_Master_Mux_W (
    /********* Clock & Reset *********/
    input                       ACLK,
    input      	                ARESETn,
    /********** Master 0 **********/
    //Write Address Channel
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
    output reg                  m0_AWREADY,
    //Write Data Channel
    input      [31:0]   m0_WID,
    input      [31:0] m0_WDATA,
    input      [3:0] m0_WSTRB,
    input                       m0_WLAST,
    input      [1023:0] m0_WUSER,
    input                       m0_WVALID,
    output reg                  m0_WREADY,
    //Write Response Channel
    output reg                  m0_BVALID,
    input                       m0_BREADY,
    /********** Master 1 **********/
    //Write Address Channel
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
    output reg                  m1_AWREADY,
    //Write Data Channel
    input      [31:0]   m1_WID,
    input      [31:0] m1_WDATA,
    input      [3:0] m1_WSTRB,
    input                       m1_WLAST,
    input      [1023:0] m1_WUSER,
    input                       m1_WVALID,
    output reg                  m1_WREADY,
    //Write Response Channel
    output reg                  m1_BVALID,
    input                       m1_BREADY,
    /********** Master 2 **********/
    //Write Address Channel
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
    output reg                  m2_AWREADY,
    //Write Data Channel
    input      [31:0]   m2_WID,
    input      [31:0] m2_WDATA,
    input      [3:0] m2_WSTRB,
    input                       m2_WLAST,
    input      [1023:0] m2_WUSER,
    input                       m2_WVALID,
    output reg                  m2_WREADY,
    //Write Response Channel
    output reg                  m2_BVALID,
    input                       m2_BREADY,
    /********** Master 3 **********/
    //Write Address Channel
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
    output reg                  m3_AWREADY,
    //Write Data Channel
    input      [31:0]   m3_WID,
    input      [31:0] m3_WDATA,
    input      [3:0] m3_WSTRB,
    input                       m3_WLAST,
    input      [1023:0] m3_WUSER,
    input                       m3_WVALID,
    output reg                  m3_WREADY,
    //Write Response Channel
    output reg                  m3_BVALID,
    input                       m3_BREADY,
    /******** Slave Common Signals ********/
    //Write Address Channel
    output reg [31:0]   s_AWID,
    output reg [31:0]	s_AWADDR,
    output reg [7:0]            s_AWLEN,
    output reg [2:0]            s_AWSIZE,
    output reg [1:0]            s_AWBURST,
    output reg                  s_AWLOCK,
    output reg [3:0]            s_AWCACHE,
    output reg [2:0]            s_AWPROT,
    output reg [3:0]            s_AWQOS,
    output reg [3:0]            s_AWREGION,
    output reg [1023:0] s_AWUSER,
    output reg                  s_AWVALID,
    //Write Data Channel
    output reg [31:0]   s_WID,
    output reg [31:0] s_WDATA,
    output reg [3:0] s_WSTRB,
    output reg                  s_WLAST,
    output reg [1023:0] s_WUSER,
    output reg                  s_WVALID,
    //Write Response Channel
    output reg                  s_BREADY,
    /******** Master Common Signals ********/
    input                       m_AWREADY,
    input                       m_WREADY,
    input                       m_BVALID,

    input                       m0_wgrnt,
    input                       m1_wgrnt,
    input                       m2_wgrnt,
    input                       m3_wgrnt

);


    //=========================================================
    //Write path multiplexing for master signals

    //---------------------------------------------------------
    //Other signal multiplexing
    always @(*) begin
        case({m0_wgrnt,m1_wgrnt,m2_wgrnt,m3_wgrnt})     //Check write path arbitration result
            4'b1000: begin
                s_AWID      =  m0_AWID;
                s_AWADDR    =  m0_AWADDR;
                s_AWLEN     =  m0_AWLEN;
                s_AWSIZE    =  m0_AWSIZE;
                s_AWBURST   =  m0_AWBURST;
                s_AWLOCK    =  m0_AWLOCK;
                s_AWCACHE   =  m0_AWCACHE;
                s_AWPROT    =  m0_AWPROT;
                s_AWQOS     =  m0_AWQOS;
                s_AWREGION  =  m0_AWREGION;
                s_AWUSER    =  m0_AWUSER;
                s_AWVALID   =  m0_AWVALID;
                s_WID       =  m0_WID;
                s_WDATA     =  m0_WDATA;
                s_WSTRB     =  m0_WSTRB;
                s_WLAST     =  m0_WLAST;
                s_WUSER     =  m0_WUSER;
                s_WVALID    =  m0_WVALID;
                s_BREADY    =  m0_BREADY;
            end
            4'b0100: begin
                s_AWID      =  m1_AWID;
                s_AWADDR    =  m1_AWADDR;
                s_AWLEN     =  m1_AWLEN;
                s_AWSIZE    =  m1_AWSIZE;
                s_AWBURST   =  m1_AWBURST;
                s_AWLOCK    =  m1_AWLOCK;
                s_AWCACHE   =  m1_AWCACHE;
                s_AWPROT    =  m1_AWPROT;
                s_AWQOS     =  m1_AWQOS;
                s_AWREGION  =  m1_AWREGION;
                s_AWUSER    =  m1_AWUSER;
                s_AWVALID   =  m1_AWVALID;
                s_WID       =  m1_WID;
                s_WDATA     =  m1_WDATA;
                s_WSTRB     =  m1_WSTRB;
                s_WLAST     =  m1_WLAST;
                s_WUSER     =  m1_WUSER;
                s_WVALID    =  m1_WVALID;
                s_BREADY    =  m1_BREADY;
            end
            4'b0010: begin
                s_AWID      =  m2_AWID;
                s_AWADDR    =  m2_AWADDR;
                s_AWLEN     =  m2_AWLEN;
                s_AWSIZE    =  m2_AWSIZE;
                s_AWBURST   =  m2_AWBURST;
                s_AWLOCK    =  m2_AWLOCK;
                s_AWCACHE   =  m2_AWCACHE;
                s_AWPROT    =  m2_AWPROT;
                s_AWQOS     =  m2_AWQOS;
                s_AWREGION  =  m2_AWREGION;
                s_AWUSER    =  m2_AWUSER;
                s_AWVALID   =  m2_AWVALID;
                s_WID       =  m2_WID;
                s_WDATA     =  m2_WDATA;
                s_WSTRB     =  m2_WSTRB;
                s_WLAST     =  m2_WLAST;
                s_WUSER     =  m2_WUSER;
                s_WVALID    =  m2_WVALID;
                s_BREADY    =  m2_BREADY;
            end
            4'b0001: begin
                s_AWID      =  m3_AWID;
                s_AWADDR    =  m3_AWADDR;
                s_AWLEN     =  m3_AWLEN;
                s_AWSIZE    =  m3_AWSIZE;
                s_AWBURST   =  m3_AWBURST;
                s_AWLOCK    =  m3_AWLOCK;
                s_AWCACHE   =  m3_AWCACHE;
                s_AWPROT    =  m3_AWPROT;
                s_AWQOS     =  m3_AWQOS;
                s_AWREGION  =  m3_AWREGION;
                s_AWUSER    =  m3_AWUSER;
                s_AWVALID   =  m3_AWVALID;
                s_WID       =  m3_WID;
                s_WDATA     =  m3_WDATA;
                s_WSTRB     =  m3_WSTRB;
                s_WLAST     =  m3_WLAST;
                s_WUSER     =  m3_WUSER;
                s_WVALID    =  m3_WVALID;
                s_BREADY    =  m3_BREADY;
            end
            default: begin
                s_AWID      =  0;
                s_AWADDR    =  0;
                s_AWLEN     =  0;
                s_AWSIZE    =  0;
                s_AWBURST   =  0;
                s_AWLOCK    =  0;
                s_AWCACHE   =  0;
                s_AWPROT    =  0;
                s_AWQOS     =  0;
                s_AWREGION  =  0;
                s_AWUSER    =  0;
                s_AWVALID   =  0;
                s_WID       =  0;
                s_WDATA     =  0;
                s_WSTRB     =  0;
                s_WLAST     =  0;
                s_WUSER     =  0;
                s_WVALID    =  0;
                s_BREADY    =  0;
            end
        endcase
    end


    //---------------------------------------------------------
    //AWREADY signal multiplexing
    always @(*) begin
        case({m0_wgrnt,m1_wgrnt,m2_wgrnt,m3_wgrnt})
            4'b1000: begin 
                m0_AWREADY = m_AWREADY;
                m1_AWREADY = 0;
                m2_AWREADY = 0;
                m3_AWREADY = 0;
            end
            4'b0100: begin
                m0_AWREADY = 0;
                m1_AWREADY = m_AWREADY;
                m2_AWREADY = 0;
                m3_AWREADY = 0;
            end
            4'b0010: begin
                m0_AWREADY = 0;
                m1_AWREADY = 0;
                m2_AWREADY = m_AWREADY;
                m3_AWREADY = 0;
            end
            4'b0001: begin
                m0_AWREADY = 0;
                m1_AWREADY = 0;
                m2_AWREADY = 0;
                m3_AWREADY = m_AWREADY;
            end
            default: begin
                m0_AWREADY = 0;
                m1_AWREADY = 0;
                m2_AWREADY = 0;
                m3_AWREADY = 0;
            end
        endcase
    end

    //---------------------------------------------------------
    //WREADY signal multiplexing
    always @(*) begin
        case({m0_wgrnt,m1_wgrnt,m2_wgrnt,m3_wgrnt})
            4'b1000: begin 
                m0_WREADY = m_WREADY;
                m1_WREADY = 0;
                m2_WREADY = 0;
                m3_WREADY = 0;
            end
            4'b0100: begin
                m0_WREADY = 0;
                m1_WREADY = m_WREADY;
                m2_WREADY = 0;
                m3_WREADY = 0;
            end
            4'b0010: begin
                m0_WREADY = 0;
                m1_WREADY = 0;
                m2_WREADY = m_WREADY;
                m3_WREADY = 0;
            end
            4'b0001: begin
                m0_WREADY = 0;
                m1_WREADY = 0;
                m2_WREADY = 0;
                m3_WREADY = m_WREADY;
            end
            default: begin
                m0_WREADY = 0;
                m1_WREADY = 0;
                m2_WREADY = 0;
                m3_WREADY = 0;
            end
        endcase
    end    

    //---------------------------------------------------------
    //BVALID signal multiplexing
    always @(*) begin
        case({m0_wgrnt,m1_wgrnt,m2_wgrnt,m3_wgrnt})
            4'b1000: begin 
                m0_BVALID = m_BVALID;
                m1_BVALID = 0;
                m2_BVALID = 0;
                m3_BVALID = 0;
            end
            4'b0100: begin
                m0_BVALID = 0;
                m1_BVALID = m_BVALID;
                m2_BVALID = 0;
                m3_BVALID = 0;
            end
            4'b0010: begin
                m0_BVALID = 0;
                m1_BVALID = 0;
                m2_BVALID = m_BVALID;
                m3_BVALID = 0;
            end
            4'b0001: begin
                m0_BVALID = 0;
                m1_BVALID = 0;
                m2_BVALID = 0;
                m3_BVALID = m_BVALID;
            end
            default: begin
                m0_BVALID = 0;
                m1_BVALID = 0;
                m2_BVALID = 0;
                m3_BVALID = 0;
            end
        endcase
    end    


endmodule