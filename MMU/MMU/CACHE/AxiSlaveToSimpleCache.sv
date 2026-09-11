module AxiSlaveToSimpleCache #(
    parameter int ADDR_WIDTH       = 32,
    parameter int DATA_WIDTH       = 256,
    parameter int AXI_ID_WIDTH     = 8,
    parameter int AXI_LEN_WIDTH    = 3,
    parameter int AXI_SIZE_WIDTH   = 3,
    parameter int AXI_BURST_WIDTH  = 2,
    parameter int AXI_RESP_WIDTH   = 2
) (
    input  wire                       clk,
    input  wire                       reset,

    input  wire [AXI_ID_WIDTH-1:0]    s_AWID,
    input  wire [ADDR_WIDTH-1:0]      s_AWADDR,
    input  wire [AXI_BURST_WIDTH-1:0] s_AWBURST,
    input  wire [AXI_LEN_WIDTH-1:0]   s_AWLEN,
    input  wire [AXI_SIZE_WIDTH-1:0]  s_AWSIZE,
    input  wire                       s_AWVALID,
    output reg                        s_AWREADY,

    input  wire [DATA_WIDTH-1:0]      s_WDATA,
    input  wire                       s_WLAST,
    input  wire                       s_WVALID,
    output reg                        s_WREADY,

    output reg  [AXI_ID_WIDTH-1:0]    s_BID,
    output reg  [AXI_RESP_WIDTH-1:0]  s_BRESP,
    output reg                        s_BVALID,
    input  wire                       s_BREADY,

    input  wire [AXI_ID_WIDTH-1:0]    s_ARID,
    input  wire [ADDR_WIDTH-1:0]      s_ARADDR,
    input  wire [AXI_BURST_WIDTH-1:0] s_ARBURST,
    input  wire [AXI_LEN_WIDTH-1:0]   s_ARLEN,
    input  wire [AXI_SIZE_WIDTH-1:0]  s_ARSIZE,
    input  wire                       s_ARVALID,
    output reg                        s_ARREADY,

    output reg  [AXI_ID_WIDTH-1:0]    s_RID,
    output reg  [DATA_WIDTH-1:0]      s_RDATA,
    output reg  [AXI_RESP_WIDTH-1:0]  s_RRESP,
    output reg                        s_RLAST,
    output reg                        s_RVALID,
    input  wire                       s_RREADY,

    output reg  [ADDR_WIDTH-1:0]      cache_addr,
    output reg                        cache_read,
    output reg                        cache_write,
    output reg  [DATA_WIDTH-1:0]      cache_wdata,
    input  wire [DATA_WIDTH-1:0]      cache_rdata,
    input  wire                       cache_ready
);

    timeunit 1ns; timeprecision 1ps;

    localparam logic [AXI_RESP_WIDTH-1:0] AXI_RESP_OKAY = 2'b00;
    localparam logic [2:0] IDLE       = 3'd0;
    localparam logic [2:0] WR_DATA    = 3'd1;
    localparam logic [2:0] WR_CACHE   = 3'd2;
    localparam logic [2:0] WR_RESP    = 3'd3;
    localparam logic [2:0] RD_CACHE   = 3'd4;
    localparam logic [2:0] RD_RESP    = 3'd5;

    reg [2:0] state, next_state;
    reg [AXI_ID_WIDTH-1:0] id_q;
    reg [ADDR_WIDTH-1:0] addr_q;
    reg [DATA_WIDTH-1:0] wdata_q;
    reg [DATA_WIDTH-1:0] rdata_q;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            id_q <= '0;
            addr_q <= '0;
            wdata_q <= '0;
            rdata_q <= '0;
        end else begin
            state <= next_state;

            if (state == IDLE && s_AWVALID && s_AWREADY) begin
                id_q <= s_AWID;
                addr_q <= s_AWADDR;
            end else if (state == IDLE && s_ARVALID && s_ARREADY) begin
                id_q <= s_ARID;
                addr_q <= s_ARADDR;
            end

            if (state == WR_DATA && s_WVALID && s_WREADY) begin
                wdata_q <= s_WDATA;
            end

            if (state == RD_CACHE && cache_ready) begin
                rdata_q <= cache_rdata;
            end
        end
    end

    always_comb begin
        next_state  = state;
        s_AWREADY   = 1'b0;
        s_WREADY    = 1'b0;
        s_BID       = id_q;
        s_BRESP     = AXI_RESP_OKAY;
        s_BVALID    = 1'b0;
        s_ARREADY   = 1'b0;
        s_RID       = id_q;
        s_RDATA     = rdata_q;
        s_RRESP     = AXI_RESP_OKAY;
        s_RLAST     = 1'b1;
        s_RVALID    = 1'b0;
        cache_addr  = addr_q;
        cache_read  = 1'b0;
        cache_write = 1'b0;
        cache_wdata = wdata_q;

        unique case (state)
            IDLE: begin
                if (s_AWVALID) begin
                    s_AWREADY = 1'b1;
                    next_state = WR_DATA;
                end else if (s_ARVALID) begin
                    s_ARREADY = 1'b1;
                    next_state = RD_CACHE;
                end
            end

            WR_DATA: begin
                s_WREADY = 1'b1;
                if (s_WVALID) begin
                    next_state = WR_CACHE;
                end
            end

            WR_CACHE: begin
                cache_addr = addr_q;
                cache_wdata = wdata_q;
                cache_write = 1'b1;
                if (cache_ready) begin
                    next_state = WR_RESP;
                end
            end

            WR_RESP: begin
                s_BVALID = 1'b1;
                if (s_BREADY) begin
                    next_state = IDLE;
                end
            end

            RD_CACHE: begin
                cache_addr = addr_q;
                cache_read = 1'b1;
                if (cache_ready) begin
                    next_state = RD_RESP;
                end
            end

            RD_RESP: begin
                s_RVALID = 1'b1;
                s_RDATA  = rdata_q;
                if (s_RREADY) begin
                    next_state = IDLE;
                end
            end

            default: begin
                next_state = IDLE;
            end
        endcase
    end

endmodule
