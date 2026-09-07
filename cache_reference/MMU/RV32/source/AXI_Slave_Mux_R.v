// Module Name: AXI_Slave_Mux_R
// Project Name: AXI4 Interconnect
// Description: AXI4 Read Address Channel Multiplexer
// Function: AXI bus read channel slave multiplexer module. 
//      It multiplexes the read address and data channels from multiple slaves to a single master. 
//      The module handles the read address and data channels, including the ARVALID, ARREADY, RVALID, RREADY, and other related signals. 
//      The module also includes a reset signal to initialize the registers and state machines.

`timescale 1ns/1ns

module AXI_Slave_Mux_R (
    /********* Clock & Reset *********/
    input                       ACLK,
    input      	                ARESETn,
    /********** Slave 0 **********/
    //Read Address Channel
    output reg                  s0_ARVALID,
    input	  		            s0_ARREADY,
    //Read Data Channel
    input	   [31:0]   s0_RID,
    input	   [31:0] s0_RDATA,
    input	   [1:0]	        s0_RRESP,
    input	  		            s0_RLAST,
    input	   [1023:0]	s0_RUSER,
    input	 		            s0_RVALID, 
    output reg                  s0_RREADY, 
    /********** Slave 1 **********/
    //Read Address Channel
    output reg                  s1_ARVALID,
    input	  		            s1_ARREADY,
    //Read Data Channel
    input	   [31:0]   s1_RID,
    input	   [31:0] s1_RDATA,
    input	   [1:0]	        s1_RRESP,
    input	  		            s1_RLAST,
    input	   [1023:0]	s1_RUSER,
    input	 		            s1_RVALID,
    output reg                  s1_RREADY,
    /********** Slave 2 **********/
    //Read Address Channel
    output reg                  s2_ARVALID,
    input	  		            s2_ARREADY,
    //Read Data Channel
    input	   [31:0]   s2_RID,
    input	   [31:0] s2_RDATA,
    input	   [1:0]	        s2_RRESP,
    input	  		            s2_RLAST,
    input	   [1023:0]	s2_RUSER,
    input	 		            s2_RVALID,
    output reg                  s2_RREADY,
    /********** Slave 3 **********/
    //Read Address Channel
    output reg                  s3_ARVALID,
    input	  		            s3_ARREADY,
    //Read Data Channel
    input	   [31:0]   s3_RID,
    input	   [31:0] s3_RDATA,
    input	   [1:0]	        s3_RRESP,
    input	  		            s3_RLAST,
    input	   [1023:0]	s3_RUSER,
    input	 		            s3_RVALID, 
    output reg                  s3_RREADY,
    /********** Slave 4 **********/
    //Read Address Channel
    output reg                  s4_ARVALID,
    input	  		            s4_ARREADY,
    //Read Data Channel
    input	   [31:0]   s4_RID,
    input	   [31:0] s4_RDATA,
    input	   [1:0]	        s4_RRESP,
    input	  		            s4_RLAST,
    input	   [1023:0]	s4_RUSER,
    input	 		            s4_RVALID, 
    output reg                  s4_RREADY,
    /********** Slave 5 **********/
    //Read Address Channel
    output reg                  s5_ARVALID,
    input	  		            s5_ARREADY,
    //Read Data Channel
    input	   [31:0]   s5_RID,
    input	   [31:0] s5_RDATA,
    input	   [1:0]	        s5_RRESP,
    input	  		            s5_RLAST,
    input	   [1023:0]	s5_RUSER,
    input	 		            s5_RVALID,
    output reg                  s5_RREADY,
    /********** Slave 6 **********/
    //Read Address Channel
    output reg                  s6_ARVALID,
    input	  		            s6_ARREADY,
    //Read Data Channel
    input	   [31:0]   s6_RID,
    input	   [31:0] s6_RDATA,
    input	   [1:0]	        s6_RRESP,
    input	  		            s6_RLAST,
    input	   [1023:0]	s6_RUSER,
    input	 		            s6_RVALID, 
    output reg                  s6_RREADY, 
    /********** Slave 7 **********/
    //Read Address Channel
    output reg                  s7_ARVALID,
    input	  		            s7_ARREADY,
    //Read Data Channel
    input	   [31:0]   s7_RID,
    input	   [31:0] s7_RDATA,
    input	   [1:0]	        s7_RRESP,
    input	  		            s7_RLAST,
    input	   [1023:0]	s7_RUSER,
    input	 		            s7_RVALID, 
    output reg                  s7_RREADY,
    /******** Master Common Signals ********/
    //Read Address Channel
    output reg	  		        m_ARREADY,
    //Read Data Channel
    output reg [31:0]   m_RID,
    output reg [31:0] m_RDATA,
    output reg [1:0]	        m_RRESP,
    output reg		            m_RLAST,
    output reg [1023:0]	m_RUSER,
    output reg	                m_RVALID, 
    /******** Slave Common Signals ********/
    //Read Address Channel
    input     [31:0]	s_ARADDR,
    input                       s_ARVALID,
    //Read Data Channel
    input                       s_RREADY  
);

    //=========================================================
    //Constant Definition
    parameter   TCO     =   1;  //Register Delay


    //=========================================================
    //Read Address Register
    reg [63:0]    araddr;     //Read Address Register

    always @(posedge ACLK or negedge ARESETn)begin
        if(!ARESETn)
            araddr <= #TCO 0;
        else if(s_ARVALID)                  //Store address when read address handshake signal starts
            araddr <= #TCO s_ARADDR;
        else
            araddr <= #TCO araddr;
    end



    //=========================================================
    //Read Path Slave Signal Multiplexing

    //---------------------------------------------------------
    //Other Signal Multiplexing
    always @(*) begin
        case(araddr[63-:3])
            3'b000: begin
                m_ARREADY   = s0_ARREADY;
                m_RID       = s0_RID;
                m_RDATA     = s0_RDATA;
                m_RRESP     = s0_RRESP;
                m_RLAST     = s0_RLAST;
                m_RUSER     = s0_RUSER;
                m_RVALID    = s0_RVALID;
            end
            3'b001: begin
                m_ARREADY   = s1_ARREADY;
                m_RID       = s1_RID;
                m_RDATA     = s1_RDATA;
                m_RRESP     = s1_RRESP;
                m_RLAST     = s1_RLAST;
                m_RUSER     = s1_RUSER;
                m_RVALID    = s1_RVALID;
            end
            3'b010: begin
                m_ARREADY   = s2_ARREADY;
                m_RID       = s2_RID;
                m_RDATA     = s2_RDATA;
                m_RRESP     = s2_RRESP;
                m_RLAST     = s2_RLAST;
                m_RUSER     = s2_RUSER;
                m_RVALID    = s2_RVALID;
            end
            3'b011: begin
                m_ARREADY   = s3_ARREADY;
                m_RID       = s3_RID;
                m_RDATA     = s3_RDATA;
                m_RRESP     = s3_RRESP;
                m_RLAST     = s3_RLAST;
                m_RUSER     = s3_RUSER;
                m_RVALID    = s3_RVALID;
            end
            3'b100: begin
                m_ARREADY   = s4_ARREADY;
                m_RID       = s4_RID;
                m_RDATA     = s4_RDATA;
                m_RRESP     = s4_RRESP;
                m_RLAST     = s4_RLAST;
                m_RUSER     = s4_RUSER;
                m_RVALID    = s4_RVALID;
            end
            3'b101: begin
                m_ARREADY   = s5_ARREADY;
                m_RID       = s5_RID;
                m_RDATA     = s5_RDATA;
                m_RRESP     = s5_RRESP;
                m_RLAST     = s5_RLAST;
                m_RUSER     = s5_RUSER;
                m_RVALID    = s5_RVALID;
            end
            3'b110: begin
                m_ARREADY   = s6_ARREADY;
                m_RID       = s6_RID;
                m_RDATA     = s6_RDATA;
                m_RRESP     = s6_RRESP;
                m_RLAST     = s6_RLAST;
                m_RUSER     = s6_RUSER;
                m_RVALID    = s6_RVALID;
            end
            3'b111: begin
                m_ARREADY   = s7_ARREADY;
                m_RID       = s7_RID;
                m_RDATA     = s7_RDATA;
                m_RRESP     = s7_RRESP;
                m_RLAST     = s7_RLAST;
                m_RUSER     = s7_RUSER;
                m_RVALID    = s7_RVALID;
            end
            default: begin
                m_ARREADY   = 0;
                m_RID       = 0;
                m_RDATA     = 0;
                m_RRESP     = 0;
                m_RLAST     = 0;
                m_RUSER     = 0;
                m_RVALID    = 0;
            end
        endcase
    end

    //---------------------------------------------------------
    //ARVALID Signal Multiplexing
    always @(*) begin
        case(araddr[63-:3])
            3'b000: begin
                s0_ARVALID  = s_ARVALID;
                s1_ARVALID  = 0;
                s2_ARVALID  = 0;
                s3_ARVALID  = 0;
                s4_ARVALID  = 0;
                s5_ARVALID  = 0;
                s6_ARVALID  = 0;
                s7_ARVALID  = 0;
            end
            3'b001: begin
                s0_ARVALID  = 0;
                s1_ARVALID  = s_ARVALID;
                s2_ARVALID  = 0;
                s3_ARVALID  = 0;
                s4_ARVALID  = 0;
                s5_ARVALID  = 0;
                s6_ARVALID  = 0;
                s7_ARVALID  = 0;
            end
            3'b010: begin
                s0_ARVALID  = 0;
                s1_ARVALID  = 0;
                s2_ARVALID  = s_ARVALID;
                s3_ARVALID  = 0;
                s4_ARVALID  = 0;
                s5_ARVALID  = 0;
                s6_ARVALID  = 0;
                s7_ARVALID  = 0;
            end
            3'b011: begin
                s0_ARVALID  = 0;
                s1_ARVALID  = 0;
                s2_ARVALID  = 0;
                s3_ARVALID  = s_ARVALID;
                s4_ARVALID  = 0;
                s5_ARVALID  = 0;
                s6_ARVALID  = 0;
                s7_ARVALID  = 0;
            end
            3'b100: begin
                s0_ARVALID  = 0;
                s1_ARVALID  = 0;
                s2_ARVALID  = 0;
                s3_ARVALID  = 0;
                s4_ARVALID  = s_ARVALID;
                s5_ARVALID  = 0;
                s6_ARVALID  = 0;
                s7_ARVALID  = 0;
            end
            3'b101: begin
                s0_ARVALID  = 0;
                s1_ARVALID  = 0;
                s2_ARVALID  = 0;
                s3_ARVALID  = 0;
                s4_ARVALID  = 0;
                s5_ARVALID  = s_ARVALID;
                s6_ARVALID  = 0;
                s7_ARVALID  = 0;
            end
            3'b110: begin
                s0_ARVALID  = 0;
                s1_ARVALID  = 0;
                s2_ARVALID  = 0;
                s3_ARVALID  = 0;
                s4_ARVALID  = 0;
                s5_ARVALID  = 0;
                s6_ARVALID  = s_ARVALID;
                s7_ARVALID  = 0;
            end
            3'b111: begin
                s0_ARVALID  = 0;
                s1_ARVALID  = 0;
                s2_ARVALID  = 0;
                s3_ARVALID  = 0;
                s4_ARVALID  = 0;
                s5_ARVALID  = 0;
                s6_ARVALID  = 0;
                s7_ARVALID  = s_ARVALID;
            end            
            default: begin
                s0_ARVALID  = 0;
                s1_ARVALID  = 0;
                s2_ARVALID  = 0;
                s3_ARVALID  = 0;
                s4_ARVALID  = 0;
                s5_ARVALID  = 0;
                s6_ARVALID  = 0;
                s7_ARVALID  = 0;
            end
        endcase
    end

    //---------------------------------------------------------
    //RREADY Signal Multiplexing
    always @(*) begin
        case(araddr[63-:3])
            3'b000: begin
                s0_RREADY  = s_RREADY;
                s1_RREADY  = 0;
                s2_RREADY  = 0;
                s3_RREADY  = 0;
                s4_RREADY  = 0;
                s5_RREADY  = 0;
                s6_RREADY  = 0;
                s7_RREADY  = 0;
            end
            3'b001: begin
                s0_RREADY  = 0;
                s1_RREADY  = s_RREADY;
                s2_RREADY  = 0;
                s3_RREADY  = 0;
                s4_RREADY  = 0;
                s5_RREADY  = 0;
                s6_RREADY  = 0;
                s7_RREADY  = 0;
            end
            3'b010: begin
                s0_RREADY  = 0;
                s1_RREADY  = 0;
                s2_RREADY  = s_RREADY;
                s3_RREADY  = 0;
                s4_RREADY  = 0;
                s5_RREADY  = 0;
                s6_RREADY  = 0;
                s7_RREADY  = 0;
            end
            3'b011: begin
                s0_RREADY  = 0;
                s1_RREADY  = 0;
                s2_RREADY  = 0;
                s3_RREADY  = s_RREADY;
                s4_RREADY  = 0;
                s5_RREADY  = 0;
                s6_RREADY  = 0;
                s7_RREADY  = 0;
            end
            3'b100: begin
                s0_RREADY  = 0;
                s1_RREADY  = 0;
                s2_RREADY  = 0;
                s3_RREADY  = 0;
                s4_RREADY  = s_RREADY;
                s5_RREADY  = 0;
                s6_RREADY  = 0;
                s7_RREADY  = 0;
            end
            3'b101: begin
                s0_RREADY  = 0;
                s1_RREADY  = 0;
                s2_RREADY  = 0;
                s3_RREADY  = 0;
                s4_RREADY  = 0;
                s5_RREADY  = s_RREADY;
                s6_RREADY  = 0;
                s7_RREADY  = 0;
            end
            3'b110: begin
                s0_RREADY  = 0;
                s1_RREADY  = 0;
                s2_RREADY  = 0;
                s3_RREADY  = 0;
                s4_RREADY  = 0;
                s5_RREADY  = 0;
                s6_RREADY  = s_RREADY;
                s7_RREADY  = 0;
            end
            3'b111: begin
                s0_RREADY  = 0;
                s1_RREADY  = 0;
                s2_RREADY  = 0;
                s3_RREADY  = 0;
                s4_RREADY  = 0;
                s5_RREADY  = 0;
                s6_RREADY  = 0;
                s7_RREADY  = s_RREADY;
            end            
            default: begin
                s0_RREADY  = 0;
                s1_RREADY  = 0;
                s2_RREADY  = 0;
                s3_RREADY  = 0;
                s4_RREADY  = 0;
                s5_RREADY  = 0;
                s6_RREADY  = 0;
                s7_RREADY  = 0;
            end
        endcase
    end

endmodule