module SimpleCacheToAxiMaster #(
    parameter int ADDR_WIDTH      = 32,
    parameter int DATA_WIDTH      = 256,
    parameter int AXI_ID_WIDTH    = 5,
    parameter int AXI_LEN_WIDTH   = 3,
    parameter int AXI_SIZE_WIDTH  = 3,
    parameter int AXI_BURST_WIDTH = 2,
    parameter int AXI_RESP_WIDTH  = 2,
    parameter int MASTER_ID       = 0
) (
    input  wire                       clk,
    input  wire                       reset,

    input  wire [ADDR_WIDTH-1:0]      req_addr,
    input  wire                       req_read,
    input  wire                       req_write,
    input  wire [DATA_WIDTH-1:0]      req_wdata,
    output reg  [DATA_WIDTH-1:0]      resp_rdata,
    output reg                        resp_ready,

    output reg  [AXI_ID_WIDTH-1:0]    m_AWID,
    output reg  [ADDR_WIDTH-1:0]      m_AWADDR,
    output reg  [AXI_BURST_WIDTH-1:0] m_AWBURST,
    output reg  [AXI_LEN_WIDTH-1:0]   m_AWLEN,
    output reg  [AXI_SIZE_WIDTH-1:0]  m_AWSIZE,
    output reg                        m_AWVALID,
    input  wire                       m_AWREADY,

    output reg  [DATA_WIDTH-1:0]      m_WDATA,
    output reg                        m_WLAST,
    output reg                        m_WVALID,
    input  wire                       m_WREADY,

    input  wire [AXI_ID_WIDTH-1:0]    m_BID,
    input  wire [AXI_RESP_WIDTH-1:0]  m_BRESP,
    input  wire                       m_BVALID,
    output reg                        m_BREADY,

    output reg  [AXI_ID_WIDTH-1:0]    m_ARID,
    output reg  [ADDR_WIDTH-1:0]      m_ARADDR,
    output reg  [AXI_BURST_WIDTH-1:0] m_ARBURST,
    output reg  [AXI_LEN_WIDTH-1:0]   m_ARLEN,
    output reg  [AXI_SIZE_WIDTH-1:0]  m_ARSIZE,
    output reg                        m_ARVALID,
    input  wire                       m_ARREADY,

    input  wire [AXI_ID_WIDTH-1:0]    m_RID,
    input  wire [DATA_WIDTH-1:0]      m_RDATA,
    input  wire [AXI_RESP_WIDTH-1:0]  m_RRESP,
    input  wire                       m_RLAST,
    input  wire                       m_RVALID,
    output reg                        m_RREADY
);

    timeunit 1ns; timeprecision 1ps;

    localparam logic [AXI_BURST_WIDTH-1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [2:0] IDLE    = 3'd0;
    localparam logic [2:0] WR_ADDR = 3'd1;
    localparam logic [2:0] WR_DATA = 3'd2;
    localparam logic [2:0] WR_RESP = 3'd3;
    localparam logic [2:0] RD_ADDR = 3'd4;
    localparam logic [2:0] RD_DATA = 3'd5;

    localparam int AXI_SIZE = $clog2(DATA_WIDTH / 8);

    reg [2:0] state, next_state;
    reg [ADDR_WIDTH-1:0] addr_q;
    reg [DATA_WIDTH-1:0] wdata_q;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            addr_q <= '0;
            wdata_q <= '0;
        end else begin
            state <= next_state;
            if (state == IDLE && (req_read || req_write)) begin
                addr_q <= req_addr;
                wdata_q <= req_wdata;
            end
        end
    end

    always_comb begin
        next_state = state;
        resp_rdata = '0;
        resp_ready = 1'b0;

        m_AWID     = MASTER_ID;
        m_AWADDR   = addr_q;
        m_AWBURST  = AXI_BURST_INCR;
        m_AWLEN    = '0;
        m_AWSIZE   = AXI_SIZE_WIDTH'(AXI_SIZE);
        m_AWVALID  = 1'b0;

        m_WDATA    = wdata_q;
        m_WLAST    = 1'b1;
        m_WVALID   = 1'b0;

        m_BREADY   = 1'b0;

        m_ARID     = MASTER_ID;
        m_ARADDR   = addr_q;
        m_ARBURST  = AXI_BURST_INCR;
        m_ARLEN    = '0;
        m_ARSIZE   = AXI_SIZE_WIDTH'(AXI_SIZE);
        m_ARVALID  = 1'b0;

        m_RREADY   = 1'b0;

        unique case (state)
            IDLE: begin
                if (req_write) begin
                    next_state = WR_ADDR;
                end else if (req_read) begin
                    next_state = RD_ADDR;
                end
            end

            WR_ADDR: begin
                m_AWVALID = 1'b1;
                if (m_AWREADY) begin
                    next_state = WR_DATA;
                end
            end

            WR_DATA: begin
                m_WVALID = 1'b1;
                if (m_WREADY) begin
                    next_state = WR_RESP;
                end
            end

            WR_RESP: begin
                m_BREADY = 1'b1;
                if (m_BVALID) begin
                    resp_ready = 1'b1;
                    next_state = IDLE;
                end
            end

            RD_ADDR: begin
                m_ARVALID = 1'b1;
                if (m_ARREADY) begin
                    next_state = RD_DATA;
                end
            end

            RD_DATA: begin
                m_RREADY = 1'b1;
                if (m_RVALID) begin
                    resp_rdata = m_RDATA;
                    resp_ready = 1'b1;
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
