`timescale 1ns / 1ps

// Aggregates the four private-cache maintenance engines into one
// system/DMA-facing handshake.  The actual clean/invalidate request is
// broadcast directly to every core_l1_wrapper; this block only tracks
// completion.  A core is counted after it pulses done while idle, which
// prevents an earlier FENCE.I completion from satisfying a Cache_Flush
// that was queued behind it.
module cache_maintenance_tracker #(
    // Diagnostic only: a timeout must never fabricate completion because a
    // late write response could otherwise race a new DMA transaction.
    parameter integer WATCHDOG_CYCLES = 65536
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       request,
    input  wire [3:0] core_busy,
    input  wire [3:0] core_done,
    input  wire [3:0] core_error,
    output wire       busy,
    output reg        done,
    output reg        error
);
    reg request_seen;
    reg inflight;
    reg [3:0] done_seen;
    reg [31:0] watchdog_count;

    wire request_rise = request & ~request_seen;
    wire [3:0] idle_done = core_done & ~core_busy;
    wire [3:0] next_done_seen = done_seen | idle_done;

    // Assert immediately with the request edge so an external master
    // cannot observe a false idle cycle before inflight is registered.
    assign busy = inflight | request_rise | (|core_busy);

    always @(posedge clk) begin
        if (rst) begin
            request_seen <= 1'b0;
            inflight     <= 1'b0;
            done_seen    <= 4'b0;
            done         <= 1'b0;
            error        <= 1'b0;
            watchdog_count <= 32'b0;
        end
        else begin
            request_seen <= request;
            done         <= 1'b0;

            if (|core_error)
                error <= 1'b1;

            if (request_rise && !inflight) begin
                inflight  <= 1'b1;
                done_seen <= 4'b0;
                watchdog_count <= 32'b0;
            end

            if (inflight) begin
                done_seen <= next_done_seen;
                if ((WATCHDOG_CYCLES > 0) &&
                    (watchdog_count >= (WATCHDOG_CYCLES - 1))) begin
                    // Sticky diagnostic only. Keep inflight/busy asserted and
                    // wait for the real cache completions; aborting cannot be
                    // made safe without a cancel/drain protocol below L2.
                    error <= 1'b1;
                end
                else begin
                    watchdog_count <= watchdog_count + 32'd1;
                end
                if (&next_done_seen) begin
                    inflight  <= 1'b0;
                    done_seen <= 4'b0;
                    done      <= 1'b1;
                    watchdog_count <= 32'b0;
                end
            end
        end
    end
endmodule
