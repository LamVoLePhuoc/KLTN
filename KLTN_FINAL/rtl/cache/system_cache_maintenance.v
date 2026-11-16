`timescale 1ns / 1ps

// Sequence a software/DMA cache-maintenance request across the complete
// hierarchy.  Private L1 caches must drain first; only then may the shared L2
// be written back and invalidated.  The public done pulse therefore means
// external memory is coherent and it is safe to start a non-coherent DMA.
module system_cache_maintenance (
    input  wire clk,
    input  wire rst,
    input  wire request,

    output reg  l1_request,
    input  wire l1_busy,
    input  wire l1_done,
    input  wire l1_error,

    output reg  l2_request,
    input  wire l2_busy,
    input  wire l2_done,
    input  wire l2_error,

    output wire busy,
    output reg  done,
    output reg  error
);
    localparam [1:0] IDLE = 2'd0, WAIT_L1 = 2'd1, WAIT_L2 = 2'd2;

    reg [1:0] state;
    reg       request_seen;
    wire      request_rise = request && !request_seen;

    assign busy = (state != IDLE) || request_rise || l1_busy || l2_busy;

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            request_seen <= 1'b0;
            l1_request   <= 1'b0;
            l2_request   <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
        end
        else begin
            request_seen <= request;
            l1_request   <= 1'b0;
            l2_request   <= 1'b0;
            done         <= 1'b0;

            if (l1_error || l2_error)
                error <= 1'b1;

            case (state)
                IDLE: begin
                    if (request_rise) begin
                        // Clear the result of the preceding operation.  A new
                        // error remains sticky for the duration of this one.
                        error      <= 1'b0;
                        l1_request <= 1'b1;
                        state      <= WAIT_L1;
                    end
                end

                WAIT_L1: begin
                    if (l1_done) begin
                        l2_request <= 1'b1;
                        state      <= WAIT_L2;
                    end
                end

                WAIT_L2: begin
                    if (l2_done) begin
                        done  <= 1'b1;
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
