// interconnect: round-robin arbiter multiplexing 4 cores x (I-cache +
// D-cache) = 8 private-cache miss/write-through ports down to the single
// shared L2 port, plus coherence snoop-invalidate broadcast.
//
// Port index convention: requester 0..3 = core 0..3's I-cache,
// requester 4..7 = core 0..3's D-cache.
//
// Arbitration: a requester with req_read or req_write asserted is
// granted the L2 port and held there (address/data steady, matching the
// hold-until-ready convention every cache controller in this design
// already uses) until l2_ready pulses for it. The grant then advances to
// the next requester (round-robin) that has a pending request. This is
// intentionally simple (no QoS/priority) — good enough to demonstrate a
// working shared L2 + coherence path; a real design would want separate
// read/write channels and outstanding-request pipelining.
//
// Coherence: whenever a D-cache write-through completes (l2_ready pulses
// while a D-side requester is granted a write), the interconnect pulses
// snoop_en for the *other three* cores' D-cache snoop ports with that
// line's address, so any stale cached copy they hold is invalidated (see
// TagArray.sv's snoop port and D_CacheController.sv's write-through
// change). This is a simple invalidate-broadcast scheme, not a full
// MESI directory — sufficient for one shared writer to be seen by
// everyone else on their next access, which is what the Phase-2
// testbench exercises.
// Named mc_interconnect, not `interconnect` — the latter is a reserved
// SystemVerilog keyword (interconnect nets, IEEE 1800-2012) and can't be
// used as a module identifier; Vivado's xvlog rejects it with a
// confusing "syntax error near '('" at the instantiation site.
module mc_interconnect #(
    parameter NUM_CORES = 4
) (
    input  wire clk,
    input  wire rst_n,

    // 8 requester ports: [0:3]=I-cache of core 0..3, [4:7]=D-cache of core 0..3
    input  wire [31:0]  req_addr  [0:7],
    input  wire         req_read  [0:7],
    input  wire         req_write [0:7],
    input  wire [255:0] req_wdata [0:7],
    output wire [255:0] req_rdata [0:7],
    output wire         req_ready [0:7],

    // Shared L2 side
    output reg  [31:0]  l2_addr,
    output reg           l2_read,
    output reg           l2_write,
    output reg  [255:0] l2_wdata,
    input  wire [255:0] l2_rdata,
    input  wire          l2_ready,

    // Coherence snoop broadcast to each core's private D-cache
    // (index-matched to core 0..3; a core never invalidates itself)
    output reg  [NUM_CORES-1:0] snoop_en,
    output reg  [31:0]          snoop_addr
);

    timeunit 1ns; timeprecision 1ps;

    reg [2:0] grant;
    reg       granted_valid;
    reg [2:0] rr_ptr;

    wire any_pending = req_read[0] | req_write[0] | req_read[1] | req_write[1] |
                       req_read[2] | req_write[2] | req_read[3] | req_write[3] |
                       req_read[4] | req_write[4] | req_read[5] | req_write[5] |
                       req_read[6] | req_write[6] | req_read[7] | req_write[7];

    // Combinational next-grant search starting at rr_ptr, wrapping.
    reg [2:0] next_grant;
    reg       next_grant_found;
    integer   k, idx;
    always @(*) begin
        next_grant_found = 1'b0;
        next_grant       = 3'd0;
        for (k = 0; k < 8; k = k + 1) begin
            idx = (rr_ptr + k) % 8;
            if (!next_grant_found && (req_read[idx] || req_write[idx])) begin
                next_grant       = idx[2:0];
                next_grant_found = 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            grant         <= 3'd0;
            granted_valid <= 1'b0;
            rr_ptr        <= 3'd0;
            snoop_en      <= {NUM_CORES{1'b0}};
            snoop_addr    <= 32'b0;
        end else begin
            snoop_en <= {NUM_CORES{1'b0}}; // 1-cycle pulse by default

            if (!granted_valid) begin
                if (next_grant_found) begin
                    grant         <= next_grant;
                    granted_valid <= 1'b1;
                end
            end else begin
                if (l2_ready) begin
                    granted_valid <= 1'b0;
                    rr_ptr        <= grant + 3'd1;

                    // Coherence: a D-side (grant>=4) write just landed in
                    // L2 — invalidate that line in every other core's
                    // private D-cache.
                    if (grant[2] && req_write[grant]) begin
                        snoop_en                    <= {NUM_CORES{1'b1}};
                        snoop_en[grant[1:0]]         <= 1'b0; // not the writer itself
                        snoop_addr                  <= req_addr[grant];
                    end
                end
            end
        end
    end

    always @(*) begin
        l2_addr  = granted_valid ? req_addr[grant]  : 32'b0;
        l2_read  = granted_valid ? req_read[grant]  : 1'b0;
        l2_write = granted_valid ? req_write[grant] : 1'b0;
        l2_wdata = granted_valid ? req_wdata[grant] : 256'b0;
    end

    genvar g;
    generate
        for (g = 0; g < 8; g = g + 1) begin : REQ_PORT
            assign req_ready[g] = granted_valid && (grant == g[2:0]) && l2_ready;
            assign req_rdata[g] = l2_rdata;
        end
    endgenerate

endmodule
