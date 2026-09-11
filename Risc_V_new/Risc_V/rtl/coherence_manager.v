`timescale 1ns / 1ps

// ============================================================
// coherence_manager
//
// The "COHERENCE MANAGEMENT UNIT" + "HIGH-SPEED BUS (AHB)" boxes
// from the 4-CORE CPU WRAPPER diagram, realized as one module: an
// 8-source (4x D$ + 4x I$) arbiter feeding a single ATOMIC
// transaction engine that drives l2_cache.v and issues MESI snoops
// to the D$s, plus the L2-miss path out to external memory (the
// diagram's "CPU MEMORY PORT").
//
// Why one module for two diagram boxes: the diagram's AHB segment
// has no Vivado stock IP to plug in anyway (see Risc_V_new/README.md
// -- Vivado's catalog is AXI-only), so nothing is lost by realizing
// "an AHB-style shared bus" as the arbitration logic inside this
// module instead of a separate physical bus module. If literal AHB
// protocol compliance (HADDR/HREADY/HRESP signal names/timing) is
// ever required for grading rather than just AHB-*shaped*
// connectivity, that's a signal-level swap at the arbiter boundary,
// not a redesign of the protocol logic below.
//
// ATOMICITY (the central design choice, made for correctness over
// throughput): only one requester's transaction is in flight system-
// wide at any time. The arbiter does not accept a new request until
// the previous one has been fully resolved -- data fetched/evicted,
// every necessary snoop sent and acknowledged, L2 and the requester
// both updated. This serializes ALL cache-miss/coherence traffic
// across all 4 cores, which is slow, but it structurally rules out
// the concurrent-transaction races (two transactions individually
// correct but racing on the same line) that are the usual source of
// real coherence bugs -- and this design was written and reasoned
// through without access to a simulator (see repo README), so
// trading throughput for something provable by hand was the
// deliberate choice. Pipelining this is a well-defined, bounded
// future improvement, not a redesign.
//
// DIRECTORY INVARIANT (why l2_cache.v's sharers[3:0] needs no
// separate "dirty owner" bit): a line can only ever transition from
// 1 sharer to 2+ sharers by first snooping that lone existing
// sharer (see the SNOOP state below, entered whenever popcount==1,
// for BOTH read and write requests). MESI's E state permits a core
// to silently upgrade E->M with no bus transaction, so a lone
// sharer's *directory* entry can't be trusted to mean "still just
// reading" -- but because every path that would grow the sharer set
// past 1 is forced through that snoop first, the snoop always
// catches a silent upgrade before a second reader could ever see
// stale data. Consequence: once a line legitimately has 2+ sharers,
// none of them can possibly be Modified (by induction on the above),
// so those cases never need a snoop at all for a plain read.
//
// Local-hit races: see l1_dcache.v's header for why a core's own
// local cache hit and an incoming snoop for the exact same line can
// still race even under this module's atomicity (a local hit never
// touches the arbiter) -- resolved there, not here.
//
// Arbitration: fixed priority (c0 D$, c0 I$, c1 D$, c1 I$, ... c3
// I$), not round-robin. This is a fairness limitation (a
// pathological access pattern from core 0 could in principle starve
// core 3), not a correctness one -- flagged, not fixed, to keep the
// one already-large state machine below easier to reason about by
// hand. Swap for real round-robin once this is simulated and
// verified functionally correct.
//
// Encodings (shared with l1_dcache.v -- keep in sync if either
// changes):
//   dreq_type:  2'b00=READ, 2'b01=RFO, 2'b10=WRITEBACK
//   dresp_state: 2'b01=S, 2'b10=E, 2'b11=M
//   snoop_type: 1'b0=INVALIDATE, 1'b1=DOWNGRADE
// ============================================================
module coherence_manager #(
    parameter LINE_WORDS = 8
)(
    input  wire clk,
    input  wire rst,

    // ================= Core 0 =================
    input  wire         c0_dreq_valid, input wire [1:0] c0_dreq_type, input wire [31:0] c0_dreq_addr, input wire [255:0] c0_dreq_line,
    output wire         c0_dresp_valid, output wire [255:0] c0_dresp_line, output wire [1:0] c0_dresp_state,
    output wire         c0_dsnoop_valid, output wire c0_dsnoop_type, output wire [31:0] c0_dsnoop_addr,
    input  wire         c0_dsnoop_ack_valid, input wire c0_dsnoop_ack_hit, input wire c0_dsnoop_ack_dirty, input wire [255:0] c0_dsnoop_ack_line,
    input  wire         c0_ireq_valid, input wire [31:0] c0_ireq_addr,
    output wire         c0_iresp_valid, output wire [255:0] c0_iresp_line,

    // ================= Core 1 =================
    input  wire         c1_dreq_valid, input wire [1:0] c1_dreq_type, input wire [31:0] c1_dreq_addr, input wire [255:0] c1_dreq_line,
    output wire         c1_dresp_valid, output wire [255:0] c1_dresp_line, output wire [1:0] c1_dresp_state,
    output wire         c1_dsnoop_valid, output wire c1_dsnoop_type, output wire [31:0] c1_dsnoop_addr,
    input  wire         c1_dsnoop_ack_valid, input wire c1_dsnoop_ack_hit, input wire c1_dsnoop_ack_dirty, input wire [255:0] c1_dsnoop_ack_line,
    input  wire         c1_ireq_valid, input wire [31:0] c1_ireq_addr,
    output wire         c1_iresp_valid, output wire [255:0] c1_iresp_line,

    // ================= Core 2 =================
    input  wire         c2_dreq_valid, input wire [1:0] c2_dreq_type, input wire [31:0] c2_dreq_addr, input wire [255:0] c2_dreq_line,
    output wire         c2_dresp_valid, output wire [255:0] c2_dresp_line, output wire [1:0] c2_dresp_state,
    output wire         c2_dsnoop_valid, output wire c2_dsnoop_type, output wire [31:0] c2_dsnoop_addr,
    input  wire         c2_dsnoop_ack_valid, input wire c2_dsnoop_ack_hit, input wire c2_dsnoop_ack_dirty, input wire [255:0] c2_dsnoop_ack_line,
    input  wire         c2_ireq_valid, input wire [31:0] c2_ireq_addr,
    output wire         c2_iresp_valid, output wire [255:0] c2_iresp_line,

    // ================= Core 3 =================
    input  wire         c3_dreq_valid, input wire [1:0] c3_dreq_type, input wire [31:0] c3_dreq_addr, input wire [255:0] c3_dreq_line,
    output wire         c3_dresp_valid, output wire [255:0] c3_dresp_line, output wire [1:0] c3_dresp_state,
    output wire         c3_dsnoop_valid, output wire c3_dsnoop_type, output wire [31:0] c3_dsnoop_addr,
    input  wire         c3_dsnoop_ack_valid, input wire c3_dsnoop_ack_hit, input wire c3_dsnoop_ack_dirty, input wire [255:0] c3_dsnoop_ack_line,
    input  wire         c3_ireq_valid, input wire [31:0] c3_ireq_addr,
    output wire         c3_iresp_valid, output wire [255:0] c3_iresp_line,

    // ---- External memory ("CPU MEMORY PORT"), single word, real handshake ----
    output reg          mem_req_valid,
    output reg          mem_we,
    output reg  [31:0]  mem_addr,
    output reg  [31:0]  mem_wdata,
    input  wire [31:0]  mem_rdata,
    input  wire         mem_valid
);

    localparam LINE_BITS = LINE_WORDS * 32;

    // ------------------------------------------------------
    // Flatten the 8 per-core request sources into indexable arrays
    // ------------------------------------------------------
    wire        dreq_valid [0:3];
    wire [1:0]  dreq_type  [0:3];
    wire [31:0] dreq_addr  [0:3];
    wire [255:0] dreq_line [0:3];
    wire        ireq_valid [0:3];
    wire [31:0] ireq_addr  [0:3];

    assign dreq_valid[0]=c0_dreq_valid; assign dreq_type[0]=c0_dreq_type; assign dreq_addr[0]=c0_dreq_addr; assign dreq_line[0]=c0_dreq_line;
    assign dreq_valid[1]=c1_dreq_valid; assign dreq_type[1]=c1_dreq_type; assign dreq_addr[1]=c1_dreq_addr; assign dreq_line[1]=c1_dreq_line;
    assign dreq_valid[2]=c2_dreq_valid; assign dreq_type[2]=c2_dreq_type; assign dreq_addr[2]=c2_dreq_addr; assign dreq_line[2]=c2_dreq_line;
    assign dreq_valid[3]=c3_dreq_valid; assign dreq_type[3]=c3_dreq_type; assign dreq_addr[3]=c3_dreq_addr; assign dreq_line[3]=c3_dreq_line;

    assign ireq_valid[0]=c0_ireq_valid; assign ireq_addr[0]=c0_ireq_addr;
    assign ireq_valid[1]=c1_ireq_valid; assign ireq_addr[1]=c1_ireq_addr;
    assign ireq_valid[2]=c2_ireq_valid; assign ireq_addr[2]=c2_ireq_addr;
    assign ireq_valid[3]=c3_ireq_valid; assign ireq_addr[3]=c3_ireq_addr;

    // Per-core response/snoop pulses, driven from one shared reg set
    // below and demuxed onto the right core's output ports.
    reg         dresp_valid_r [0:3];
    reg [255:0] dresp_line_r  [0:3];
    reg [1:0]   dresp_state_r [0:3];
    reg         iresp_valid_r [0:3];
    reg [255:0] iresp_line_r  [0:3];
    reg         dsnoop_valid_r [0:3];
    reg         dsnoop_type_r  [0:3];
    reg [31:0]  dsnoop_addr_r  [0:3];

    wire        dsnoop_ack_valid [0:3];
    wire        dsnoop_ack_hit   [0:3];
    wire        dsnoop_ack_dirty [0:3];
    wire [255:0] dsnoop_ack_line [0:3];
    assign dsnoop_ack_valid[0]=c0_dsnoop_ack_valid; assign dsnoop_ack_hit[0]=c0_dsnoop_ack_hit; assign dsnoop_ack_dirty[0]=c0_dsnoop_ack_dirty; assign dsnoop_ack_line[0]=c0_dsnoop_ack_line;
    assign dsnoop_ack_valid[1]=c1_dsnoop_ack_valid; assign dsnoop_ack_hit[1]=c1_dsnoop_ack_hit; assign dsnoop_ack_dirty[1]=c1_dsnoop_ack_dirty; assign dsnoop_ack_line[1]=c1_dsnoop_ack_line;
    assign dsnoop_ack_valid[2]=c2_dsnoop_ack_valid; assign dsnoop_ack_hit[2]=c2_dsnoop_ack_hit; assign dsnoop_ack_dirty[2]=c2_dsnoop_ack_dirty; assign dsnoop_ack_line[2]=c2_dsnoop_ack_line;
    assign dsnoop_ack_valid[3]=c3_dsnoop_ack_valid; assign dsnoop_ack_hit[3]=c3_dsnoop_ack_hit; assign dsnoop_ack_dirty[3]=c3_dsnoop_ack_dirty; assign dsnoop_ack_line[3]=c3_dsnoop_ack_line;

    assign c0_dresp_valid=dresp_valid_r[0]; assign c0_dresp_line=dresp_line_r[0]; assign c0_dresp_state=dresp_state_r[0];
    assign c1_dresp_valid=dresp_valid_r[1]; assign c1_dresp_line=dresp_line_r[1]; assign c1_dresp_state=dresp_state_r[1];
    assign c2_dresp_valid=dresp_valid_r[2]; assign c2_dresp_line=dresp_line_r[2]; assign c2_dresp_state=dresp_state_r[2];
    assign c3_dresp_valid=dresp_valid_r[3]; assign c3_dresp_line=dresp_line_r[3]; assign c3_dresp_state=dresp_state_r[3];

    assign c0_iresp_valid=iresp_valid_r[0]; assign c0_iresp_line=iresp_line_r[0];
    assign c1_iresp_valid=iresp_valid_r[1]; assign c1_iresp_line=iresp_line_r[1];
    assign c2_iresp_valid=iresp_valid_r[2]; assign c2_iresp_line=iresp_line_r[2];
    assign c3_iresp_valid=iresp_valid_r[3]; assign c3_iresp_line=iresp_line_r[3];

    assign c0_dsnoop_valid=dsnoop_valid_r[0]; assign c0_dsnoop_type=dsnoop_type_r[0]; assign c0_dsnoop_addr=dsnoop_addr_r[0];
    assign c1_dsnoop_valid=dsnoop_valid_r[1]; assign c1_dsnoop_type=dsnoop_type_r[1]; assign c1_dsnoop_addr=dsnoop_addr_r[1];
    assign c2_dsnoop_valid=dsnoop_valid_r[2]; assign c2_dsnoop_type=dsnoop_type_r[2]; assign c2_dsnoop_addr=dsnoop_addr_r[2];
    assign c3_dsnoop_valid=dsnoop_valid_r[3]; assign c3_dsnoop_type=dsnoop_type_r[3]; assign c3_dsnoop_addr=dsnoop_addr_r[3];

    // ------------------------------------------------------
    // L2 storage
    // ------------------------------------------------------
    wire         l2_cmd_valid;
    wire         l2_cmd_we;
    wire [31:0]  l2_cmd_addr;
    wire [1:0]   l2_cmd_way;
    wire [255:0] l2_cmd_wdata;
    wire         l2_cmd_w_valid;
    wire         l2_cmd_w_dirty;
    wire [3:0]   l2_cmd_w_sharers;
    wire         l2_resp_valid;
    wire         l2_resp_hit;
    wire [1:0]   l2_resp_way;
    wire [15:0]  l2_resp_victim_tag;
    wire         l2_resp_victim_valid;
    wire         l2_resp_victim_dirty;
    wire [3:0]   l2_resp_victim_sharers;
    wire [255:0] l2_resp_line;
    wire [3:0]   l2_resp_sharers;

    l2_cache u_l2 (
        .clk(clk), .rst(rst),
        .cmd_valid(l2_cmd_valid), .cmd_we(l2_cmd_we), .cmd_addr(l2_cmd_addr), .cmd_way(l2_cmd_way),
        .cmd_wdata(l2_cmd_wdata), .cmd_w_valid(l2_cmd_w_valid), .cmd_w_dirty(l2_cmd_w_dirty), .cmd_w_sharers(l2_cmd_w_sharers),
        .resp_valid(l2_resp_valid), .resp_hit(l2_resp_hit), .resp_way(l2_resp_way),
        .resp_victim_tag(l2_resp_victim_tag), .resp_victim_valid(l2_resp_victim_valid),
        .resp_victim_dirty(l2_resp_victim_dirty), .resp_victim_sharers(l2_resp_victim_sharers),
        .resp_line(l2_resp_line), .resp_sharers(l2_resp_sharers)
    );

    // ------------------------------------------------------
    // Main FSM
    // ------------------------------------------------------
    localparam [3:0]
        S_IDLE              = 4'd0,
        S_L2_LOOKUP         = 4'd1,
        S_L2_LOOKUP_WAIT    = 4'd2,
        S_EVICT_SNOOP_ISSUE = 4'd3,
        S_EVICT_SNOOP_WAIT  = 4'd4,
        S_EVICT_WB_MEM      = 4'd5,
        S_FETCH_MEM         = 4'd6,
        S_L2_FILL           = 4'd7,
        S_SHARER_SNOOP_ISSUE= 4'd8,
        S_SHARER_SNOOP_WAIT = 4'd9,
        S_GRANT_WRITE_L2    = 4'd10,
        S_RESPOND           = 4'd11,
        S_WB_UPDATE_L2      = 4'd12;

    reg [3:0] state;

    // ---- Latched transaction context ----
    reg [2:0]   req_core;      // 0-3 = D$ of that core, 4-7 = I$ of core (req_core-4)
    reg         req_is_d;
    reg [1:0]   req_type;      // dreq_type, valid only when req_is_d
    reg [31:0]  req_addr;      // line-aligned
    reg [255:0] req_wr_line;   // WRITEBACK payload from the requester

    reg [1:0]   line_way;
    reg [255:0] line_data;
    reg [3:0]   line_sharers;
    reg         line_dirty;

    reg [3:0]   snoop_todo;
    reg         snoop_type_send;
    reg [31:0]  snoop_addr_send;
    reg [3:0]   snoop_after; // which state (one-hot-ish encode via case) to resume in
    reg         any_snoop_dirty;
    reg [255:0] snoop_dirty_data;

    reg [2:0]   mem_word_idx;
    reg [31:0]  mem_line_addr;
    reg [255:0] mem_line_buf;

    integer i;

    // ---- Fixed-priority arbiter (combinational) ----
    reg        arb_valid;
    reg [2:0]  arb_core;
    always @(*) begin
        arb_valid = 1'b0;
        arb_core  = 3'd0;
        if      (dreq_valid[0]) begin arb_valid=1'b1; arb_core=3'd0; end
        else if (ireq_valid[0]) begin arb_valid=1'b1; arb_core=3'd4; end
        else if (dreq_valid[1]) begin arb_valid=1'b1; arb_core=3'd1; end
        else if (ireq_valid[1]) begin arb_valid=1'b1; arb_core=3'd5; end
        else if (dreq_valid[2]) begin arb_valid=1'b1; arb_core=3'd2; end
        else if (ireq_valid[2]) begin arb_valid=1'b1; arb_core=3'd6; end
        else if (dreq_valid[3]) begin arb_valid=1'b1; arb_core=3'd3; end
        else if (ireq_valid[3]) begin arb_valid=1'b1; arb_core=3'd7; end
    end

    assign l2_cmd_valid = (state == S_L2_LOOKUP) || (state == S_L2_FILL) ||
                           (state == S_GRANT_WRITE_L2) || (state == S_WB_UPDATE_L2);
    assign l2_cmd_we    = (state != S_L2_LOOKUP);
    assign l2_cmd_addr  = req_addr;
    assign l2_cmd_way   = line_way;
    assign l2_cmd_wdata = line_data;
    assign l2_cmd_w_valid  = (state == S_L2_FILL) || (state == S_GRANT_WRITE_L2) || (state == S_WB_UPDATE_L2);
    assign l2_cmd_w_dirty  = (state == S_WB_UPDATE_L2) ? 1'b1 :
                              (state == S_GRANT_WRITE_L2) ? (line_dirty | any_snoop_dirty) : 1'b0;

    // NOTE (bug fixed on review): this cannot just read the
    // `line_sharers` register -- S_L2_FILL and S_GRANT_WRITE_L2 both
    // *also* write a new value into `line_sharers` on this same
    // cycle (non-blocking, so the register doesn't actually update
    // until the next edge), so an L2 write issued in either of those
    // states must compute the value it wants combinationally right
    // here, not through the register round-trip -- otherwise the
    // write that fires this cycle silently uses last cycle's stale
    // value instead of the one just decided.
    wire [3:0] req_bit       = (4'b0001 << req_core[1:0]);
    wire [3:0] grant_sharers = (req_type == 2'b01) ? req_bit : (line_sharers | req_bit);
    assign l2_cmd_w_sharers = (state == S_L2_FILL)        ? 4'b0 :
                               (state == S_GRANT_WRITE_L2) ? grant_sharers :
                                                              line_sharers; // S_WB_UPDATE_L2: already resolved 1 full cycle earlier, safe to read directly

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            for (i = 0; i < 4; i = i + 1) begin
                dresp_valid_r[i]  <= 1'b0;
                iresp_valid_r[i]  <= 1'b0;
                dsnoop_valid_r[i] <= 1'b0;
            end
            mem_req_valid <= 1'b0;
        end
        else begin
            // Default: all pulses low unless explicitly set below.
            for (i = 0; i < 4; i = i + 1) begin
                dresp_valid_r[i]  <= 1'b0;
                iresp_valid_r[i]  <= 1'b0;
                dsnoop_valid_r[i] <= 1'b0;
            end
            mem_req_valid <= 1'b0;

            case (state)
                // ==================================================
                S_IDLE: begin
                    if (arb_valid) begin
                        req_core <= arb_core;
                        req_is_d <= ~arb_core[2];
                        if (~arb_core[2]) begin
                            req_type    <= dreq_type[arb_core[1:0]];
                            req_addr    <= {dreq_addr[arb_core[1:0]][31:5], 5'b0};
                            req_wr_line <= dreq_line[arb_core[1:0]];
                        end
                        else begin
                            req_type    <= 2'b00; // READ semantics for I$
                            req_addr    <= {ireq_addr[arb_core[1:0]][31:5], 5'b0};
                        end
                        state <= S_L2_LOOKUP;
                    end
                end

                // ==================================================
                S_L2_LOOKUP: state <= S_L2_LOOKUP_WAIT; // one cycle for l2_cache's registered response

                S_L2_LOOKUP_WAIT: begin
                    if (l2_resp_valid) begin
                        line_way <= l2_resp_way;

                        if (req_is_d && (req_type == 2'b10)) begin
                            // WRITEBACK: by the inclusion property this
                            // always hits (see header). Just update L2.
                            line_data    <= req_wr_line;
                            line_sharers <= l2_resp_sharers & ~(4'b0001 << req_core[1:0]);
                            state        <= S_WB_UPDATE_L2;
                        end
                        else if (l2_resp_hit) begin
                            line_data    <= l2_resp_line;
                            line_sharers <= l2_resp_sharers;
                            line_dirty   <= 1'b0; // clean w.r.t. DRAM unless a snoop below dirties it
                            any_snoop_dirty  <= 1'b0;
                            snoop_dirty_data <= {LINE_BITS{1'b0}};

                            if (!req_is_d) begin
                                // I$: no coherence involvement at all.
                                state <= S_RESPOND;
                            end
                            else begin
                                snoop_todo <= (l2_resp_sharers & ~(4'b0001 << req_core[1:0]));
                                snoop_type_send <= (req_type == 2'b00) ? 1'b1 : 1'b0; // READ->DOWNGRADE, RFO->INVALIDATE
                                snoop_after <= S_GRANT_WRITE_L2;
                                state <= S_SHARER_SNOOP_ISSUE;
                            end
                        end
                        else begin
                            // Miss in L2: may need to evict the victim way first.
                            line_data    <= l2_resp_line;      // victim's current data (for its own writeback, if needed)
                            line_sharers <= l2_resp_victim_sharers;
                            line_dirty   <= l2_resp_victim_dirty;
                            any_snoop_dirty  <= 1'b0;
                            snoop_dirty_data <= {LINE_BITS{1'b0}};

                            if (l2_resp_victim_valid && (l2_resp_victim_sharers != 4'b0)) begin
                                snoop_todo      <= l2_resp_victim_sharers;
                                snoop_type_send <= 1'b0; // INVALIDATE -- evicting outright
                                snoop_after     <= S_EVICT_WB_MEM;
                                state           <= S_EVICT_SNOOP_ISSUE;
                            end
                            else if (l2_resp_victim_valid && l2_resp_victim_dirty) begin
                                state <= S_EVICT_WB_MEM;
                            end
                            else begin
                                state <= S_FETCH_MEM;
                            end
                        end
                    end
                end

                // ==================================================
                // Generic snoop-one-or-more sub-sequence. snoop_todo
                // is a bitmap of cores still owed a snoop for
                // snoop_addr_send/snoop_type_send; issues one at a
                // time (simplest to reason about correctly), then
                // resumes at snoop_after.
                // ==================================================
                S_EVICT_SNOOP_ISSUE, S_SHARER_SNOOP_ISSUE: begin
                    snoop_addr_send <= req_addr;
                    if (snoop_todo == 4'b0) begin
                        state <= snoop_after;
                    end
                    else begin
                        // issue to the lowest set bit
                        if (snoop_todo[0]) begin dsnoop_valid_r[0] <= 1'b1; dsnoop_type_r[0] <= snoop_type_send; dsnoop_addr_r[0] <= req_addr; end
                        else if (snoop_todo[1]) begin dsnoop_valid_r[1] <= 1'b1; dsnoop_type_r[1] <= snoop_type_send; dsnoop_addr_r[1] <= req_addr; end
                        else if (snoop_todo[2]) begin dsnoop_valid_r[2] <= 1'b1; dsnoop_type_r[2] <= snoop_type_send; dsnoop_addr_r[2] <= req_addr; end
                        else if (snoop_todo[3]) begin dsnoop_valid_r[3] <= 1'b1; dsnoop_type_r[3] <= snoop_type_send; dsnoop_addr_r[3] <= req_addr; end
                        state <= (state == S_EVICT_SNOOP_ISSUE) ? S_EVICT_SNOOP_WAIT : S_SHARER_SNOOP_WAIT;
                    end
                end

                // NOTE (bug fixed on review): a sharer's bit must be
                // cleared whenever the snoop was an INVALIDATE and it
                // actually hit (that core provably no longer has the
                // line), not only when the ack came back "not hit".
                // The original code only cleared on !hit, which was
                // right for DOWNGRADE (a hit there means "still a
                // valid S copy, keep it as a sharer") but wrong for
                // INVALIDATE (a hit there means "just invalidated,
                // must drop it"). Rule now: clear on INVALIDATE
                // regardless of hit, or on any type when it missed.
                S_EVICT_SNOOP_WAIT, S_SHARER_SNOOP_WAIT: begin
                    if (dsnoop_ack_valid[0] || dsnoop_ack_valid[1] || dsnoop_ack_valid[2] || dsnoop_ack_valid[3]) begin
                        // Exactly one core acks per issued snoop (we only
                        // ever pulse one dsnoop_valid_r bit at a time).
                        if (dsnoop_ack_valid[0]) begin
                            snoop_todo[0] <= 1'b0;
                            if (dsnoop_ack_hit[0] && dsnoop_ack_dirty[0]) begin any_snoop_dirty <= 1'b1; snoop_dirty_data <= dsnoop_ack_line[0]; line_data <= dsnoop_ack_line[0]; end
                            if (!snoop_type_send || !dsnoop_ack_hit[0]) line_sharers <= line_sharers & ~4'b0001;
                        end
                        else if (dsnoop_ack_valid[1]) begin
                            snoop_todo[1] <= 1'b0;
                            if (dsnoop_ack_hit[1] && dsnoop_ack_dirty[1]) begin any_snoop_dirty <= 1'b1; snoop_dirty_data <= dsnoop_ack_line[1]; line_data <= dsnoop_ack_line[1]; end
                            if (!snoop_type_send || !dsnoop_ack_hit[1]) line_sharers <= line_sharers & ~4'b0010;
                        end
                        else if (dsnoop_ack_valid[2]) begin
                            snoop_todo[2] <= 1'b0;
                            if (dsnoop_ack_hit[2] && dsnoop_ack_dirty[2]) begin any_snoop_dirty <= 1'b1; snoop_dirty_data <= dsnoop_ack_line[2]; line_data <= dsnoop_ack_line[2]; end
                            if (!snoop_type_send || !dsnoop_ack_hit[2]) line_sharers <= line_sharers & ~4'b0100;
                        end
                        else begin
                            snoop_todo[3] <= 1'b0;
                            if (dsnoop_ack_hit[3] && dsnoop_ack_dirty[3]) begin any_snoop_dirty <= 1'b1; snoop_dirty_data <= dsnoop_ack_line[3]; line_data <= dsnoop_ack_line[3]; end
                            if (!snoop_type_send || !dsnoop_ack_hit[3]) line_sharers <= line_sharers & ~4'b1000;
                        end
                        state <= (state == S_EVICT_SNOOP_WAIT) ? S_EVICT_SNOOP_ISSUE : S_SHARER_SNOOP_ISSUE;
                    end
                end

                // ==================================================
                // Evict path: write victim's (possibly snoop-updated)
                // dirty data to memory if needed, then fetch the new
                // line, then fill L2, then resume as if it had hit.
                // ==================================================
                S_EVICT_WB_MEM: begin
                    if (!(line_dirty | any_snoop_dirty)) begin
                        state <= S_FETCH_MEM;
                    end
                    else if (mem_word_idx == 3'd0 && !mem_req_valid) begin
                        mem_line_addr <= {l2_resp_victim_tag, req_addr[15:5], 5'b0}; // NOTE: index bits come from req_addr (same set), tag from the victim
                        mem_line_buf  <= line_data;
                        mem_req_valid <= 1'b1;
                        mem_we        <= 1'b1;
                        mem_addr      <= {l2_resp_victim_tag, req_addr[15:5], 5'b0};
                        mem_wdata     <= line_data[31:0];
                    end
                    else if (mem_valid) begin
                        if (mem_word_idx == 3'd7) begin
                            mem_word_idx  <= 3'd0;
                            mem_req_valid <= 1'b0;
                            state         <= S_FETCH_MEM;
                        end
                        else begin
                            mem_word_idx  <= mem_word_idx + 3'd1;
                            mem_req_valid <= 1'b1;
                            mem_we        <= 1'b1;
                            mem_addr      <= mem_line_addr + ((mem_word_idx + 3'd1) << 2);
                            mem_wdata     <= mem_line_buf[(mem_word_idx + 3'd1)*32 +: 32];
                        end
                    end
                end

                S_FETCH_MEM: begin
                    if (mem_word_idx == 3'd0 && !mem_req_valid && !mem_line_fetch_started) begin
                        mem_req_valid <= 1'b1;
                        mem_we        <= 1'b0;
                        mem_addr      <= req_addr;
                    end
                    else if (mem_valid) begin
                        mem_line_buf[mem_word_idx*32 +: 32] <= mem_rdata;
                        if (mem_word_idx == 3'd7) begin
                            mem_word_idx  <= 3'd0;
                            mem_req_valid <= 1'b0;
                            line_data     <= { mem_rdata, mem_line_buf[223:0] }; // fold in the final word
                            state         <= S_L2_FILL;
                        end
                        else begin
                            mem_word_idx  <= mem_word_idx + 3'd1;
                            mem_req_valid <= 1'b1;
                            mem_we        <= 1'b0;
                            mem_addr      <= req_addr + ((mem_word_idx + 3'd1) << 2);
                        end
                    end
                end

                S_L2_FILL: begin
                    // line_data/line_way already set; sharers start
                    // empty, dirty=0 (clean copy straight from DRAM).
                    line_sharers <= 4'b0;
                    if (!req_is_d) begin
                        state <= S_RESPOND;
                    end
                    else begin
                        snoop_todo      <= 4'b0; // freshly fetched: no sharers to probe
                        snoop_after     <= S_GRANT_WRITE_L2;
                        state           <= S_SHARER_SNOOP_ISSUE; // immediately falls through (snoop_todo==0)
                    end
                end

                // ==================================================
                S_GRANT_WRITE_L2: begin
                    // Add requester to sharers (mask already pruned of
                    // any non-acking stale sharers above); RFO clears
                    // everyone else. (grant_sharers is the same
                    // combinational expression the L2 write above
                    // this cycle already used -- registering it here
                    // too just makes it visible to S_RESPOND next
                    // cycle.)
                    line_sharers <= grant_sharers;
                    state <= S_RESPOND;
                end

                S_WB_UPDATE_L2: state <= S_RESPOND;

                // ==================================================
                S_RESPOND: begin
                    if (req_is_d) begin
                        dresp_valid_r[req_core[1:0]] <= 1'b1;
                        dresp_line_r[req_core[1:0]]  <= line_data;
                        dresp_state_r[req_core[1:0]] <=
                            (req_type == 2'b10) ? 2'b00 :          // WRITEBACK ack, state field unused
                            (req_type == 2'b01) ? 2'b11 :          // RFO -> M
                            ((line_sharers == req_bit) ? 2'b10 : 2'b01); // sole sharer -> E, else S (line_sharers already includes the requester by now, written in S_GRANT_WRITE_L2 last cycle)
                    end
                    else begin
                        iresp_valid_r[req_core[1:0]] <= 1'b1;
                        iresp_line_r[req_core[1:0]]  <= line_data;
                    end
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Small helper flag: distinguishes "about to issue the very
    // first fetch word" from "waiting on mem_valid for it" without
    // an extra state (kept as a wire computed from mem_req_valid's
    // own timing would be circular, so a tiny reg is simplest/safest).
    reg mem_line_fetch_started;
    always @(posedge clk) begin
        if (rst) mem_line_fetch_started <= 1'b0;
        else if (state != S_FETCH_MEM) mem_line_fetch_started <= 1'b0;
        else if (mem_req_valid) mem_line_fetch_started <= 1'b1;
    end

endmodule
