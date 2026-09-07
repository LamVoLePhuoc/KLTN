// Module bname: AXI_Slave_Mux_W
// Project Name: AXI4 Interconnect
// Description: AXI4 Write Address Channel Multiplexer
// Function: This module implements a multiplexer for the AXI4 write address channel. 
//      It selects one of the eight slave interfaces based on the address provided by the master. 
//      The selected slave's signals are then passed to the master interface.

`timescale 1ns/1ns

module AXI_Slave_Mux_W (
    /********* Clock & Reset *********/
    input                       ACLK,
    input      	                ARESETn,
    /********** Slave 0 **********/
    //Write address channel
    output reg                  s0_AWVALID,
    input	   	                s0_AWREADY,
    //Write data channel
    output reg                  s0_WVALID,
    input	  		            s0_WREADY,
    //Write response channel
    input	   [31:0]	s0_BID,
    input	   [1:0]	        s0_BRESP,
    input	   [1023:0] s0_BUSER,
    input	     		        s0_BVALID,
    output reg                  s0_BREADY,
    /********** Slave 1 **********/
    //Write address channel
    output reg                  s1_AWVALID,
    input	   	                s1_AWREADY,
    //Write data channel
    output reg                  s1_WVALID,
    input	  		            s1_WREADY,
    //Write response channel
    input	   [31:0]	s1_BID,
    input	   [1:0]	        s1_BRESP,
    input	   [1023:0] s1_BUSER,
    input	     		        s1_BVALID,
    output reg                  s1_BREADY,
    /********** Slave 2 **********/
    //Write address channel
    output reg                  s2_AWVALID,
    input	   	                s2_AWREADY,
    //Write data channel
    output reg                  s2_WVALID,
    input	  		            s2_WREADY,
    //Write response channel
    input	   [31:0]	s2_BID,
    input	   [1:0]	        s2_BRESP,
    input	   [1023:0] s2_BUSER,
    input	     		        s2_BVALID,
    output reg                  s2_BREADY,
    /********** Slave 3 **********/
    //Write address channel
    output reg                  s3_AWVALID,
    input	   	                s3_AWREADY,
    //Write data channel
    output reg                  s3_WVALID,
    input	  		            s3_WREADY,
    //Write response channel
    input	   [31:0]	s3_BID,
    input	   [1:0]	        s3_BRESP,
    input	   [1023:0] s3_BUSER,
    input	     		        s3_BVALID,
    output reg                  s3_BREADY,
    /********** Slave 4 **********/
    //Write address channel
    output reg                  s4_AWVALID,
    input	   	                s4_AWREADY,
    //Write data channel
    output reg                  s4_WVALID,
    input	  		            s4_WREADY,
    //Write response channel
    input	   [31:0]	s4_BID,
    input	   [1:0]	        s4_BRESP,
    input	   [1023:0] s4_BUSER,
    input	     		        s4_BVALID,
    output reg                  s4_BREADY,
    /********** Slave 5 **********/
    //Write address channel
    output reg                  s5_AWVALID,
    input	   	                s5_AWREADY,
    //Write data channel
    output reg                  s5_WVALID,
    input	  		            s5_WREADY,
    //Write response channel
    input	   [31:0]	s5_BID,
    input	   [1:0]	        s5_BRESP,
    input	   [1023:0] s5_BUSER,
    input	     		        s5_BVALID,
    output reg                  s5_BREADY,
    /********** Slave 6 **********/
    //Write address channel
    output reg                  s6_AWVALID,
    input	   	                s6_AWREADY,
    //Write data channel
    output reg                  s6_WVALID,
    input	  		            s6_WREADY,
    //Write response channel
    input	   [31:0]	s6_BID,
    input	   [1:0]	        s6_BRESP,
    input	   [1023:0] s6_BUSER,
    input	     		        s6_BVALID,
    output reg                  s6_BREADY,
    /********** Slave 7 **********/
    //Write address channel
    output reg                  s7_AWVALID,
    input	   	                s7_AWREADY,
    //Write data channel
    output reg                  s7_WVALID,
    input	  		            s7_WREADY,
    //Write response channel
    input	   [31:0]	s7_BID,
    input	   [1:0]	        s7_BRESP,
    input	   [1023:0] s7_BUSER,
    input	     		        s7_BVALID,
    output reg                  s7_BREADY,
    /******** Master Common Signals ********/
    //Write address channel
    output reg 	                m_AWREADY,
    //Write data channel
    output reg		            m_WREADY,
    //Write response channel
    output reg [31:0]	m_BID,
    output reg [1:0]	        m_BRESP,
    output reg [1023:0] m_BUSER,
    output reg   		        m_BVALID,
    /******** Slave Common Signals ********/
    //Write address channel
    input     [31:0]	s_AWADDR,
    input                       s_AWVALID,
    //Write data channel
    input                       s_WVALID,
    //Write response channel
    input                       s_BREADY    
);

    //=========================================================
    //Constant definitions
    parameter   TCO     =   1;  //Register delay

    //=========================================================
    //Write address storage
    reg [63:0]    awaddr;     //Write address register

    always @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn)
            awaddr <= #TCO 0;
        else if(s_AWVALID)                  //Store write address when write address handshake signal is activated
            awaddr <= #TCO s_AWADDR;
        else
            awaddr <= #TCO awaddr;
    end

    //=========================================================
    //Write path multiplexing for slave signals

    //---------------------------------------------------------
    //Other signal multiplexing
    always @(*) begin
        case(awaddr[63:61])
            3'b000: begin
                m_AWREADY   = s0_AWREADY;
                m_WREADY    = s0_WREADY;
                m_BID       = s0_BID;
                m_BRESP     = s0_BRESP;
                m_BUSER     = s0_BUSER;
                m_BVALID    = s0_BVALID;
            end
            3'b001: begin
                m_AWREADY   = s1_AWREADY;
                m_WREADY    = s1_WREADY;
                m_BID       = s1_BID;
                m_BRESP     = s1_BRESP;
                m_BUSER     = s1_BUSER;
                m_BVALID    = s1_BVALID;
            end
            3'b010: begin
                m_AWREADY   = s2_AWREADY;
                m_WREADY    = s2_WREADY;
                m_BID       = s2_BID;
                m_BRESP     = s2_BRESP;
                m_BUSER     = s2_BUSER;
                m_BVALID    = s2_BVALID;
            end
            3'b011: begin
                m_AWREADY   = s3_AWREADY;
                m_WREADY    = s3_WREADY;
                m_BID       = s3_BID;
                m_BRESP     = s3_BRESP;
                m_BUSER     = s3_BUSER;
                m_BVALID    = s3_BVALID;
            end
            3'b100: begin
                m_AWREADY   = s4_AWREADY;
                m_WREADY    = s4_WREADY;
                m_BID       = s4_BID;
                m_BRESP     = s4_BRESP;
                m_BUSER     = s4_BUSER;
                m_BVALID    = s4_BVALID;
            end
            3'b101: begin
                m_AWREADY   = s5_AWREADY;
                m_WREADY    = s5_WREADY;
                m_BID       = s5_BID;
                m_BRESP     = s5_BRESP;
                m_BUSER     = s5_BUSER;
                m_BVALID    = s5_BVALID;
            end
            3'b110: begin
                m_AWREADY   = s6_AWREADY;
                m_WREADY    = s6_WREADY;
                m_BID       = s6_BID;
                m_BRESP     = s6_BRESP;
                m_BUSER     = s6_BUSER;
                m_BVALID    = s6_BVALID;
            end
            3'b111: begin
                m_AWREADY   = s7_AWREADY;
                m_WREADY    = s7_WREADY;
                m_BID       = s7_BID;
                m_BRESP     = s7_BRESP;
                m_BUSER     = s7_BUSER;
                m_BVALID    = s7_BVALID;
            end
            default: begin
                m_AWREADY   = 0;
                m_WREADY    = 0;
                m_BID       = 0;
                m_BRESP     = 0;
                m_BUSER     = 0;
                m_BVALID    = 0;
            end
        endcase
    end

    //---------------------------------------------------------
    //AWVALID signal multiplexing
    always @(*) begin
        case(awaddr[63:61])
            3'b000:begin
                s0_AWVALID  = s_AWVALID;
                s1_AWVALID  = 0;
                s2_AWVALID  = 0;
                s3_AWVALID  = 0;
                s4_AWVALID  = 0;
                s5_AWVALID  = 0;
                s6_AWVALID  = 0;
                s7_AWVALID  = 0;
            end
            3'b001:begin
                s0_AWVALID  = 0;
                s1_AWVALID  = s_AWVALID;
                s2_AWVALID  = 0;
                s3_AWVALID  = 0;
                s4_AWVALID  = 0;
                s5_AWVALID  = 0;
                s6_AWVALID  = 0;
                s7_AWVALID  = 0;
            end
            3'b010:begin
                s0_AWVALID  = 0;
                s1_AWVALID  = 0;
                s2_AWVALID  = s_AWVALID;
                s3_AWVALID  = 0;
                s4_AWVALID  = 0;
                s5_AWVALID  = 0;
                s6_AWVALID  = 0;
                s7_AWVALID  = 0;
            end
            3'b011:begin
                s0_AWVALID  = 0;
                s1_AWVALID  = 0;
                s2_AWVALID  = 0;
                s3_AWVALID  = s_AWVALID;
                s4_AWVALID  = 0;
                s5_AWVALID  = 0;
                s6_AWVALID  = 0;
                s7_AWVALID  = 0;
            end
            3'b100:begin
                s0_AWVALID  = 0;
                s1_AWVALID  = 0;
                s2_AWVALID  = 0;
                s3_AWVALID  = 0;
                s4_AWVALID  = s_AWVALID;
                s5_AWVALID  = 0;
                s6_AWVALID  = 0;
                s7_AWVALID  = 0;
            end
            3'b101:begin
                s0_AWVALID  = 0;
                s1_AWVALID  = 0;
                s2_AWVALID  = 0;
                s3_AWVALID  = 0;
                s4_AWVALID  = 0;
                s5_AWVALID  = s_AWVALID;
                s6_AWVALID  = 0;
                s7_AWVALID  = 0;
            end
            3'b110:begin
                s0_AWVALID  = 0;
                s1_AWVALID  = 0;
                s2_AWVALID  = 0;
                s3_AWVALID  = 0;
                s4_AWVALID  = 0;
                s5_AWVALID  = 0;
                s6_AWVALID  = s_AWVALID;
                s7_AWVALID  = 0;
            end
            3'b111:begin
                s0_AWVALID  = 0;
                s1_AWVALID  = 0;
                s2_AWVALID  = 0;
                s3_AWVALID  = 0;
                s4_AWVALID  = 0;
                s5_AWVALID  = 0;
                s6_AWVALID  = 0;
                s7_AWVALID  = s_AWVALID;
            end
            default: begin
                s0_AWVALID  = 0;
                s1_AWVALID  = 0;
                s2_AWVALID  = 0;
                s3_AWVALID  = 0;
                s4_AWVALID  = 0;
                s5_AWVALID  = 0;
                s6_AWVALID  = 0;
                s7_AWVALID  = 0;
            end
        endcase
    end

    //---------------------------------------------------------
    //BREADY signal multiplexing
    always @(*) begin
        case(awaddr[63:61])
            3'b000:begin
                s0_BREADY  = s_BREADY;
                s1_BREADY  = 0;
                s2_BREADY  = 0;
                s3_BREADY  = 0;
                s4_BREADY  = 0;
                s5_BREADY  = 0;
                s6_BREADY  = 0;
                s7_BREADY  = 0;
            end
            3'b001:begin
                s0_BREADY  = 0;
                s1_BREADY  = s_BREADY;
                s2_BREADY  = 0;
                s3_BREADY  = 0;
                s4_BREADY  = 0;
                s5_BREADY  = 0;
                s6_BREADY  = 0;
                s7_BREADY  = 0;
            end
            3'b010:begin
                s0_BREADY  = 0;
                s1_BREADY  = 0;
                s2_BREADY  = s_BREADY;
                s3_BREADY  = 0;
                s4_BREADY  = 0;
                s5_BREADY  = 0;
                s6_BREADY  = 0;
                s7_BREADY  = 0;
            end
            3'b011:begin
                s0_BREADY  = 0;
                s1_BREADY  = 0;
                s2_BREADY  = 0;
                s3_BREADY  = s_BREADY;
                s4_BREADY  = 0;
                s5_BREADY  = 0;
                s6_BREADY  = 0;
                s7_BREADY  = 0;
            end
            3'b100:begin
                s0_BREADY  = 0;
                s1_BREADY  = 0;
                s2_BREADY  = 0;
                s3_BREADY  = 0;
                s4_BREADY  = s_BREADY;
                s5_BREADY  = 0;
                s6_BREADY  = 0;
                s7_BREADY  = 0;
            end
            3'b101:begin
                s0_BREADY  = 0;
                s1_BREADY  = 0;
                s2_BREADY  = 0;
                s3_BREADY  = 0;
                s4_BREADY  = 0;
                s5_BREADY  = s_BREADY;
                s6_BREADY  = 0;
                s7_BREADY  = 0;
            end
            3'b110:begin
                s0_BREADY  = 0;
                s1_BREADY  = 0;
                s2_BREADY  = 0;
                s3_BREADY  = 0;
                s4_BREADY  = 0;
                s5_BREADY  = 0;
                s6_BREADY  = s_BREADY;
                s7_BREADY  = 0;
            end
            3'b111:begin
                s0_BREADY  = 0;
                s1_BREADY  = 0;
                s2_BREADY  = 0;
                s3_BREADY  = 0;
                s4_BREADY  = 0;
                s5_BREADY  = 0;
                s6_BREADY  = 0;
                s7_BREADY  = s_BREADY;
            end
            default: begin
                s0_BREADY  = 0;
                s1_BREADY  = 0;
                s2_BREADY  = 0;
                s3_BREADY  = 0;
                s4_BREADY  = 0;
                s5_BREADY  = 0;
                s6_BREADY  = 0;
                s7_BREADY  = 0;
            end
        endcase
    end

    //---------------------------------------------------------
    //WVALID signal multiplexing
    always @(*) begin
        case(awaddr[63:61])
            3'b000:begin
                s0_WVALID  = s_WVALID;
                s1_WVALID  = 0;
                s2_WVALID  = 0;
                s3_WVALID  = 0;
                s4_WVALID  = 0;
                s5_WVALID  = 0;
                s6_WVALID  = 0;
                s7_WVALID  = 0;
            end
            3'b001:begin
                s0_WVALID  = 0;
                s1_WVALID  = s_WVALID;
                s2_WVALID  = 0;
                s3_WVALID  = 0;
                s4_WVALID  = 0;
                s5_WVALID  = 0;
                s6_WVALID  = 0;
                s7_WVALID  = 0;
            end
            3'b010:begin
                s0_WVALID  = 0;
                s1_WVALID  = 0;
                s2_WVALID  = s_WVALID;
                s3_WVALID  = 0;
                s4_WVALID  = 0;
                s5_WVALID  = 0;
                s6_WVALID  = 0;
                s7_WVALID  = 0;
            end
            3'b011:begin
                s0_WVALID  = 0;
                s1_WVALID  = 0;
                s2_WVALID  = 0;
                s3_WVALID  = s_WVALID;
                s4_WVALID  = 0;
                s5_WVALID  = 0;
                s6_WVALID  = 0;
                s7_WVALID  = 0;
            end
            3'b100:begin
                s0_WVALID  = 0;
                s1_WVALID  = 0;
                s2_WVALID  = 0;
                s3_WVALID  = 0;
                s4_WVALID  = s_WVALID;
                s5_WVALID  = 0;
                s6_WVALID  = 0;
                s7_WVALID  = 0;
            end
            3'b101:begin
                s0_WVALID  = 0;
                s1_WVALID  = 0;
                s2_WVALID  = 0;
                s3_WVALID  = 0;
                s4_WVALID  = 0;
                s5_WVALID  = s_WVALID;
                s6_WVALID  = 0;
                s7_WVALID  = 0;
            end
            3'b110:begin
                s0_WVALID  = 0;
                s1_WVALID  = 0;
                s2_WVALID  = 0;
                s3_WVALID  = 0;
                s4_WVALID  = 0;
                s5_WVALID  = 0;
                s6_WVALID  = s_WVALID;
                s7_WVALID  = 0;
            end
            3'b111:begin
                s0_WVALID  = 0;
                s1_WVALID  = 0;
                s2_WVALID  = 0;
                s3_WVALID  = 0;
                s4_WVALID  = 0;
                s5_WVALID  = 0;
                s6_WVALID  = 0;
                s7_WVALID  = s_WVALID;
            end
            default: begin
                s0_WVALID  = 0;
                s1_WVALID  = 0;
                s2_WVALID  = 0;
                s3_WVALID  = 0;
                s4_WVALID  = 0;
                s5_WVALID  = 0;
                s6_WVALID  = 0;
                s7_WVALID  = 0;
            end
        endcase
    end

endmodule
