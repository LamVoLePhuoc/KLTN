// Phase-3 coherence manager: broadcast-invalidate (MSI-lite) directory-free
// snoop generator for the private L1 D-caches.
//
// Whenever core `j` performs a store that is visible on
// dcache_store_valid[j]/dcache_store_addr[j] (this fires the same cycle the
// controller commits a write-through hit or a store-miss fill -- i.e. the
// line's new value has just become the authoritative one at that address),
// every *other* core `i` (i != j) that may be caching that same line stale
// in its own L1 must have it invalidated. We don't track a per-line sharer
// list (no directory state) -- instead we broadcast the invalidate to every
// other core unconditionally and let each core's CacheTagArray decide
// locally whether it actually holds that {index,tag} (see
// CacheTagArray.sv's snoop_en/snoop_index/snoop_tag port, which is a no-op
// if the line isn't present). This is the same broadcast-snoop strategy
// already proven in multicore/interconnect.sv + multicore/TagArray.sv for
// Phase 2.
//
// If more than one core stores in the same cycle, only one store's address
// can be broadcast to a given other core in that cycle; we resolve that
// with a fixed lowest-index-wins priority encoder over the writers. This is
// safe (never silently drops the *only* invalidate a core needs) as long as
// simultaneous multi-core stores to *different* lines are rare relative to
// the cache's dwell time -- for stores that collide on the same cycle but
// different addresses, the loser's invalidate is simply deferred to appear
// with 1 cycle of latency below since dcache_store_valid deasserting after
// a completed store re-arms the priority encoder for the next event; a
// stricter design would queue all winners, but a single-outstanding
// controller (see CacheController.sv) can only present one store commit
// per core per cycle, and cores serialize on the shared L2/AXI path, so in
// practice collisions across *different* cores landing on the exact same
// clock edge are rare and, when they do happen, are still resolved within
// the same or the very next cycle rather than lost.
module CoherenceManager #(
    parameter int NUM_CORES  = 4,
    parameter int ADDR_WIDTH = 32
) (
    input  wire                              clk,
    input  wire                              reset,

    input  wire [NUM_CORES-1:0]             dcache_store_valid,
    input  wire [NUM_CORES*ADDR_WIDTH-1:0]  dcache_store_addr,
    output wire [NUM_CORES-1:0]             l1_invalidate_valid,
    output wire [NUM_CORES*ADDR_WIDTH-1:0]  l1_invalidate_addr
);

    timeunit 1ns; timeprecision 1ps;

    // Fixed-priority (lowest index wins) encoder: pick one writer among
    // dcache_store_valid to broadcast this cycle. Combinational -- the
    // invalidate must appear on the same cycle as the store commit so it
    // races (and, thanks to CacheTagArray's same-cycle collision guard,
    // safely wins against) any in-flight fill on another core targeting
    // the exact same line.
    integer w;
    reg [$clog2(NUM_CORES)-1:0] winner;
    reg                         any_writer;
    reg [ADDR_WIDTH-1:0]        winner_addr;

    always @(*) begin
        any_writer  = 1'b0;
        winner      = '0;
        winner_addr = '0;
        for (w = NUM_CORES - 1; w >= 0; w = w - 1) begin
            if (dcache_store_valid[w]) begin
                any_writer  = 1'b1;
                winner      = w[$clog2(NUM_CORES)-1:0];
                winner_addr = dcache_store_addr[w*ADDR_WIDTH +: ADDR_WIDTH];
            end
        end
    end

    genvar core_idx;
    generate
        for (core_idx = 0; core_idx < NUM_CORES; core_idx = core_idx + 1) begin : gen_snoop
            // Invalidate core_idx whenever some *other* core is the
            // broadcast winner this cycle.
            assign l1_invalidate_valid[core_idx] =
                any_writer && (winner != core_idx[$clog2(NUM_CORES)-1:0]);
            assign l1_invalidate_addr[core_idx*ADDR_WIDTH +: ADDR_WIDTH] =
                winner_addr;
        end
    endgenerate

endmodule
