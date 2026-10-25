`timescale 1ns / 1ps

// AXI4 memory-to-memory DMA engine.
//
// The engine is intentionally small and blocking: it reads one bounded burst
// into an internal buffer, then writes that burst before issuing the next one.
// This costs throughput compared with a deep, multi-outstanding DMA, but gives
// deterministic ordering and a compact correctness surface for the thesis SoC.
// Commands must be data-bus aligned and have a non-zero aligned byte length.
// Bursts never cross a 4 KiB AXI boundary, even when source and destination
// reach different boundaries within the same transfer.
module axi_memcpy_dma #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter MAX_BURST_LEN = 16
)(
    input  wire                  clk,
    input  wire                  rst,

    input  wire                  cmd_valid,
    output wire                  cmd_ready,
    input  wire [ADDR_WIDTH-1:0] cmd_src_addr,
    input  wire [ADDR_WIDTH-1:0] cmd_dst_addr,
    input  wire [31:0]           cmd_length_bytes,

    output wire                  busy,
    output reg                   done,
    output reg                   error,
    output wire                  progress,

    output reg  [ADDR_WIDTH-1:0] m_axi_araddr,
    output reg  [7:0]            m_axi_arlen,
    output wire [2:0]            m_axi_arsize,
    output wire [1:0]            m_axi_arburst,
    output reg                   m_axi_arvalid,
    input  wire                  m_axi_arready,

    input  wire [DATA_WIDTH-1:0] m_axi_rdata,
    input  wire [1:0]            m_axi_rresp,
    input  wire                  m_axi_rlast,
    input  wire                  m_axi_rvalid,
    output reg                   m_axi_rready,

    output reg  [ADDR_WIDTH-1:0] m_axi_awaddr,
    output reg  [7:0]            m_axi_awlen,
    output wire [2:0]            m_axi_awsize,
    output wire [1:0]            m_axi_awburst,
    output reg                   m_axi_awvalid,
    input  wire                  m_axi_awready,

    output reg  [DATA_WIDTH-1:0] m_axi_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_wstrb,
    output reg                   m_axi_wlast,
    output reg                   m_axi_wvalid,
    input  wire                  m_axi_wready,

    input  wire [1:0]            m_axi_bresp,
    input  wire                  m_axi_bvalid,
    output reg                   m_axi_bready
);
    localparam integer STRB_WIDTH = DATA_WIDTH / 8;

    function integer log2_int;
        input integer value;
        integer v;
        begin
            v = value - 1;
            log2_int = 0;
            while (v > 0) begin
                v = v / 2;
                log2_int = log2_int + 1;
            end
        end
    endfunction

    localparam [2:0] AXI_SIZE = log2_int(STRB_WIDTH);
    localparam [ADDR_WIDTH-1:0] ADDR_ALIGN_MASK = STRB_WIDTH - 1;
    localparam [31:0] LENGTH_ALIGN_MASK = STRB_WIDTH - 1;
    localparam [31:0] MAX_BURST_LEN_U = MAX_BURST_LEN;
    localparam [3:0]
        ST_IDLE  = 4'd0,
        ST_AR    = 4'd1,
        ST_READ  = 4'd2,
        ST_AW    = 4'd3,
        ST_WRITE = 4'd4,
        ST_BRESP = 4'd5,
        ST_R_DRAIN = 4'd6;

    reg [3:0] state;
    reg [ADDR_WIDTH-1:0] src_addr_r;
    reg [ADDR_WIDTH-1:0] dst_addr_r;
    reg [31:0] remaining_beats_r;
    reg [8:0] burst_beats_r;
    reg [8:0] read_index_r;
    reg [8:0] write_index_r;
    reg burst_error_r;
    reg [DATA_WIDTH-1:0] burst_buffer [0:MAX_BURST_LEN-1];

    integer k;

    function [8:0] choose_burst;
        input [ADDR_WIDTH-1:0] src_addr;
        input [ADDR_WIDTH-1:0] dst_addr;
        input [31:0] remaining_beats;
        reg [31:0] candidate;
        reg [31:0] src_to_boundary;
        reg [31:0] dst_to_boundary;
        begin
            candidate = remaining_beats;
            if (candidate > MAX_BURST_LEN_U)
                candidate = MAX_BURST_LEN_U;
            src_to_boundary = (32'd4096 - {20'd0, src_addr[11:0]}) >> AXI_SIZE;
            dst_to_boundary = (32'd4096 - {20'd0, dst_addr[11:0]}) >> AXI_SIZE;
            if (candidate > src_to_boundary)
                candidate = src_to_boundary;
            if (candidate > dst_to_boundary)
                candidate = dst_to_boundary;
            if (candidate < 1)
                candidate = 1;
            choose_burst = candidate[8:0];
        end
    endfunction

    wire command_aligned = ((cmd_src_addr & ADDR_ALIGN_MASK) ==
                            {ADDR_WIDTH{1'b0}}) &&
                           ((cmd_dst_addr & ADDR_ALIGN_MASK) ==
                            {ADDR_WIDTH{1'b0}}) &&
                           ((cmd_length_bytes & LENGTH_ALIGN_MASK) == 32'd0);
    wire [ADDR_WIDTH-1:0] burst_bytes_addr =
        {{(ADDR_WIDTH-9){1'b0}}, burst_beats_r} << AXI_SIZE;
    wire [31:0] burst_beats_32 = {23'd0, burst_beats_r};

    assign cmd_ready = (state == ST_IDLE);
    assign busy = (state != ST_IDLE);
    assign m_axi_arsize = AXI_SIZE;
    assign m_axi_awsize = AXI_SIZE;
    assign m_axi_arburst = 2'b01;
    assign m_axi_awburst = 2'b01;
    assign m_axi_wstrb = {STRB_WIDTH{1'b1}};

    // A watchdog must measure lack of forward progress, not the total time of
    // a multi-burst transfer.  Report every accepted AXI channel beat so the
    // coordinator can restart its inactivity timer while a legal transfer is
    // still advancing.
    assign progress = (m_axi_arvalid && m_axi_arready) ||
                      (m_axi_rvalid  && m_axi_rready)  ||
                      (m_axi_awvalid && m_axi_awready) ||
                      (m_axi_wvalid  && m_axi_wready)  ||
                      (m_axi_bvalid  && m_axi_bready);

    always @(*) begin
        m_axi_araddr  = src_addr_r;
        m_axi_arlen   = burst_beats_r[7:0] - 8'd1;
        m_axi_arvalid = (state == ST_AR);
        m_axi_rready  = (state == ST_READ) || (state == ST_R_DRAIN);

        m_axi_awaddr  = dst_addr_r;
        m_axi_awlen   = burst_beats_r[7:0] - 8'd1;
        m_axi_awvalid = (state == ST_AW);
        m_axi_wdata   = burst_buffer[write_index_r];
        m_axi_wlast   = (write_index_r == burst_beats_r - 1'b1);
        m_axi_wvalid  = (state == ST_WRITE);
        m_axi_bready  = (state == ST_BRESP);
    end

    always @(posedge clk) begin
        if (rst) begin
            state             <= ST_IDLE;
            src_addr_r        <= {ADDR_WIDTH{1'b0}};
            dst_addr_r        <= {ADDR_WIDTH{1'b0}};
            remaining_beats_r <= 32'd0;
            burst_beats_r     <= 9'd0;
            read_index_r      <= 9'd0;
            write_index_r     <= 9'd0;
            burst_error_r     <= 1'b0;
            done              <= 1'b0;
            error             <= 1'b0;
            for (k = 0; k < MAX_BURST_LEN; k = k + 1)
                burst_buffer[k] <= {DATA_WIDTH{1'b0}};
        end
        else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    error <= 1'b0;
                    if (cmd_valid) begin
                        if ((cmd_length_bytes == 0) || !command_aligned) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                        end
                        else begin
                            src_addr_r        <= cmd_src_addr;
                            dst_addr_r        <= cmd_dst_addr;
                            remaining_beats_r <= cmd_length_bytes >> AXI_SIZE;
                            burst_beats_r     <= choose_burst(cmd_src_addr,
                                                              cmd_dst_addr,
                                                              cmd_length_bytes >> AXI_SIZE);
                            read_index_r      <= 9'd0;
                            burst_error_r     <= 1'b0;
                            state             <= ST_AR;
                        end
                    end
                end

                ST_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        read_index_r  <= 9'd0;
                        state         <= ST_READ;
                    end
                end

                ST_READ: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        burst_buffer[read_index_r] <= m_axi_rdata;

                        if (read_index_r == burst_beats_r - 1'b1) begin
                            // Never copy a burst whose source read failed or
                            // whose RLAST position is malformed.  Writing the
                            // partially valid buffer would corrupt the
                            // destination and make the reported error unsafe.
                            if (!m_axi_rlast) begin
                                // The slave sent more beats than ARLEN. Drain
                                // until its eventual RLAST; returning idle here
                                // would leave an outstanding response capable
                                // of corrupting the next DMA command.
                                error <= 1'b1;
                                burst_error_r <= 1'b1;
                                state <= ST_R_DRAIN;
                            end
                            else if (burst_error_r || (m_axi_rresp != 2'b00)) begin
                                error <= 1'b1;
                                done  <= 1'b1;
                                state <= ST_IDLE;
                            end
                            else begin
                                write_index_r <= 9'd0;
                                state         <= ST_AW;
                            end
                        end
                        else if (m_axi_rlast) begin
                            // Early RLAST is a protocol error.  Abort without
                            // issuing a write containing incomplete data.
                            error <= 1'b1;
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end
                        else begin
                            if (m_axi_rresp != 2'b00)
                                burst_error_r <= 1'b1;
                            read_index_r <= read_index_r + 1'b1;
                        end
                    end
                end

                ST_R_DRAIN: begin
                    if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
                        error <= 1'b1;
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                ST_AW: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        write_index_r <= 9'd0;
                        state         <= ST_WRITE;
                    end
                end

                ST_WRITE: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (m_axi_wlast)
                            state <= ST_BRESP;
                        else
                            write_index_r <= write_index_r + 1'b1;
                    end
                end

                ST_BRESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        if (burst_error_r || (m_axi_bresp != 2'b00)) begin
                            error <= 1'b1;
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end
                        else if (remaining_beats_r == burst_beats_r) begin
                            done  <= 1'b1;
                            error <= 1'b0;
                            state <= ST_IDLE;
                        end
                        else begin
                            src_addr_r        <= src_addr_r + burst_bytes_addr;
                            dst_addr_r        <= dst_addr_r + burst_bytes_addr;
                            remaining_beats_r <= remaining_beats_r - burst_beats_32;
                            burst_beats_r     <= choose_burst(
                                src_addr_r + burst_bytes_addr,
                                dst_addr_r + burst_bytes_addr,
                                remaining_beats_r - burst_beats_32);
                            read_index_r  <= 9'd0;
                            burst_error_r <= 1'b0;
                            state         <= ST_AR;
                        end
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
