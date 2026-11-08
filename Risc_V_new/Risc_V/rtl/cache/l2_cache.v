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
// registered response out.  A lookup is internally pipelined so the packed
// block-RAM directory read and the four-way tag comparison do not share one
// timing path. All protocol decisions (snoop-before-share, eviction,
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
    output wire [255:0]            maint_line_data,

    output reg           resp_valid,      // pulses when the registered response is complete
    output reg           resp_hit,        // tag matched an already-valid way
    output reg  [1:0]    resp_way,        // matching way (hit) or LRU victim way (miss)
    output reg  [32-INDEX_BITS-5-1:0] resp_victim_tag, // tag currently held by resp_way (meaningful when !resp_hit)
    output reg           resp_victim_valid,
    output reg           resp_victim_dirty,
    output reg  [3:0]    resp_victim_sharers,
    output wire [255:0]  resp_line,       // data at resp_way (hit: the requested line; miss: the victim's data)
    output reg  [3:0]    resp_sharers     // sharers at resp_way (hit: current sharers; miss: victim's, same as resp_victim_sharers)
);

    localparam OFFSET_BITS = 5;
    localparam TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS;
    localparam SETS        = (1 << INDEX_BITS);
    localparam LINE_BITS   = LINE_WORDS * 32;
    localparam WAYS        = 4;
    localparam META_BITS   = TAG_BITS + 6; // {tag, sharers[3:0], dirty, valid}

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

    // Keep each way as an independent packed metadata RAM.  The 21-bit entry
    // maps to block RAM instead of 21 separate 4K-deep distributed arrays.
    // Lookup/maintenance already have registered read stages, so the BRAM
    // latency does not add another externally visible controller state.
    wire [INDEX_BITS-1:0] meta_ram_set;
    wire [3:0]            meta_way_we;
    wire [META_BITS-1:0]  meta_wdata;
    wire [META_BITS-1:0]  meta_way0_q;
    wire [META_BITS-1:0]  meta_way1_q;
    wire [META_BITS-1:0]  meta_way2_q;
    wire [META_BITS-1:0]  meta_way3_q;
    wire                  lru_we;
    wire [1:0]            lru_wdata;
    wire [1:0]            lru_q;
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

    // Lookup pipeline.  The coherence controller is blocking and does not
    // issue another L2 command until resp_valid, so one in-flight lookup is
    // sufficient.  Splitting address fanout/directory read from tag compare
    // removes the former req_addr -> directory -> compare -> response path.
    reg                    lookup_addr_pending;
    reg                    lookup_meta_pending;
    reg                    lookup_select_pending;
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
    reg                    lookup_hit_q;
    reg [1:0]              lookup_selected_way_q;

    // Maintenance read pipeline.  The BRAM read is launched when the request
    // is accepted.  Data selection is implemented by eight independent
    // 32-bit slice pipelines below; there is deliberately no central 256-bit
    // register fed by all L2 BRAM columns.
    reg                    maint_pending;
    reg                    maint_data_pending;
    reg [INDEX_BITS-1:0]   maint_set_q;
    reg [1:0]              maint_way_q;
    wire [255:0]           lookup_line_banked_q;
    wire [255:0]           maint_line_banked_q;

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
    wire lookup_busy = lookup_addr_pending | lookup_meta_pending |
                       lookup_select_pending;
    // Drive the BRAM address mux from command presence, not the multi-stage
    // lookup-busy feedback.  The interface permits only one blocking command;
    // while a lookup is in flight the controller either holds this same
    // address or deasserts cmd_valid, in which case lookup_index retains it.
    // This removes a four-LUT control path into every BRAM address pin.
    wire lookup_address_present = !init_active && !maint_valid &&
                                  active_cmd_valid && !active_cmd_we;
    wire lookup_accept = !init_active && !maint_valid && !maint_pending &&
                         !lookup_busy && active_cmd_valid && !active_cmd_we;
    assign data_ram_we = !init_active && !maint_valid && !maint_pending &&
                         active_cmd_valid && active_cmd_we;
    assign data_ram_set = maint_read    ? maint_set   :
                          maint_pending ? maint_set_q :
                          (lookup_address_present || data_ram_we) ? addr_index : lookup_index;
    assign data_way_we = data_ram_we ? (4'b0001 << active_cmd_way) : 4'b0000;

    // Lookup and maintenance are mutually exclusive at the blocking
    // controller interface.  One address mux therefore serves all metadata
    // BRAMs without duplicating the directory read port.
    wire maint_invalidate_write = !init_active && maint_valid && maint_invalidate;
    assign meta_ram_set = init_active              ? init_index  :
                          maint_invalidate_write   ? maint_set    :
                          data_ram_we              ? addr_index   :
                          maint_read               ? maint_set    :
                          maint_pending            ? maint_set_q  :
                          lookup_address_present   ? addr_index   : lookup_index;
    assign meta_way_we = init_active            ? 4'b1111 :
                         maint_invalidate_write ? (4'b0001 << maint_way) :
                         data_ram_we            ? (4'b0001 << active_cmd_way) : 4'b0000;
    assign meta_wdata = (init_active || maint_invalidate_write) ?
                        {META_BITS{1'b0}} :
                        {addr_tag, active_cmd_w_sharers,
                         active_cmd_w_dirty, active_cmd_w_valid};
    assign lru_we    = init_active || (data_ram_we && active_cmd_w_valid);
    assign lru_wdata = init_active ? 2'b0 : (active_cmd_way + 2'b1);

    l2_sync_block_ram #(.ADDR_WIDTH(INDEX_BITS), .WIDTH(META_BITS)) u_meta_way0 (
        .clk(clk), .we(meta_way_we[0]), .addr(meta_ram_set),
        .din(meta_wdata), .dout(meta_way0_q));
    l2_sync_block_ram #(.ADDR_WIDTH(INDEX_BITS), .WIDTH(META_BITS)) u_meta_way1 (
        .clk(clk), .we(meta_way_we[1]), .addr(meta_ram_set),
        .din(meta_wdata), .dout(meta_way1_q));
    l2_sync_block_ram #(.ADDR_WIDTH(INDEX_BITS), .WIDTH(META_BITS)) u_meta_way2 (
        .clk(clk), .we(meta_way_we[2]), .addr(meta_ram_set),
        .din(meta_wdata), .dout(meta_way2_q));
    l2_sync_block_ram #(.ADDR_WIDTH(INDEX_BITS), .WIDTH(META_BITS)) u_meta_way3 (
        .clk(clk), .we(meta_way_we[3]), .addr(meta_ram_set),
        .din(meta_wdata), .dout(meta_way3_q));
    l2_sync_block_ram #(.ADDR_WIDTH(INDEX_BITS), .WIDTH(2)) u_meta_lru (
        .clk(clk), .we(lru_we), .addr(meta_ram_set),
        .din(lru_wdata), .dout(lru_q));

    wire                  meta_valid_way0   = meta_way0_q[0];
    wire                  meta_valid_way1   = meta_way1_q[0];
    wire                  meta_valid_way2   = meta_way2_q[0];
    wire                  meta_valid_way3   = meta_way3_q[0];
    wire                  meta_dirty_way0   = meta_way0_q[1];
    wire                  meta_dirty_way1   = meta_way1_q[1];
    wire                  meta_dirty_way2   = meta_way2_q[1];
    wire                  meta_dirty_way3   = meta_way3_q[1];
    wire [3:0]            meta_sharers_way0 = meta_way0_q[5:2];
    wire [3:0]            meta_sharers_way1 = meta_way1_q[5:2];
    wire [3:0]            meta_sharers_way2 = meta_way2_q[5:2];
    wire [3:0]            meta_sharers_way3 = meta_way3_q[5:2];
    wire [TAG_BITS-1:0]   meta_tag_way0     = meta_way0_q[META_BITS-1:6];
    wire [TAG_BITS-1:0]   meta_tag_way1     = meta_way1_q[META_BITS-1:6];
    wire [TAG_BITS-1:0]   meta_tag_way2     = meta_way2_q[META_BITS-1:6];
    wire [TAG_BITS-1:0]   meta_tag_way3     = meta_way3_q[META_BITS-1:6];
    wire [1:0]            meta_lru          = lru_q;

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

    // Keep the post-BRAM mux/registers physically local to each 32-bit bank.
    // Each slice performs a 4:1 lookup selection and the registered 2:1 + 2:1
    // maintenance selection independently.  The line ports are only wiring
    // concatenations of these eight local registers.
    genvar line_bank;
    generate
        for (line_bank = 0; line_bank < 8; line_bank = line_bank + 1) begin : g_line_slice
            l2_line_slice_pipe u_slice (
                .clk                 (clk),
                .rst                 (rst),
                .way0_word           (data_way0_q[line_bank*32 +: 32]),
                .way1_word           (data_way1_q[line_bank*32 +: 32]),
                .way2_word           (data_way2_q[line_bank*32 +: 32]),
                .way3_word           (data_way3_q[line_bank*32 +: 32]),
                .lookup_capture      (lookup_select_pending),
                .lookup_way          (lookup_selected_way_q),
                .lookup_word_q       (lookup_line_banked_q[line_bank*32 +: 32]),
                .maint_pair_capture  (maint_pending),
                .maint_output_capture(maint_data_pending),
                .maint_way           (maint_way_q),
                .maint_word_q        (maint_line_banked_q[line_bank*32 +: 32])
            );
        end
    endgenerate

    assign resp_line       = lookup_line_banked_q;
    assign maint_line_data = maint_line_banked_q;

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
        case (lookup_selected_way_q)
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
            lookup_select_pending <= 1'b0;
            lookup_index        <= {INDEX_BITS{1'b0}};
            lookup_tag          <= {TAG_BITS{1'b0}};
            lookup_hit_q        <= 1'b0;
            lookup_selected_way_q <= 2'b0;
            maint_pending       <= 1'b0;
            maint_data_pending  <= 1'b0;
            maint_set_q         <= {INDEX_BITS{1'b0}};
            maint_way_q         <= 2'b0;
        end
        else if (init_active) begin
            resp_valid <= 1'b0;
            maint_resp_valid <= 1'b0;
            lookup_addr_pending <= 1'b0;
            lookup_meta_pending <= 1'b0;
            lookup_select_pending <= 1'b0;
            maint_pending <= 1'b0;
            maint_data_pending <= 1'b0;

            // Packed metadata BRAMs clear all four valid bits and LRU at this
            // one address through their explicit write ports.

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
            // only after directory read, tag compare/way selection and local
            // bank selection have completed.
            resp_valid <= lookup_select_pending || data_ram_we;
            maint_resp_valid <= maint_data_pending;
            lookup_addr_pending <= lookup_accept;
            lookup_meta_pending <= lookup_addr_pending;
            lookup_select_pending <= lookup_meta_pending;
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

            // Stage 3: terminate tag comparison and victim-way selection at a
            // narrow register boundary.  This prevents the tag comparators,
            // LRU mux and four-way metadata mux from sharing one 300-MHz path.
            if (lookup_meta_pending) begin
                lookup_hit_q          <= hit_v;
                lookup_selected_way_q <= selected_way;
            end

            // Stage 4: mux the selected directory entry from the registered
            // way.  The eight local line slices capture their corresponding
            // 32-bit BRAM words on this same edge.
            if (lookup_select_pending) begin
                resp_hit            <= lookup_hit_q;
                resp_way            <= lookup_selected_way_q;
                resp_victim_tag     <= selected_tag_v;
                resp_victim_valid   <= selected_valid_v;
                resp_victim_dirty   <= selected_dirty_v;
                resp_victim_sharers <= selected_sharers_v;
                resp_sharers        <= selected_sharers_v;
            end

            if (maint_read) begin
                maint_set_q <= maint_set;
                maint_way_q <= maint_way;
            end

            // Metadata follows the first maintenance data-slice stage.  The
            // actual word muxes/registers live in g_line_slice[*].u_slice.
            if (maint_pending) begin
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

            // Metadata writes (fill/update/invalidate) and LRU updates are
            // driven through the explicit block-RAM ports above.
        end
    end

endmodule

// One 32-bit post-BRAM slice.  Keeping this register hierarchy separate for
// every word gives placement eight small local cones instead of one 256-bit
// mux/register cone spanning all data BRAMs.
module l2_line_slice_pipe (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] way0_word,
    input  wire [31:0] way1_word,
    input  wire [31:0] way2_word,
    input  wire [31:0] way3_word,
    input  wire        lookup_capture,
    input  wire [1:0]  lookup_way,
    output reg  [31:0] lookup_word_q,
    input  wire        maint_pair_capture,
    input  wire        maint_output_capture,
    input  wire [1:0]  maint_way,
    output reg  [31:0] maint_word_q
);
    reg [31:0] maint_pair_low_q;
    reg [31:0] maint_pair_high_q;
    reg        maint_upper_q;

    always @(posedge clk) begin
        if (rst) begin
            lookup_word_q    <= 32'b0;
            maint_pair_low_q  <= 32'b0;
            maint_pair_high_q <= 32'b0;
            maint_upper_q     <= 1'b0;
            maint_word_q      <= 32'b0;
        end
        else begin
            if (lookup_capture) begin
                case (lookup_way)
                    2'd0: lookup_word_q <= way0_word;
                    2'd1: lookup_word_q <= way1_word;
                    2'd2: lookup_word_q <= way2_word;
                    default: lookup_word_q <= way3_word;
                endcase
            end
            if (maint_pair_capture) begin
                maint_pair_low_q  <= maint_way[0] ? way1_word : way0_word;
                maint_pair_high_q <= maint_way[0] ? way3_word : way2_word;
                maint_upper_q     <= maint_way[1];
            end
            if (maint_output_capture)
                maint_word_q <= maint_upper_q ? maint_pair_high_q : maint_pair_low_q;
        end
    end
endmodule

// Packed synchronous metadata/LRU storage.  XPM makes the intended physical
// primitive explicit in synthesis; the behavioral model preserves read-first,
// one-cycle semantics for XSIM.
module l2_sync_block_ram #(
    parameter integer ADDR_WIDTH = 12,
    parameter integer WIDTH = 21
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [WIDTH-1:0]      din,
    output wire [WIDTH-1:0]      dout
);
`ifdef SYNTHESIS
    xpm_memory_spram #(
        .ADDR_WIDTH_A       (ADDR_WIDTH),
        .AUTO_SLEEP_TIME    (0),
        .BYTE_WRITE_WIDTH_A (WIDTH),
        .CASCADE_HEIGHT     (0),
        .ECC_MODE           ("no_ecc"),
        .MEMORY_INIT_FILE   ("none"),
        .MEMORY_INIT_PARAM  ("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE   ("block"),
        .MEMORY_SIZE        (WIDTH * (1 << ADDR_WIDTH)),
        .MESSAGE_CONTROL    (0),
        .READ_DATA_WIDTH_A  (WIDTH),
        .READ_LATENCY_A     (1),
        .READ_RESET_VALUE_A ("0"),
        .RST_MODE_A         ("SYNC"),
        .SIM_ASSERT_CHK     (0),
        .USE_MEM_INIT       (0),
        .WAKEUP_TIME        ("disable_sleep"),
        .WRITE_DATA_WIDTH_A (WIDTH),
        .WRITE_MODE_A       ("read_first"),
        .WRITE_PROTECT      (1)
    ) u_xpm (
        .sleep(1'b0), .clka(clk), .rsta(1'b0), .ena(1'b1),
        .regcea(1'b1), .wea(we), .addra(addr), .dina(din),
        .injectsbiterra(1'b0), .injectdbiterra(1'b0),
        .douta(dout), .sbiterra(), .dbiterra()
    );
`else
    reg [WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];
    reg [WIDTH-1:0] dout_r;

    assign dout = dout_r;
    always @(posedge clk) begin
        if (we)
            mem[addr] <= din;
        dout_r <= mem[addr];
    end
`endif
endmodule

// Explicit single-port data store for one L2 way.  Eight independent 32-bit
// memories make the physical banking visible to synthesis and placement; the
// old 256-bit XPM encouraged a single wide cone spanning every BRAM column.
module l2_way_data_ram #(
    parameter integer ADDR_WIDTH = 12
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] addr,
    input  wire [255:0]          din,
    output wire [255:0]          dout
);
    genvar word_bank;
    generate
        for (word_bank = 0; word_bank < 8; word_bank = word_bank + 1) begin : g_word_bank
            l2_sync_block_ram #(
                .ADDR_WIDTH(ADDR_WIDTH),
                .WIDTH     (32)
            ) u_word_ram (
                .clk (clk),
                .we  (we),
                .addr(addr),
                .din (din[word_bank*32 +: 32]),
                .dout(dout[word_bank*32 +: 32])
            );
        end
    endgenerate
endmodule
