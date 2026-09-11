`timescale 1ns / 1ps

// ============================================================
// l2_cache
//
// Shared L2 storage array: tag + valid + dirty(-vs-DRAM) + data +
// a per-line sharer bitmap (the coherence directory). Per
// address_mapping's L2 spec (the diagram says 512KB; this repo
// defaults to address_mapping's 256KB -- see Risc_V_new/README.md
// for that open conflict; override L2_SIZE_BYTES to match whichever
// gets decided):
//   256KB, 4-way, line = 32B -> offset=5b, index=11b (2048 sets), tag=16b
//
// Inclusive of all 4 L1 D-caches (a directory-based protocol can
// only track sharers for lines it currently holds) -- I-caches are
// NOT tracked here at all (see l1_icache.v: no coherence participation).
//
// This module is deliberately "dumb": one synchronous command in,
// one registered response out, one cycle of latency, no sequencing
// of its own. All protocol decisions (snoop-before-share, eviction,
// fetch-from-memory, directory updates) live in coherence_manager.v,
// which issues LOOKUP/WRITE commands here the same way a CPU issues
// commands to a plain single-port RAM with a directory bolted on.
//
// Directory encoding: ONLY a sharers[3:0] bitmap, no separate
// "dirty owner" field. This is intentional, not a missing feature
// -- see coherence_manager.v's header for the invariant that makes
// it sufficient (a line can only ever go from 0 or 1 sharers to 2+
// by way of a mandatory snoop of the sole existing sharer, which is
// exactly the step that would catch a silent E->M upgrade; once a
// line has 2+ sharers, none of them can possibly be Modified, by
// construction).
// ============================================================
module l2_cache #(
    parameter INDEX_BITS    = 11,   // 2048 sets (256KB, 4-way, 32B line)
    parameter WAYS          = 4,
    parameter LINE_WORDS    = 8
)(
    input  wire         clk,
    input  wire         rst,

    // ---- Command (1-cycle latency, registered response) ----
    input  wire         cmd_valid,
    input  wire         cmd_we,          // 0 = lookup only, 1 = write the fields below
    input  wire [31:0]  cmd_addr,
    input  wire [1:0]   cmd_way,         // which way to WRITE (ignored on a lookup)
    input  wire [255:0] cmd_wdata,
    input  wire         cmd_w_valid,
    input  wire         cmd_w_dirty,
    input  wire [3:0]   cmd_w_sharers,

    output reg           resp_valid,      // 1 cycle after cmd_valid
    output reg           resp_hit,        // tag matched an already-valid way
    output reg  [1:0]    resp_way,        // matching way (hit) or LRU victim way (miss)
    output reg  [15:0]   resp_victim_tag, // tag currently held by resp_way (meaningful when !resp_hit)
    output reg           resp_victim_valid,
    output reg           resp_victim_dirty,
    output reg  [3:0]    resp_victim_sharers,
    output reg  [255:0]  resp_line,       // data at resp_way (hit: the requested line; miss: the victim's data)
    output reg  [3:0]    resp_sharers     // sharers at resp_way (hit: current sharers; miss: victim's, same as resp_victim_sharers)
);

    localparam OFFSET_BITS = 5;
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS;
    localparam SETS        = (1 << INDEX_BITS);
    localparam LINE_BITS   = LINE_WORDS * 32;

    wire [TAG_BITS-1:0]   addr_tag   = cmd_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] addr_index = cmd_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];

    reg                 valid_r   [0:WAYS-1][0:SETS-1];
    reg                 dirty_r   [0:WAYS-1][0:SETS-1];
    reg [TAG_BITS-1:0]  tag_r     [0:WAYS-1][0:SETS-1];
    reg [3:0]           sharers_r [0:WAYS-1][0:SETS-1];
    reg [LINE_BITS-1:0] data_r    [0:WAYS-1][0:SETS-1];
    reg [1:0]           lru_r     [0:SETS-1]; // round-robin victim pointer per set

    integer w, s;

    // ------------------------------------------------------
    // Lookup (combinational)
    // ------------------------------------------------------
    reg        hit_v;
    reg [1:0]  hit_way_v;

    always @(*) begin
        hit_v     = 1'b0;
        hit_way_v = 2'b0;
        for (w = 0; w < WAYS; w = w + 1) begin
            if (valid_r[w][addr_index] && (tag_r[w][addr_index] == addr_tag)) begin
                hit_v     = 1'b1;
                hit_way_v = w[1:0];
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            resp_valid <= 1'b0;
            for (s = 0; s < SETS; s = s + 1) begin
                lru_r[s] <= 2'b0;
                for (w = 0; w < WAYS; w = w + 1) begin
                    valid_r[w][s]   <= 1'b0;
                    dirty_r[w][s]   <= 1'b0;
                    sharers_r[w][s] <= 4'b0;
                end
            end
        end
        else begin
            resp_valid <= cmd_valid;

            if (cmd_valid && !cmd_we) begin
                // LOOKUP
                resp_hit            <= hit_v;
                resp_way             <= hit_v ? hit_way_v : lru_r[addr_index];
                resp_victim_tag      <= tag_r[hit_v ? hit_way_v : lru_r[addr_index]][addr_index];
                resp_victim_valid    <= valid_r[hit_v ? hit_way_v : lru_r[addr_index]][addr_index];
                resp_victim_dirty    <= dirty_r[hit_v ? hit_way_v : lru_r[addr_index]][addr_index];
                resp_victim_sharers  <= sharers_r[hit_v ? hit_way_v : lru_r[addr_index]][addr_index];
                resp_line            <= data_r[hit_v ? hit_way_v : lru_r[addr_index]][addr_index];
                resp_sharers         <= sharers_r[hit_v ? hit_way_v : lru_r[addr_index]][addr_index];
            end
            else if (cmd_valid && cmd_we) begin
                // WRITE (fill / directory update / eviction-clear, at
                // an explicit way chosen by the coherence manager --
                // normally the same way its preceding LOOKUP reported)
                valid_r[cmd_way][addr_index]   <= cmd_w_valid;
                dirty_r[cmd_way][addr_index]   <= cmd_w_dirty;
                tag_r[cmd_way][addr_index]     <= addr_tag;
                sharers_r[cmd_way][addr_index] <= cmd_w_sharers;
                data_r[cmd_way][addr_index]    <= cmd_wdata;
                if (cmd_w_valid) begin
                    lru_r[addr_index] <= cmd_way + 2'b1;
                end
            end
        end
    end

endmodule
