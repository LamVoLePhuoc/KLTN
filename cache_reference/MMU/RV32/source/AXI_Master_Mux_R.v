// Module Name: AXI4_Master_Mux_R
// Project Name: AXI4 Interconnect
// Description: AXI4 Read Address Channel Multiplexer
// Function: This module implements a multiplexer for the AXI4 read address channel. 
//      It selects one of the four masters based on their request signals and forwards the selected master's read address and control signals to the slave. 
//      The module also handles the read data channel by forwarding the read data from the selected master to the slave.

`timescale 1ns/1ns

module AXI_Master_Mux_R (
    /********* Clock & Reset *********/
    input                       ACLK,
    input      	                ARESETn,
    /********** Master 0 **********/
    // Read address channel
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
    output reg                  m0_ARREADY,
    // Read data channel
    output reg                  m0_RVALID,
    input                       m0_RREADY,
    /********** Master 1 **********/
    // Read address channel
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
    output reg                  m1_ARREADY,
    // Read data channel
    output reg                  m1_RVALID,
    input                       m1_RREADY,
    /********** Master 2 **********/
    // Read address channel
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
    output reg                  m2_ARREADY,
    // Read data channel
    output reg                  m2_RVALID,
    input                       m2_RREADY,
    /********** Master 3 **********/
    // Read address channel
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
    output reg                  m3_ARREADY,
    // Read data channel
    output reg                  m3_RVALID,
    input                       m3_RREADY,
    /******** Slave Common Signals ********/
    // Read address channel
    output reg [31:0]   s_ARID,
    output reg [31:0] s_ARADDR,
    output reg [7:0]            s_ARLEN,
    output reg [2:0]            s_ARSIZE,
    output reg [1:0]            s_ARBURST,
    output reg                  s_ARLOCK,
    output reg [3:0]            s_ARCACHE,
    output reg [2:0]            s_ARPROT,
    output reg [3:0]            s_ARQOS,
    output reg [3:0]            s_ARREGION,
    output reg [1023:0] s_ARUSER,
    output reg                  s_ARVALID,
    // Read data channel
    output reg                  s_RREADY,
    /******** Master Common Signals ********/
    input                       m_ARREADY,
    input                       m_RVALID,
    /******** Chip Select Signals ********/
    input                       m0_rgrnt,
    input                       m1_rgrnt,
    input                       m2_rgrnt,
    input                       m3_rgrnt
);

    //=========================================================
    // Read path multiplexed master signals

    //---------------------------------------------------------
    // Other signal multiplexing
    always @(*) begin
        case({m0_rgrnt,m1_rgrnt,m2_rgrnt,m3_rgrnt})
            4'b1000: begin
                s_ARID      =   m0_ARID;
                s_ARADDR    =   m0_ARADDR;
                s_ARLEN     =   m0_ARLEN;
                s_ARSIZE    =   m0_ARSIZE;
                s_ARBURST   =   m0_ARBURST;
                s_ARLOCK    =   m0_ARLOCK;
                s_ARCACHE   =   m0_ARCACHE;
                s_ARPROT    =   m0_ARPROT;
                s_ARQOS     =   m0_ARQOS;
                s_ARREGION  =   m0_ARREGION;
                s_ARUSER    =   m0_ARUSER;
                s_ARVALID   =   m0_ARVALID;
                s_RREADY    =   m0_RREADY;
            end
            4'b0100: begin
                s_ARID      =   m1_ARID;
                s_ARADDR    =   m1_ARADDR;
                s_ARLEN     =   m1_ARLEN;
                s_ARSIZE    =   m1_ARSIZE;
                s_ARBURST   =   m1_ARBURST;
                s_ARLOCK    =   m1_ARLOCK;
                s_ARCACHE   =   m1_ARCACHE;
                s_ARPROT    =   m1_ARPROT;
                s_ARQOS     =   m1_ARQOS;
                s_ARREGION  =   m1_ARREGION;
                s_ARUSER    =   m1_ARUSER;
                s_ARVALID   =   m1_ARVALID;
                s_RREADY    =   m1_RREADY;
            end
            4'b0010: begin
                s_ARID      =   m2_ARID;
                s_ARADDR    =   m2_ARADDR;
                s_ARLEN     =   m2_ARLEN;
                s_ARSIZE    =   m2_ARSIZE;
                s_ARBURST   =   m2_ARBURST;
                s_ARLOCK    =   m2_ARLOCK;
                s_ARCACHE   =   m2_ARCACHE;
                s_ARPROT    =   m2_ARPROT;
                s_ARQOS     =   m2_ARQOS;
                s_ARREGION  =   m2_ARREGION;
                s_ARUSER    =   m2_ARUSER;
                s_ARVALID   =   m2_ARVALID;
                s_RREADY    =   m2_RREADY;
            end
            4'b0001: begin
                s_ARID      =   m3_ARID;
                s_ARADDR    =   m3_ARADDR;
                s_ARLEN     =   m3_ARLEN;
                s_ARSIZE    =   m3_ARSIZE;
                s_ARBURST   =   m3_ARBURST;
                s_ARLOCK    =   m3_ARLOCK;
                s_ARCACHE   =   m3_ARCACHE;
                s_ARPROT    =   m3_ARPROT;
                s_ARQOS     =   m3_ARQOS;
                s_ARREGION  =   m3_ARREGION;
                s_ARUSER    =   m3_ARUSER;
                s_ARVALID   =   m3_ARVALID;
                s_RREADY    =   m3_RREADY;
            end
            default: begin
                s_ARID      =   {ID_WIDTH{1'b0}};
                s_ARADDR    =   {ADDR_WIDTH{1'b0}};
                s_ARLEN     =   8'h0;
                s_ARSIZE    =   3'h0;
                s_ARBURST   =   2'h0;
                s_ARLOCK    =   1'b0;
                s_ARCACHE   =   4'h0;
                s_ARPROT    =   3'h0;
                s_ARQOS     =   4'h0;
                s_ARREGION  =   4'h0;
                s_ARUSER    =   {USER_WIDTH{1'b0}};
                s_ARVALID   =   1'b0;
                s_RREADY    =   1'b0;
            end
        endcase
    end

    //---------------------------------------------------------
    // ARREADY signal multiplexing
    always @(*) begin
        case({m0_rgrnt,m1_rgrnt,m2_rgrnt,m3_rgrnt})
            4'b1000: begin
                m0_ARREADY  = m_ARREADY;
                m1_ARREADY  = 1'b0;
                m2_ARREADY  = 1'b0;
                m3_ARREADY  = 1'b0;
            end
            4'b0100: begin
                m0_ARREADY  = 1'b0;
                m1_ARREADY  = m_ARREADY;
                m2_ARREADY  = 1'b0;
                m3_ARREADY  = 1'b0;
            end
            4'b0010: begin
                m0_ARREADY  = 1'b0;
                m1_ARREADY  = 1'b0;
                m2_ARREADY  = m_ARREADY;
                m3_ARREADY  = 1'b0;
            end
            4'b0001: begin
                m0_ARREADY  = 1'b0;
                m1_ARREADY  = 1'b0;
                m2_ARREADY  = 1'b0;
                m3_ARREADY  = m_ARREADY;
            end
            default: begin
                m0_ARREADY  = 1'b0;
                m1_ARREADY  = 1'b0;
                m2_ARREADY  = 1'b0;
                m3_ARREADY  = 1'b0;
            end
        endcase
    end

    //---------------------------------------------------------
    // RVALID signal multiplexing
    always @(*) begin
        case({m0_rgrnt,m1_rgrnt,m2_rgrnt,m3_rgrnt})
            4'b1000: begin
                m0_RVALID  = m_RVALID;
                m1_RVALID  = 1'b0;
                m2_RVALID  = 1'b0;
                m3_RVALID  = 1'b0;
            end
            4'b0100: begin
                m0_RVALID  = 1'b0;
                m1_RVALID  = m_RVALID;
                m2_RVALID  = 1'b0;
                m3_RVALID  = 1'b0;
            end
            4'b0010: begin
                m0_RVALID  = 1'b0;
                m1_RVALID  = 1'b0;
                m2_RVALID  = m_RVALID;
                m3_RVALID  = 1'b0;
            end
            4'b0001: begin
                m0_RVALID  = 1'b0;
                m1_RVALID  = 1'b0;
                m2_RVALID  = 1'b0;
                m3_RVALID  = m_RVALID;
            end
            default: begin
                m0_RVALID  = 1'b0;
                m1_RVALID  = 1'b0;
                m2_RVALID  = 1'b0;
                m3_RVALID  = 1'b0;
            end
        endcase
    end

endmodule