`timescale 1ns / 1ps

// ============================================================
// l2_cache
//
// Shared L2 storage array: tag + valid + dirty(-vs-DRAM) + data +
// a per-line sharer bitmap (the coherence directory). Sized per the
// FINAL architecture decision (Risc_V_new/README.md mục 4 -- the
// diagram's own 512KB, not address_mapping's earlier 256KB placeholder
// number; the "open conflict" this header used to describe is now
// resolved):
//   512KB, 4-way, line = 32B -> offset=5b, index=12b (4096 sets), tag=15b
// (16384 total lines / 4 ways = 4096 lines/way = 2^12 -- INDEX_BITS=12.
// Every other size-derived constant below (TAG_BITS/SETS/etc.) is a
// localparam computed FROM INDEX_BITS, so this is the only parameter
// that ever needs to change for a different L2 size.)
//
// Inclusive of all 4 L1 D-caches (a directory-based protocol can
// only track sharers for lines it currently holds) -- I-caches are
// NOT tracked here at all (see l1_icache.v: no coherence participation).
//
// This module is deliberately "dumb": one synchronous command in,
// one registered response out, one cycle of latency, no sequencing
// of its own. All protocol decisions (snoop-before-share, eviction,
// fetch-from-memory, directory updates) live in cache_controller_mmu
// (implemented by the coherence_manager policy engine), which issues
// LOOKUP/WRITE commands here the same way a CPU issues
// commands to a plain single-port RAM with a directory bolted on.
//
// Directory encoding: ONLY a sharers[3:0] bitmap, no separate
// "dirty owner" field. Under MSI every S->M transition is a visible
// RFO, so an M line has exactly one sharer bit. The coherence manager
// snoops listed holders on BusRd/BusRdX and obtains dirty data from
// the unique M holder before changing the directory.
// ============================================================
module l2_cache #(
    parameter INDEX_BITS    = 12,   // 4096 sets (512KB, 4-way, 32B line)
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
    output reg  [32-INDEX_BITS-5-1:0] resp_victim_tag, // tag currently held by resp_way (meaningful when !resp_hit)
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
    localparam WAYS        = 4;
    localparam DATA_DEPTH  = WAYS * SETS;

    // A cache-wide synchronous clear prevents RAM inference.  Invalidate
    // one set per cycle after reset instead, and retain the single command
    // that the blocking controller can issue while initialization runs.
    reg                  init_active;
    reg [INDEX_BITS-1:0] init_index;
    reg                  pending_valid;
    reg                  pending_we;
    reg [31:0]           pending_addr;
    reg [1:0]            pending_way;
    reg [255:0]          pending_wdata;
    reg                  pending_w_valid;
    reg                  pending_w_dirty;
    reg [3:0]            pending_w_sharers;

    wire                 active_cmd_valid     = pending_valid | cmd_valid;
    wire                 active_cmd_we        = pending_valid ? pending_we        : cmd_we;
    wire [31:0]          active_cmd_addr      = pending_valid ? pending_addr      : cmd_addr;
    wire [1:0]           active_cmd_way       = pending_valid ? pending_way       : cmd_way;
    wire [255:0]         active_cmd_wdata      = pending_valid ? pending_wdata      : cmd_wdata;
    wire                 active_cmd_w_valid    = pending_valid ? pending_w_valid    : cmd_w_valid;
    wire                 active_cmd_w_dirty    = pending_valid ? pending_w_dirty    : cmd_w_dirty;
    wire [3:0]           active_cmd_w_sharers = pending_valid ? pending_w_sharers : cmd_w_sharers;

    wire [TAG_BITS-1:0]   addr_tag   = active_cmd_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] addr_index = active_cmd_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];

    // Keep each way as an independent one-dimensional memory.  Vivado
    // 2022.2 expands the former [way][set] 3-D RAM representation into
    // hundreds of thousands of scalar registers before optimizing it;
    // that is the source of the multi-hour synthesis stall.  Splitting
    // ways leaves the cache organization and lookup latency unchanged.
    (* ram_style = "distributed" *) reg valid_way0_r [0:SETS-1];
    (* ram_style = "distributed" *) reg valid_way1_r [0:SETS-1];
    (* ram_style = "distributed" *) reg valid_way2_r [0:SETS-1];
    (* ram_style = "distributed" *) reg valid_way3_r [0:SETS-1];
    (* ram_style = "distributed" *) reg dirty_way0_r [0:SETS-1];
    (* ram_style = "distributed" *) reg dirty_way1_r [0:SETS-1];
    (* ram_style = "distributed" *) reg dirty_way2_r [0:SETS-1];
    (* ram_style = "distributed" *) reg dirty_way3_r [0:SETS-1];
    (* ram_style = "distributed" *) reg [TAG_BITS-1:0] tag_way0_r [0:SETS-1];
    (* ram_style = "distributed" *) reg [TAG_BITS-1:0] tag_way1_r [0:SETS-1];
    (* ram_style = "distributed" *) reg [TAG_BITS-1:0] tag_way2_r [0:SETS-1];
    (* ram_style = "distributed" *) reg [TAG_BITS-1:0] tag_way3_r [0:SETS-1];
    (* ram_style = "distributed" *) reg [3:0] sharers_way0_r [0:SETS-1];
    (* ram_style = "distributed" *) reg [3:0] sharers_way1_r [0:SETS-1];
    (* ram_style = "distributed" *) reg [3:0] sharers_way2_r [0:SETS-1];
    (* ram_style = "distributed" *) reg [3:0] sharers_way3_r [0:SETS-1];
    // Do not describe the complete 512-KB store as one 4,194,304-bit
    // Verilog variable.  Vivado limits an individual variable to
    // 1,000,000 bits during RTL elaboration.  Eight independent 32-bit
    // banks preserve the exact same 256-bit line interface and are also
    // a much more natural shape for block-RAM inference.
    (* ram_style = "block" *) reg [31:0] data_word0_r [0:DATA_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] data_word1_r [0:DATA_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] data_word2_r [0:DATA_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] data_word3_r [0:DATA_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] data_word4_r [0:DATA_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] data_word5_r [0:DATA_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] data_word6_r [0:DATA_DEPTH-1];
    (* ram_style = "block" *) reg [31:0] data_word7_r [0:DATA_DEPTH-1];
    (* ram_style = "distributed" *) reg [1:0] lru_r [0:SETS-1];

    // ------------------------------------------------------
    // Lookup (combinational)
    // ------------------------------------------------------
    reg        hit_v;
    reg [1:0]  hit_way_v;
    reg [TAG_BITS-1:0] selected_tag_v;
    reg                selected_valid_v;
    reg                selected_dirty_v;
    reg [3:0]          selected_sharers_v;

    wire [1:0] lru_way = lru_r[addr_index];
    wire [1:0] selected_way = hit_v ? hit_way_v : lru_way;
    wire [INDEX_BITS+1:0] read_data_index  = {selected_way, addr_index};
    wire [INDEX_BITS+1:0] write_data_index = {active_cmd_way, addr_index};

    always @(*) begin
        hit_v     = 1'b0;
        hit_way_v = 2'b0;
        if (valid_way0_r[addr_index] && (tag_way0_r[addr_index] == addr_tag)) begin
            hit_v = 1'b1; hit_way_v = 2'd0;
        end
        if (valid_way1_r[addr_index] && (tag_way1_r[addr_index] == addr_tag)) begin
            hit_v = 1'b1; hit_way_v = 2'd1;
        end
        if (valid_way2_r[addr_index] && (tag_way2_r[addr_index] == addr_tag)) begin
            hit_v = 1'b1; hit_way_v = 2'd2;
        end
        if (valid_way3_r[addr_index] && (tag_way3_r[addr_index] == addr_tag)) begin
            hit_v = 1'b1; hit_way_v = 2'd3;
        end
    end

    always @(*) begin
        selected_tag_v     = {TAG_BITS{1'b0}};
        selected_valid_v   = 1'b0;
        selected_dirty_v   = 1'b0;
        selected_sharers_v = 4'b0;
        case (selected_way)
            2'd0: begin
                selected_tag_v     = tag_way0_r[addr_index];
                selected_valid_v   = valid_way0_r[addr_index];
                selected_dirty_v   = dirty_way0_r[addr_index];
                selected_sharers_v = sharers_way0_r[addr_index];
            end
            2'd1: begin
                selected_tag_v     = tag_way1_r[addr_index];
                selected_valid_v   = valid_way1_r[addr_index];
                selected_dirty_v   = dirty_way1_r[addr_index];
                selected_sharers_v = sharers_way1_r[addr_index];
            end
            2'd2: begin
                selected_tag_v     = tag_way2_r[addr_index];
                selected_valid_v   = valid_way2_r[addr_index];
                selected_dirty_v   = dirty_way2_r[addr_index];
                selected_sharers_v = sharers_way2_r[addr_index];
            end
            default: begin
                selected_tag_v     = tag_way3_r[addr_index];
                selected_valid_v   = valid_way3_r[addr_index];
                selected_dirty_v   = dirty_way3_r[addr_index];
                selected_sharers_v = sharers_way3_r[addr_index];
            end
        endcase
        // Tag/directory contents do not need a physical reset because an
        // invalid line is never consumed.  Mask them to deterministic zero
        // at the interface to prevent X propagation in RTL simulation.
        if (!selected_valid_v) begin
            selected_tag_v     = {TAG_BITS{1'b0}};
            selected_dirty_v   = 1'b0;
            selected_sharers_v = 4'b0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            resp_valid         <= 1'b0;
            init_active        <= 1'b1;
            init_index         <= {INDEX_BITS{1'b0}};
            pending_valid      <= 1'b0;
            pending_we         <= 1'b0;
            pending_addr       <= 32'b0;
            pending_way        <= 2'b0;
            pending_wdata      <= 256'b0;
            pending_w_valid    <= 1'b0;
            pending_w_dirty    <= 1'b0;
            pending_w_sharers  <= 4'b0;
        end
        else if (init_active) begin
            resp_valid <= 1'b0;

            // One write address per array per cycle is RAM-inference
            // friendly, unlike clearing every set in one clock edge.
            valid_way0_r[init_index] <= 1'b0;
            valid_way1_r[init_index] <= 1'b0;
            valid_way2_r[init_index] <= 1'b0;
            valid_way3_r[init_index] <= 1'b0;
            lru_r[init_index]        <= 2'b0;

            if (cmd_valid && !pending_valid) begin
                pending_valid     <= 1'b1;
                pending_we        <= cmd_we;
                pending_addr      <= cmd_addr;
                pending_way       <= cmd_way;
                pending_wdata     <= cmd_wdata;
                pending_w_valid   <= cmd_w_valid;
                pending_w_dirty   <= cmd_w_dirty;
                pending_w_sharers <= cmd_w_sharers;
            end

            if (init_index == SETS-1) begin
                init_active <= 1'b0;
            end
            else begin
                init_index <= init_index + {{(INDEX_BITS-1){1'b0}}, 1'b1};
            end
        end
        else begin
            resp_valid <= active_cmd_valid;
            if (pending_valid)
                pending_valid <= 1'b0;

            if (active_cmd_valid && !active_cmd_we) begin
                // LOOKUP
                resp_hit            <= hit_v;
                resp_way             <= selected_way;
                resp_victim_tag      <= selected_tag_v;
                resp_victim_valid    <= selected_valid_v;
                resp_victim_dirty    <= selected_dirty_v;
                resp_victim_sharers  <= selected_sharers_v;
                resp_line            <= {
                    data_word7_r[read_data_index], data_word6_r[read_data_index],
                    data_word5_r[read_data_index], data_word4_r[read_data_index],
                    data_word3_r[read_data_index], data_word2_r[read_data_index],
                    data_word1_r[read_data_index], data_word0_r[read_data_index]
                };
                resp_sharers         <= selected_sharers_v;
            end
            else if (active_cmd_valid && active_cmd_we) begin
                // WRITE (fill / directory update / eviction-clear, at
                // an explicit way chosen by the coherence manager --
                // normally the same way its preceding LOOKUP reported)
                case (active_cmd_way)
                    2'd0: begin
                        valid_way0_r[addr_index]   <= active_cmd_w_valid;
                        dirty_way0_r[addr_index]   <= active_cmd_w_dirty;
                        tag_way0_r[addr_index]     <= addr_tag;
                        sharers_way0_r[addr_index] <= active_cmd_w_sharers;
                    end
                    2'd1: begin
                        valid_way1_r[addr_index]   <= active_cmd_w_valid;
                        dirty_way1_r[addr_index]   <= active_cmd_w_dirty;
                        tag_way1_r[addr_index]     <= addr_tag;
                        sharers_way1_r[addr_index] <= active_cmd_w_sharers;
                    end
                    2'd2: begin
                        valid_way2_r[addr_index]   <= active_cmd_w_valid;
                        dirty_way2_r[addr_index]   <= active_cmd_w_dirty;
                        tag_way2_r[addr_index]     <= addr_tag;
                        sharers_way2_r[addr_index] <= active_cmd_w_sharers;
                    end
                    default: begin
                        valid_way3_r[addr_index]   <= active_cmd_w_valid;
                        dirty_way3_r[addr_index]   <= active_cmd_w_dirty;
                        tag_way3_r[addr_index]     <= addr_tag;
                        sharers_way3_r[addr_index] <= active_cmd_w_sharers;
                    end
                endcase
                data_word0_r[write_data_index] <= active_cmd_wdata[31:0];
                data_word1_r[write_data_index] <= active_cmd_wdata[63:32];
                data_word2_r[write_data_index] <= active_cmd_wdata[95:64];
                data_word3_r[write_data_index] <= active_cmd_wdata[127:96];
                data_word4_r[write_data_index] <= active_cmd_wdata[159:128];
                data_word5_r[write_data_index] <= active_cmd_wdata[191:160];
                data_word6_r[write_data_index] <= active_cmd_wdata[223:192];
                data_word7_r[write_data_index] <= active_cmd_wdata[255:224];
                if (active_cmd_w_valid)
                    lru_r[addr_index] <= active_cmd_way + 2'b1;
            end
        end
    end

endmodule
