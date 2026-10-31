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
// This module is deliberately "dumb": one blocking command in and one
// registered response out.  A lookup is internally pipelined so the large
// distributed directory read and the four-way tag comparison do not share
// one timing path. All protocol decisions (snoop-before-share, eviction,
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

    // ---- Command (registered response; one blocking lookup at a time) ----
    input  wire         cmd_valid,
    input  wire         cmd_we,          // 0 = lookup only, 1 = write the fields below
    input  wire [31:0]  cmd_addr,
    input  wire [1:0]   cmd_way,         // which way to WRITE (ignored on a lookup)
    input  wire [255:0] cmd_wdata,
    input  wire         cmd_w_valid,
    input  wire         cmd_w_dirty,
    input  wire [3:0]   cmd_w_sharers,

    // ---- Whole-cache maintenance port ----
    // The cache controller scans one explicit {way,set} at a time after all
    // private L1 caches have drained.  A dirty line is first copied out over
    // this read-only port, then maint_invalidate is pulsed only after its
    // external-memory writeback has completed successfully.
    input  wire                    maint_valid,
    input  wire [INDEX_BITS-1:0]   maint_set,
    input  wire [1:0]              maint_way,
    input  wire                    maint_invalidate,
    output wire                    maint_ready,
    output reg                     maint_resp_valid,
    output reg                     maint_line_valid,
    output reg                     maint_line_dirty,
    output reg  [32-INDEX_BITS-5-1:0] maint_line_tag,
    output reg  [255:0]            maint_line_data,

    output reg           resp_valid,      // pulses when the registered response is complete
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
    // Store every way in its own synchronous BRAM.  All four ways read the
    // same set in parallel; the registered resp_way selects a line only after
    // the BRAM outputs are available.  This removes the former critical path
    // tag compare -> selected_way -> {way,set} -> RAMB36 address while keeping
    // exactly the same 512-KB capacity.  The lookup response is pipelined;
    // the controller waits for resp_valid instead of assuming one cycle.
    wire [INDEX_BITS-1:0] data_ram_set;
    wire                  data_ram_we;
    wire [3:0]            data_way_we;
    wire [255:0]          data_way0_q;
    wire [255:0]          data_way1_q;
    wire [255:0]          data_way2_q;
    wire [255:0]          data_way3_q;
    (* ram_style = "distributed" *) reg [1:0] lru_r [0:SETS-1];

    // Lookup pipeline.  The coherence controller is blocking and does not
    // issue another L2 command until resp_valid, so one in-flight lookup is
    // sufficient.  Splitting address fanout/directory read from tag compare
    // removes the former req_addr -> directory -> compare -> response path.
    reg                    lookup_addr_pending;
    reg                    lookup_meta_pending;
    reg [INDEX_BITS-1:0]   lookup_index;
    reg [TAG_BITS-1:0]     lookup_tag;
    reg                    lookup_valid_way0;
    reg                    lookup_valid_way1;
    reg                    lookup_valid_way2;
    reg                    lookup_valid_way3;
    reg                    lookup_dirty_way0;
    reg                    lookup_dirty_way1;
    reg                    lookup_dirty_way2;
    reg                    lookup_dirty_way3;
    reg [TAG_BITS-1:0]     lookup_tag_way0;
    reg [TAG_BITS-1:0]     lookup_tag_way1;
    reg [TAG_BITS-1:0]     lookup_tag_way2;
    reg [TAG_BITS-1:0]     lookup_tag_way3;
    reg [3:0]              lookup_sharers_way0;
    reg [3:0]              lookup_sharers_way1;
    reg [3:0]              lookup_sharers_way2;
    reg [3:0]              lookup_sharers_way3;
    reg [1:0]              lookup_lru;

    // Maintenance read pipeline.  The BRAM read is launched when the request
    // is accepted; data and metadata are registered one cycle later so the
    // 256-bit way mux is contained inside L2 rather than spanning into the
    // cache controller's flush_line register bank.
    reg                    maint_pending;
    reg                    maint_data_pending;
    reg [INDEX_BITS-1:0]   maint_set_q;
    reg [1:0]              maint_way_q;
    reg                    maint_upper_q;
    reg [255:0]            maint_pair_low_q;
    reg [255:0]            maint_pair_high_q;

    // Lookup and maintenance are mutually exclusive at the blocking
    // controller interface.  Explicitly mux their read address before every
    // directory array so synthesis keeps one physical read port instead of
    // duplicating the complete 4K-entry directory for a second port.
    wire [INDEX_BITS-1:0] meta_read_index = maint_pending ? maint_set_q : lookup_index;
    wire                  meta_valid_way0   = valid_way0_r[meta_read_index];
    wire                  meta_valid_way1   = valid_way1_r[meta_read_index];
    wire                  meta_valid_way2   = valid_way2_r[meta_read_index];
    wire                  meta_valid_way3   = valid_way3_r[meta_read_index];
    wire                  meta_dirty_way0   = dirty_way0_r[meta_read_index];
    wire                  meta_dirty_way1   = dirty_way1_r[meta_read_index];
    wire                  meta_dirty_way2   = dirty_way2_r[meta_read_index];
    wire                  meta_dirty_way3   = dirty_way3_r[meta_read_index];
    wire [TAG_BITS-1:0]   meta_tag_way0     = tag_way0_r[meta_read_index];
    wire [TAG_BITS-1:0]   meta_tag_way1     = tag_way1_r[meta_read_index];
    wire [TAG_BITS-1:0]   meta_tag_way2     = tag_way2_r[meta_read_index];
    wire [TAG_BITS-1:0]   meta_tag_way3     = tag_way3_r[meta_read_index];
    wire [3:0]            meta_sharers_way0 = sharers_way0_r[meta_read_index];
    wire [3:0]            meta_sharers_way1 = sharers_way1_r[meta_read_index];
    wire [3:0]            meta_sharers_way2 = sharers_way2_r[meta_read_index];
    wire [3:0]            meta_sharers_way3 = sharers_way3_r[meta_read_index];
    wire [1:0]            meta_lru          = lru_r[meta_read_index];

    // ------------------------------------------------------
    // Lookup (combinational)
    // ------------------------------------------------------
    reg        hit_v;
    reg [1:0]  hit_way_v;
    reg [TAG_BITS-1:0] selected_tag_v;
    reg                selected_valid_v;
    reg                selected_dirty_v;
    reg [3:0]          selected_sharers_v;

    wire [1:0] lru_way = lookup_lru;
    wire [1:0] selected_way = hit_v ? hit_way_v : lru_way;

    wire maint_read = !init_active && maint_valid && !maint_invalidate;
    wire lookup_busy = lookup_addr_pending | lookup_meta_pending;
    wire lookup_accept = !init_active && !maint_valid && !maint_pending &&
                         !lookup_busy && active_cmd_valid && !active_cmd_we;
    assign data_ram_we = !init_active && !maint_valid && !maint_pending &&
                         active_cmd_valid && active_cmd_we;
    assign data_ram_set = maint_read    ? maint_set   :
                          maint_pending ? maint_set_q :
                          (lookup_accept || data_ram_we) ? addr_index : lookup_index;
    assign data_way_we = data_ram_we ? (4'b0001 << active_cmd_way) : 4'b0000;

    l2_way_data_ram #(.ADDR_WIDTH(INDEX_BITS)) u_data_way0 (
        .clk(clk), .we(data_way_we[0]), .addr(data_ram_set),
        .din(active_cmd_wdata), .dout(data_way0_q));
    l2_way_data_ram #(.ADDR_WIDTH(INDEX_BITS)) u_data_way1 (
        .clk(clk), .we(data_way_we[1]), .addr(data_ram_set),
        .din(active_cmd_wdata), .dout(data_way1_q));
    l2_way_data_ram #(.ADDR_WIDTH(INDEX_BITS)) u_data_way2 (
        .clk(clk), .we(data_way_we[2]), .addr(data_ram_set),
        .din(active_cmd_wdata), .dout(data_way2_q));
    l2_way_data_ram #(.ADDR_WIDTH(INDEX_BITS)) u_data_way3 (
        .clk(clk), .we(data_way_we[3]), .addr(data_ram_set),
        .din(active_cmd_wdata), .dout(data_way3_q));

    assign maint_ready = !init_active;

    always @(*) begin
        hit_v     = 1'b0;
        hit_way_v = 2'b0;
        if (lookup_valid_way0 && (lookup_tag_way0 == lookup_tag)) begin
            hit_v = 1'b1; hit_way_v = 2'd0;
        end
        if (lookup_valid_way1 && (lookup_tag_way1 == lookup_tag)) begin
            hit_v = 1'b1; hit_way_v = 2'd1;
        end
        if (lookup_valid_way2 && (lookup_tag_way2 == lookup_tag)) begin
            hit_v = 1'b1; hit_way_v = 2'd2;
        end
        if (lookup_valid_way3 && (lookup_tag_way3 == lookup_tag)) begin
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
                selected_tag_v     = lookup_tag_way0;
                selected_valid_v   = lookup_valid_way0;
                selected_dirty_v   = lookup_dirty_way0;
                selected_sharers_v = lookup_sharers_way0;
            end
            2'd1: begin
                selected_tag_v     = lookup_tag_way1;
                selected_valid_v   = lookup_valid_way1;
                selected_dirty_v   = lookup_dirty_way1;
                selected_sharers_v = lookup_sharers_way1;
            end
            2'd2: begin
                selected_tag_v     = lookup_tag_way2;
                selected_valid_v   = lookup_valid_way2;
                selected_dirty_v   = lookup_dirty_way2;
                selected_sharers_v = lookup_sharers_way2;
            end
            default: begin
                selected_tag_v     = lookup_tag_way3;
                selected_valid_v   = lookup_valid_way3;
                selected_dirty_v   = lookup_dirty_way3;
                selected_sharers_v = lookup_sharers_way3;
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
            maint_resp_valid   <= 1'b0;
            maint_line_valid   <= 1'b0;
            maint_line_dirty   <= 1'b0;
            maint_line_tag     <= {TAG_BITS{1'b0}};
            lookup_addr_pending <= 1'b0;
            lookup_meta_pending <= 1'b0;
            lookup_index        <= {INDEX_BITS{1'b0}};
            lookup_tag          <= {TAG_BITS{1'b0}};
            maint_pending       <= 1'b0;
            maint_data_pending  <= 1'b0;
            maint_set_q         <= {INDEX_BITS{1'b0}};
            maint_way_q         <= 2'b0;
            maint_upper_q       <= 1'b0;
        end
        else if (init_active) begin
            resp_valid <= 1'b0;
            maint_resp_valid <= 1'b0;
            lookup_addr_pending <= 1'b0;
            lookup_meta_pending <= 1'b0;
            maint_pending <= 1'b0;
            maint_data_pending <= 1'b0;

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
            // Pipeline-valid signals are single-cycle pulses. Writes keep the
            // legacy immediate acknowledgement; lookup data is acknowledged
            // only after both directory stages have completed.
            resp_valid <= lookup_meta_pending || data_ram_we;
            maint_resp_valid <= maint_data_pending;
            lookup_addr_pending <= lookup_accept;
            lookup_meta_pending <= lookup_addr_pending;
            maint_pending <= maint_read;
            maint_data_pending <= maint_pending;
            if (pending_valid)
                pending_valid <= 1'b0;

            if (lookup_accept) begin
                lookup_index <= addr_index;
                lookup_tag   <= addr_tag;
            end

            // Stage 2: terminate the high-fanout directory read at local
            // registers. Tag comparison and victim selection happen only in
            // the following cycle from these registered values.
            if (lookup_addr_pending) begin
                lookup_valid_way0   <= meta_valid_way0;
                lookup_valid_way1   <= meta_valid_way1;
                lookup_valid_way2   <= meta_valid_way2;
                lookup_valid_way3   <= meta_valid_way3;
                lookup_dirty_way0   <= meta_dirty_way0;
                lookup_dirty_way1   <= meta_dirty_way1;
                lookup_dirty_way2   <= meta_dirty_way2;
                lookup_dirty_way3   <= meta_dirty_way3;
                lookup_tag_way0     <= meta_tag_way0;
                lookup_tag_way1     <= meta_tag_way1;
                lookup_tag_way2     <= meta_tag_way2;
                lookup_tag_way3     <= meta_tag_way3;
                lookup_sharers_way0 <= meta_sharers_way0;
                lookup_sharers_way1 <= meta_sharers_way1;
                lookup_sharers_way2 <= meta_sharers_way2;
                lookup_sharers_way3 <= meta_sharers_way3;
                lookup_lru          <= meta_lru;
            end

            // Stage 3: register the selected directory entry and its aligned
            // BRAM line. The BRAM address has remained at lookup_index while
            // this blocking lookup was in flight.
            if (lookup_meta_pending) begin
                resp_hit            <= hit_v;
                resp_way            <= selected_way;
                resp_victim_tag     <= selected_tag_v;
                resp_victim_valid   <= selected_valid_v;
                resp_victim_dirty   <= selected_dirty_v;
                resp_victim_sharers <= selected_sharers_v;
                resp_sharers        <= selected_sharers_v;
                case (selected_way)
                    2'd0: resp_line <= data_way0_q;
                    2'd1: resp_line <= data_way1_q;
                    2'd2: resp_line <= data_way2_q;
                    default: resp_line <= data_way3_q;
                endcase
            end

            if (maint_read) begin
                maint_set_q <= maint_set;
                maint_way_q <= maint_way;
            end

            // First maintenance data stage: two local 2:1 selections.  This
            // replaces the congested four-way 256-bit mux (9.4 ns routing in
            // the previous routed build) with two shorter registered paths.
            if (maint_pending) begin
                maint_pair_low_q  <= maint_way_q[0] ? data_way1_q : data_way0_q;
                maint_pair_high_q <= maint_way_q[0] ? data_way3_q : data_way2_q;
                maint_upper_q     <= maint_way_q[1];
                case (maint_way_q)
                    2'd0: begin
                        maint_line_valid <= meta_valid_way0;
                        maint_line_dirty <= meta_valid_way0 && meta_dirty_way0;
                        maint_line_tag   <= meta_valid_way0 ? meta_tag_way0 : {TAG_BITS{1'b0}};
                    end
                    2'd1: begin
                        maint_line_valid <= meta_valid_way1;
                        maint_line_dirty <= meta_valid_way1 && meta_dirty_way1;
                        maint_line_tag   <= meta_valid_way1 ? meta_tag_way1 : {TAG_BITS{1'b0}};
                    end
                    2'd2: begin
                        maint_line_valid <= meta_valid_way2;
                        maint_line_dirty <= meta_valid_way2 && meta_dirty_way2;
                        maint_line_tag   <= meta_valid_way2 ? meta_tag_way2 : {TAG_BITS{1'b0}};
                    end
                    default: begin
                        maint_line_valid <= meta_valid_way3;
                        maint_line_dirty <= meta_valid_way3 && meta_dirty_way3;
                        maint_line_tag   <= meta_valid_way3 ? meta_tag_way3 : {TAG_BITS{1'b0}};
                    end
                endcase
            end

            // Second maintenance data stage: select between the two registered
            // pairs, then assert maint_resp_valid with the complete response.
            if (maint_data_pending)
                maint_line_data <= maint_upper_q ? maint_pair_high_q : maint_pair_low_q;

            if (maint_valid && maint_invalidate) begin
                // Invalidate only after a dirty line has reached memory.  Data
                // and tag RAMs need not be cleared because valid gates them.
                case (maint_way)
                    2'd0: begin
                        valid_way0_r[maint_set]   <= 1'b0;
                        dirty_way0_r[maint_set]   <= 1'b0;
                        sharers_way0_r[maint_set] <= 4'b0;
                    end
                    2'd1: begin
                        valid_way1_r[maint_set]   <= 1'b0;
                        dirty_way1_r[maint_set]   <= 1'b0;
                        sharers_way1_r[maint_set] <= 4'b0;
                    end
                    2'd2: begin
                        valid_way2_r[maint_set]   <= 1'b0;
                        dirty_way2_r[maint_set]   <= 1'b0;
                        sharers_way2_r[maint_set] <= 4'b0;
                    end
                    default: begin
                        valid_way3_r[maint_set]   <= 1'b0;
                        dirty_way3_r[maint_set]   <= 1'b0;
                        sharers_way3_r[maint_set] <= 4'b0;
                    end
                endcase
            end
            else if (data_ram_we) begin
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
                if (active_cmd_w_valid)
                    lru_r[addr_index] <= active_cmd_way + 2'b1;
            end
        end
    end

endmodule

// Explicit single-port BRAM for one complete L2 way.  Synthesis sees one
// 256-bit XPM memory; the behavioural implementation splits the storage into
// eight words so no Verilog variable exceeds Vivado's elaboration-size limit.
module l2_way_data_ram #(
    parameter integer ADDR_WIDTH = 12
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [255:0]          din,
    output wire [255:0]          dout
);
`ifdef SYNTHESIS
    xpm_memory_spram #(
        .ADDR_WIDTH_A       (ADDR_WIDTH),
        .AUTO_SLEEP_TIME    (0),
        .BYTE_WRITE_WIDTH_A (256),
        .CASCADE_HEIGHT     (0),
        .ECC_MODE           ("no_ecc"),
        .MEMORY_INIT_FILE   ("none"),
        .MEMORY_INIT_PARAM  ("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE   ("block"),
        .MEMORY_SIZE        (256 * (1 << ADDR_WIDTH)),
        .MESSAGE_CONTROL    (0),
        .READ_DATA_WIDTH_A  (256),
        .READ_LATENCY_A     (1),
        .READ_RESET_VALUE_A ("0"),
        .RST_MODE_A         ("SYNC"),
        .SIM_ASSERT_CHK     (0),
        .USE_MEM_INIT       (0),
        .WAKEUP_TIME        ("disable_sleep"),
        .WRITE_DATA_WIDTH_A (256),
        .WRITE_MODE_A       ("read_first"),
        .WRITE_PROTECT      (1)
    ) u_xpm (
        .sleep(1'b0), .clka(clk), .rsta(1'b0), .ena(1'b1),
        .regcea(1'b1), .wea(we), .addra(addr), .dina(din),
        .injectsbiterra(1'b0), .injectdbiterra(1'b0),
        .douta(dout), .sbiterra(), .dbiterra()
    );
`else
    reg [31:0] mem_word0 [0:(1 << ADDR_WIDTH)-1];
    reg [31:0] mem_word1 [0:(1 << ADDR_WIDTH)-1];
    reg [31:0] mem_word2 [0:(1 << ADDR_WIDTH)-1];
    reg [31:0] mem_word3 [0:(1 << ADDR_WIDTH)-1];
    reg [31:0] mem_word4 [0:(1 << ADDR_WIDTH)-1];
    reg [31:0] mem_word5 [0:(1 << ADDR_WIDTH)-1];
    reg [31:0] mem_word6 [0:(1 << ADDR_WIDTH)-1];
    reg [31:0] mem_word7 [0:(1 << ADDR_WIDTH)-1];
    reg [255:0] dout_r;

    assign dout = dout_r;
    always @(posedge clk) begin
        if (we) begin
            mem_word0[addr] <= din[31:0];
            mem_word1[addr] <= din[63:32];
            mem_word2[addr] <= din[95:64];
            mem_word3[addr] <= din[127:96];
            mem_word4[addr] <= din[159:128];
            mem_word5[addr] <= din[191:160];
            mem_word6[addr] <= din[223:192];
            mem_word7[addr] <= din[255:224];
        end
        dout_r <= {
            mem_word7[addr], mem_word6[addr], mem_word5[addr], mem_word4[addr],
            mem_word3[addr], mem_word2[addr], mem_word1[addr], mem_word0[addr]
        };
    end
`endif
endmodule
