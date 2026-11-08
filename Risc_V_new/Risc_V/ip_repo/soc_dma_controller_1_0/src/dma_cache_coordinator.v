`timescale 1ns / 1ps

// Orders a non-coherent DMA transfer against the CPU caches:
//   quiesce buffer -> pre-DMA clean/invalidate -> DMA -> post-DMA
//   clean/invalidate -> completion.
// The cache-maintenance request is a one-cycle pulse.  Completion is never
// fabricated by the watchdog: without a cancel/drain protocol, returning to
// idle while AXI or cache traffic is outstanding would be unsafe.  Once DMA
// has started, post-maintenance is performed even after a DMA error because a
// failed AXI write response may still have modified part of the destination.
module dma_cache_coordinator #(
    parameter [31:0] TIMEOUT_CYCLES = 32'd1000000
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        request_valid,
    output wire        request_ready,
    input  wire [31:0] request_src_addr,
    input  wire [31:0] request_dst_addr,
    input  wire [31:0] request_length_bytes,
    input  wire        buffer_quiesced,

    output reg         cache_flush,
    input  wire        cache_flush_busy,
    input  wire        cache_flush_done,
    input  wire        cache_flush_error,

    output reg         dma_cmd_valid,
    input  wire        dma_cmd_ready,
    output reg  [31:0] dma_cmd_src_addr,
    output reg  [31:0] dma_cmd_dst_addr,
    output reg  [31:0] dma_cmd_length_bytes,
    input  wire        dma_busy,
    input  wire        dma_done,
    input  wire        dma_error,
    input  wire        dma_progress,

    output wire        busy,
    output reg         done,
    output reg         error,
    output reg  [2:0]  error_code
);
    localparam [2:0]
        ERR_NONE          = 3'd0,
        ERR_PRE_FLUSH     = 3'd1,
        ERR_DMA           = 3'd2,
        ERR_POST_FLUSH    = 3'd3,
        ERR_TIMEOUT       = 3'd4;

    localparam [3:0]
        ST_IDLE      = 4'd0,
        ST_PRE_REQ   = 4'd1,
        ST_PRE_WAIT  = 4'd2,
        ST_DMA_START = 4'd3,
        ST_DMA_WAIT  = 4'd4,
        ST_POST_REQ  = 4'd5,
        ST_POST_WAIT = 4'd6;

    reg [3:0] state;
    reg [31:0] timeout_count;
    reg timeout_seen;

    assign request_ready = (state == ST_IDLE) && buffer_quiesced &&
                           !cache_flush_busy && !dma_busy;
    assign busy = (state != ST_IDLE);

    always @(*) begin
        cache_flush  = (state == ST_PRE_REQ) || (state == ST_POST_REQ);
        dma_cmd_valid = (state == ST_DMA_START);
    end

    always @(posedge clk) begin
        if (rst) begin
            state                <= ST_IDLE;
            timeout_count        <= 32'd0;
            timeout_seen         <= 1'b0;
            dma_cmd_src_addr     <= 32'd0;
            dma_cmd_dst_addr     <= 32'd0;
            dma_cmd_length_bytes <= 32'd0;
            done                 <= 1'b0;
            error                <= 1'b0;
            error_code           <= ERR_NONE;
        end
        else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    timeout_count <= 32'd0;
                    if (request_valid && request_ready) begin
                        dma_cmd_src_addr     <= request_src_addr;
                        dma_cmd_dst_addr     <= request_dst_addr;
                        dma_cmd_length_bytes <= request_length_bytes;
                        error                <= 1'b0;
                        error_code           <= ERR_NONE;
                        timeout_seen         <= 1'b0;
                        state                <= ST_PRE_REQ;
                    end
                end

                ST_PRE_REQ: begin
                    timeout_count <= 32'd0;
                    state <= ST_PRE_WAIT;
                end

                ST_PRE_WAIT: begin
                    if (cache_flush_done) begin
                        timeout_count <= 32'd0;
                        if (cache_flush_error || timeout_seen) begin
                            error      <= 1'b1;
                            error_code <= cache_flush_error ? ERR_PRE_FLUSH : ERR_TIMEOUT;
                            done       <= 1'b1;
                            state      <= ST_IDLE;
                        end
                        else begin
                            timeout_seen <= 1'b0;
                            state <= ST_DMA_START;
                        end
                    end
                    else if ((TIMEOUT_CYCLES != 0) && !timeout_seen &&
                             (timeout_count >= TIMEOUT_CYCLES-1)) begin
                        // Diagnostic only.  Keep waiting for the real cache
                        // completion so no late writeback can race a DMA.
                        error      <= 1'b1;
                        error_code <= ERR_TIMEOUT;
                        timeout_seen <= 1'b1;
                    end
                    else if (!timeout_seen)
                        timeout_count <= timeout_count + 1'b1;
                end

                ST_DMA_START: begin
                    if (dma_cmd_valid && dma_cmd_ready) begin
                        timeout_count <= 32'd0;
                        state <= ST_DMA_WAIT;
                    end
                end

                ST_DMA_WAIT: begin
                    if (dma_done) begin
                        if (dma_error) begin
                            error      <= 1'b1;
                            error_code <= ERR_DMA;
                        end
                        // Always restore the CPU cache view after DMA was
                        // issued.  A BRESP error does not guarantee that no
                        // destination beat reached memory.
                        timeout_count <= 32'd0;
                        timeout_seen  <= 1'b0;
                        state <= ST_POST_REQ;
                    end
                    else if (dma_progress) begin
                        // TIMEOUT_CYCLES is an inactivity watchdog.  Long,
                        // healthy transfers may legitimately take many times
                        // this value, so restart the timer on each AXI
                        // handshake instead of timing the whole command.
                        timeout_count <= 32'd0;
                    end
                    else if ((TIMEOUT_CYCLES != 0) && !timeout_seen &&
                             (timeout_count >= TIMEOUT_CYCLES-1)) begin
                        error      <= 1'b1;
                        error_code <= ERR_TIMEOUT;
                        timeout_seen <= 1'b1;
                    end
                    else if (!timeout_seen)
                        timeout_count <= timeout_count + 1'b1;
                end

                ST_POST_REQ: begin
                    timeout_count <= 32'd0;
                    state <= ST_POST_WAIT;
                end

                ST_POST_WAIT: begin
                    if (cache_flush_done) begin
                        if (cache_flush_error) begin
                            error      <= 1'b1;
                            error_code <= ERR_POST_FLUSH;
                        end
                        else if (timeout_seen) begin
                            error      <= 1'b1;
                            error_code <= ERR_TIMEOUT;
                        end
                        else if (!error) begin
                            error      <= 1'b0;
                            error_code <= ERR_NONE;
                        end
                        done       <= 1'b1;
                        timeout_count <= 32'd0;
                        timeout_seen <= 1'b0;
                        state      <= ST_IDLE;
                    end
                    else if ((TIMEOUT_CYCLES != 0) && !timeout_seen &&
                             (timeout_count >= TIMEOUT_CYCLES-1)) begin
                        error      <= 1'b1;
                        error_code <= ERR_TIMEOUT;
                        timeout_seen <= 1'b1;
                    end
                    else if (!timeout_seen)
                        timeout_count <= timeout_count + 1'b1;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule
