`timescale 1ns / 1ps

// ============================================================
// coherence_manager
//
// Protocol engine used by the shared cache controller.  It contains
// the 8-source (4x D$ + 4x I$) round-robin arbiter, the atomic MSI
// transaction FSM and the external-memory line-transfer engine.
//
// EXTERNAL_L2=0 preserves the original, self-contained integration
// used by legacy unit tests.  EXTERNAL_L2=1 exports the command/status
// interface of l2_cache so the active quad-core hierarchy can place
// the controller and L2 as peer blocks.  That peer topology matches
// the project adviser terminology: the shared "MMU" is a cache/memory
// controller, while the per-core Sv32 block remains the architectural
// address-translation unit.
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
// DIRECTORY INVARIANT: the directory stores a sharer bitmap but no
// separate dirty-owner ID. Under MSI every transition S->M is an RFO
// observed here, so an M line has exactly one directory bit set. A
// BusRd/BusRdX snoops every other listed holder; an M holder returns
// the authoritative line and then moves to S/I. This keeps L2 data
// coherent without relying on MESI's silent E->M transition.
//
// Local-hit races: see l1_dcache.v's header for why a core's own
// local cache hit and an incoming snoop for the exact same line can
// still race even under this module's atomicity (a local hit never
// touches the arbiter) -- resolved there, not here.
//
// Arbitration is starvation-free round-robin over all eight D$/I$
// sources.  The pointer advances only when S_IDLE accepts a request;
// a level-held requester therefore cannot be skipped or accepted
// twice while another transaction is in flight.
//
// Encodings (shared with l1_dcache.v -- keep in sync if either
// changes):
//   dreq_type:  2'b00=READ, 2'b01=RFO, 2'b10=WRITEBACK,
//               2'b11=UNCACHED single-word bypass
//   dresp_state: 2'b01=S, 2'b11=M (2'b10 is unused)
//   snoop_type: 1'b0=INVALIDATE, 1'b1=DOWNGRADE
//
// EXTERNAL MEMORY ERRORS: mem_error is sampled only with mem_valid and
// returned to the serialized transaction's original I$/D$ requester.
// Failed fills never enter L2. If a dirty victim writeback fails after
// snoops have removed other copies, the authoritative line is restored
// into its original L2 way/tag as dirty before the error response fires.
// UNCACHED requests bypass L2/directory/snoops and carry one write-enable,
// four byte strobes and shifted write data in dreq_line[36:0].
// ============================================================
module coherence_manager_engine #(
    parameter LINE_WORDS = 8,
    parameter PERF_COUNTER_ENABLE = 1,
    parameter DEBUG_TRACE_ENABLE = 0,
    parameter integer WATCHDOG_LIMIT = 1024,
    parameter EXTERNAL_L2 = 0
)(
    input  wire clk,
    input  wire rst,

    // ================= Core 0 =================
    input  wire         c0_dreq_valid, input wire [1:0] c0_dreq_type, input wire [31:0] c0_dreq_addr, input wire [255:0] c0_dreq_line,
    output wire         c0_dresp_valid, output wire c0_dresp_error, output wire [255:0] c0_dresp_line, output wire [1:0] c0_dresp_state,
    output wire         c0_dsnoop_valid, output wire c0_dsnoop_type, output wire [31:0] c0_dsnoop_addr,
    input  wire         c0_dsnoop_ack_valid, input wire c0_dsnoop_ack_hit, input wire c0_dsnoop_ack_dirty, input wire [255:0] c0_dsnoop_ack_line,
    input  wire         c0_ireq_valid, input wire [31:0] c0_ireq_addr,
    output wire         c0_iresp_valid, output wire c0_iresp_error, output wire [255:0] c0_iresp_line,

    // ================= Core 1 =================
    input  wire         c1_dreq_valid, input wire [1:0] c1_dreq_type, input wire [31:0] c1_dreq_addr, input wire [255:0] c1_dreq_line,
    output wire         c1_dresp_valid, output wire c1_dresp_error, output wire [255:0] c1_dresp_line, output wire [1:0] c1_dresp_state,
    output wire         c1_dsnoop_valid, output wire c1_dsnoop_type, output wire [31:0] c1_dsnoop_addr,
    input  wire         c1_dsnoop_ack_valid, input wire c1_dsnoop_ack_hit, input wire c1_dsnoop_ack_dirty, input wire [255:0] c1_dsnoop_ack_line,
    input  wire         c1_ireq_valid, input wire [31:0] c1_ireq_addr,
    output wire         c1_iresp_valid, output wire c1_iresp_error, output wire [255:0] c1_iresp_line,

    // ================= Core 2 =================
    input  wire         c2_dreq_valid, input wire [1:0] c2_dreq_type, input wire [31:0] c2_dreq_addr, input wire [255:0] c2_dreq_line,
    output wire         c2_dresp_valid, output wire c2_dresp_error, output wire [255:0] c2_dresp_line, output wire [1:0] c2_dresp_state,
    output wire         c2_dsnoop_valid, output wire c2_dsnoop_type, output wire [31:0] c2_dsnoop_addr,
    input  wire         c2_dsnoop_ack_valid, input wire c2_dsnoop_ack_hit, input wire c2_dsnoop_ack_dirty, input wire [255:0] c2_dsnoop_ack_line,
    input  wire         c2_ireq_valid, input wire [31:0] c2_ireq_addr,
    output wire         c2_iresp_valid, output wire c2_iresp_error, output wire [255:0] c2_iresp_line,

    // ================= Core 3 =================
    input  wire         c3_dreq_valid, input wire [1:0] c3_dreq_type, input wire [31:0] c3_dreq_addr, input wire [255:0] c3_dreq_line,
    output wire         c3_dresp_valid, output wire c3_dresp_error, output wire [255:0] c3_dresp_line, output wire [1:0] c3_dresp_state,
    output wire         c3_dsnoop_valid, output wire c3_dsnoop_type, output wire [31:0] c3_dsnoop_addr,
    input  wire         c3_dsnoop_ack_valid, input wire c3_dsnoop_ack_hit, input wire c3_dsnoop_ack_dirty, input wire [255:0] c3_dsnoop_ack_line,
    input  wire         c3_ireq_valid, input wire [31:0] c3_ireq_addr,
    output wire         c3_iresp_valid, output wire c3_iresp_error, output wire [255:0] c3_iresp_line,

    // ---- External memory ("CPU MEMORY PORT"), single word, real handshake ----
    output reg          mem_req_valid,
    output reg          mem_we,
    output reg  [31:0]  mem_addr,
    output reg  [31:0]  mem_wdata,
    output reg  [3:0]   mem_wstrb,
    input  wire [31:0]  mem_rdata,
    input  wire         mem_valid,
    input  wire         mem_error,

    // ---- Bring-up observability (free-running, saturating only by 32-bit wrap) ----
    output reg [31:0] perf_total_requests,
    output reg [31:0] perf_d_bus_reads,
    output reg [31:0] perf_d_rfos,
    output reg [31:0] perf_d_writebacks,
    output reg [31:0] perf_i_reads,
    output reg [31:0] perf_l2_hits,
    output reg [31:0] perf_l2_misses,
    output reg [31:0] perf_snoop_requests,
    output reg [31:0] perf_mem_read_words,
    output reg [31:0] perf_mem_write_words,
    output reg [31:0] perf_busy_cycles,
    output reg        protocol_error,
    output reg        timeout_error,
    output reg        memory_error,

    // Optional 16-entry circular transaction trace. Record format:
    // {cycle[31:0], event[3:0], core[2:0], is_d, type[1:0],
    //  state[3:0], l2_hit, dirty, sharers[3:0], reserved[11:0], addr[31:0]}.
    input  wire [3:0]  debug_trace_rd_index,
    output wire [95:0] debug_trace_rd_data,
    output wire [4:0]  debug_trace_count,
    output wire [3:0]  debug_trace_write_index,
    output wire [3:0]  debug_controller_state,

    // ---- L2 command/status interface ----
    // Used when EXTERNAL_L2=1.  Command is controller -> L2; response
    // is L2 -> controller.  Keeping data and policy on opposite sides
    // of this boundary makes the adviser's "MMU beside L2" structure
    // explicit without duplicating cache arrays in the controller.
    output wire         l2_cmd_valid_o,
    output wire         l2_cmd_we_o,
    output wire [31:0]  l2_cmd_addr_o,
    output wire [1:0]   l2_cmd_way_o,
    output wire [255:0] l2_cmd_wdata_o,
    output wire         l2_cmd_w_valid_o,
    output wire         l2_cmd_w_dirty_o,
    output wire [3:0]   l2_cmd_w_sharers_o,
    input  wire         l2_resp_valid_i,
    input  wire         l2_resp_hit_i,
    input  wire [1:0]   l2_resp_way_i,
    input  wire [14:0]  l2_resp_victim_tag_i,
    input  wire         l2_resp_victim_valid_i,
    input  wire         l2_resp_victim_dirty_i,
    input  wire [3:0]   l2_resp_victim_sharers_i,
    input  wire [255:0] l2_resp_line_i,
    input  wire [3:0]   l2_resp_sharers_i
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
    reg         dresp_error_r [0:3];
    reg [255:0] dresp_line_r  [0:3];
    reg [1:0]   dresp_state_r [0:3];
    reg         iresp_valid_r [0:3];
    reg         iresp_error_r [0:3];
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
    wire [3:0] dsnoop_ack_valid_vec = {dsnoop_ack_valid[3], dsnoop_ack_valid[2],
                                       dsnoop_ack_valid[1], dsnoop_ack_valid[0]};

    assign c0_dresp_valid=dresp_valid_r[0]; assign c0_dresp_error=dresp_error_r[0]; assign c0_dresp_line=dresp_line_r[0]; assign c0_dresp_state=dresp_state_r[0];
    assign c1_dresp_valid=dresp_valid_r[1]; assign c1_dresp_error=dresp_error_r[1]; assign c1_dresp_line=dresp_line_r[1]; assign c1_dresp_state=dresp_state_r[1];
    assign c2_dresp_valid=dresp_valid_r[2]; assign c2_dresp_error=dresp_error_r[2]; assign c2_dresp_line=dresp_line_r[2]; assign c2_dresp_state=dresp_state_r[2];
    assign c3_dresp_valid=dresp_valid_r[3]; assign c3_dresp_error=dresp_error_r[3]; assign c3_dresp_line=dresp_line_r[3]; assign c3_dresp_state=dresp_state_r[3];

    assign c0_iresp_valid=iresp_valid_r[0]; assign c0_iresp_error=iresp_error_r[0]; assign c0_iresp_line=iresp_line_r[0];
    assign c1_iresp_valid=iresp_valid_r[1]; assign c1_iresp_error=iresp_error_r[1]; assign c1_iresp_line=iresp_line_r[1];
    assign c2_iresp_valid=iresp_valid_r[2]; assign c2_iresp_error=iresp_error_r[2]; assign c2_iresp_line=iresp_line_r[2];
    assign c3_iresp_valid=iresp_valid_r[3]; assign c3_iresp_error=iresp_error_r[3]; assign c3_iresp_line=iresp_line_r[3];

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
    wire [14:0]  l2_resp_victim_tag;
    wire         l2_resp_victim_valid;
    wire         l2_resp_victim_dirty;
    wire [3:0]   l2_resp_victim_sharers;
    wire [255:0] l2_resp_line;
    wire [3:0]   l2_resp_sharers;

    wire         int_l2_resp_valid;
    wire         int_l2_resp_hit;
    wire [1:0]   int_l2_resp_way;
    wire [14:0]  int_l2_resp_victim_tag;
    wire         int_l2_resp_victim_valid;
    wire         int_l2_resp_victim_dirty;
    wire [3:0]   int_l2_resp_victim_sharers;
    wire [255:0] int_l2_resp_line;
    wire [3:0]   int_l2_resp_sharers;

    generate
        if (!EXTERNAL_L2) begin : g_internal_l2
            l2_cache u_l2 (
                .clk(clk), .rst(rst),
                .cmd_valid(l2_cmd_valid), .cmd_we(l2_cmd_we), .cmd_addr(l2_cmd_addr), .cmd_way(l2_cmd_way),
                .cmd_wdata(l2_cmd_wdata), .cmd_w_valid(l2_cmd_w_valid), .cmd_w_dirty(l2_cmd_w_dirty), .cmd_w_sharers(l2_cmd_w_sharers),
                .resp_valid(int_l2_resp_valid), .resp_hit(int_l2_resp_hit), .resp_way(int_l2_resp_way),
                .resp_victim_tag(int_l2_resp_victim_tag), .resp_victim_valid(int_l2_resp_victim_valid),
                .resp_victim_dirty(int_l2_resp_victim_dirty), .resp_victim_sharers(int_l2_resp_victim_sharers),
                .resp_line(int_l2_resp_line), .resp_sharers(int_l2_resp_sharers)
            );
        end
    endgenerate

    assign l2_resp_valid           = EXTERNAL_L2 ? l2_resp_valid_i           : int_l2_resp_valid;
    assign l2_resp_hit             = EXTERNAL_L2 ? l2_resp_hit_i             : int_l2_resp_hit;
    assign l2_resp_way             = EXTERNAL_L2 ? l2_resp_way_i             : int_l2_resp_way;
    assign l2_resp_victim_tag      = EXTERNAL_L2 ? l2_resp_victim_tag_i      : int_l2_resp_victim_tag;
    assign l2_resp_victim_valid    = EXTERNAL_L2 ? l2_resp_victim_valid_i    : int_l2_resp_victim_valid;
    assign l2_resp_victim_dirty    = EXTERNAL_L2 ? l2_resp_victim_dirty_i    : int_l2_resp_victim_dirty;
    assign l2_resp_victim_sharers  = EXTERNAL_L2 ? l2_resp_victim_sharers_i  : int_l2_resp_victim_sharers;
    assign l2_resp_line            = EXTERNAL_L2 ? l2_resp_line_i            : int_l2_resp_line;
    assign l2_resp_sharers         = EXTERNAL_L2 ? l2_resp_sharers_i         : int_l2_resp_sharers;

    assign l2_cmd_valid_o      = l2_cmd_valid;
    assign l2_cmd_we_o         = l2_cmd_we;
    assign l2_cmd_addr_o       = l2_cmd_addr;
    assign l2_cmd_way_o        = l2_cmd_way;
    assign l2_cmd_wdata_o      = l2_cmd_wdata;
    assign l2_cmd_w_valid_o    = l2_cmd_w_valid;
    assign l2_cmd_w_dirty_o    = l2_cmd_w_dirty;
    assign l2_cmd_w_sharers_o  = l2_cmd_w_sharers;

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
        S_WB_UPDATE_L2      = 4'd12,
        S_WAIT_REQ_DROP     = 4'd13,
        S_ERROR_RESTORE_L2  = 4'd14,
        S_UNCACHED_MEM      = 4'd15;

    reg [3:0] state;
    reg [3:0] watchdog_state;
    reg [31:0] watchdog_cycles;

    // ---- Latched transaction context ----
    reg [2:0]   req_core;      // 0-3 = D$ of that core, 4-7 = I$ of core (req_core-4)
    reg         req_is_d;
    reg [1:0]   req_type;      // dreq_type, valid only when req_is_d
    reg [31:0]  req_addr;      // line-aligned except exact byte address for UNCACHED
    reg [255:0] req_wr_line;   // WRITEBACK line or UNCACHED metadata/payload

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
    // One request pulse is emitted per external-memory word, then the
    // FSM waits for mem_valid before advancing to the next word.
    reg         mem_waiting;
    reg         victim_valid;
    reg         transaction_error;
    reg         recovery_dirty;

    integer i;

    // ---- Starvation-free round-robin arbiter (combinational) ----
    // Source encoding remains 0..3=D$0..D$3, 4..7=I$0..I$3 so
    // req_core[2] still selects instruction versus data.  rr_next
    // advances only when S_IDLE actually accepts a request.
    reg        arb_valid;
    reg [2:0]  arb_core;
    reg [2:0]  rr_next;
    reg [2:0]  arb_candidate;
    reg [7:0]  arb_requests;
    integer    arb_offset;
    always @(*) begin
        arb_requests = {ireq_valid[3], ireq_valid[2], ireq_valid[1], ireq_valid[0],
                        dreq_valid[3], dreq_valid[2], dreq_valid[1], dreq_valid[0]};
        arb_valid     = 1'b0;
        arb_core      = rr_next;
        arb_candidate = rr_next;
        for (arb_offset = 0; arb_offset < 8; arb_offset = arb_offset + 1) begin
            arb_candidate = rr_next + arb_offset[2:0];
            if (!arb_valid && arb_requests[arb_candidate]) begin
                arb_valid = 1'b1;
                arb_core  = arb_candidate;
            end
        end
    end

    // Event codes: 0=request accepted, 1=L2 hit, 2=L2 miss,
    // 3=snoop issued, 4=response returned, 5=external-memory error.
    reg [31:0] trace_cycle;
    reg        trace_event_valid;
    reg [95:0] trace_event_data;
    reg [31:0] trace_event_addr;
    reg [1:0]  trace_event_type;
    always @(*) begin
        trace_event_valid = 1'b0;
        trace_event_addr  = req_addr;
        trace_event_type  = req_type;
        trace_event_data  = 96'b0;

        if ((state == S_IDLE) && arb_valid) begin
            trace_event_valid = 1'b1;
            trace_event_addr  = arb_core[2] ? ireq_addr[arb_core[1:0]]
                                             : dreq_addr[arb_core[1:0]];
            trace_event_type  = arb_core[2] ? 2'b00 : dreq_type[arb_core[1:0]];
            trace_event_data  = {trace_cycle, 4'd0, arb_core, ~arb_core[2],
                                 trace_event_type, state, 1'b0, 1'b0, 4'b0,
                                 12'b0, trace_event_addr};
        end
        else if ((state == S_L2_LOOKUP_WAIT) && l2_resp_valid) begin
            trace_event_valid = 1'b1;
            trace_event_data  = {trace_cycle, l2_resp_hit ? 4'd1 : 4'd2,
                                 req_core, req_is_d, req_type, state,
                                 l2_resp_hit, l2_resp_victim_dirty,
                                 l2_resp_sharers, 12'b0, req_addr};
        end
        else if (((state == S_EVICT_SNOOP_ISSUE) ||
                  (state == S_SHARER_SNOOP_ISSUE)) && (snoop_todo != 4'b0)) begin
            trace_event_valid = 1'b1;
            trace_event_data  = {trace_cycle, 4'd3, req_core, req_is_d,
                                 req_type, state, 1'b0, line_dirty,
                                 line_sharers, 12'b0, snoop_addr_send};
        end
        else if (((state == S_EVICT_WB_MEM) || (state == S_FETCH_MEM) ||
                  (state == S_UNCACHED_MEM)) &&
                 mem_valid && mem_error) begin
            trace_event_valid = 1'b1;
            trace_event_data  = {trace_cycle, 4'd5, req_core, req_is_d,
                                 req_type, state, 1'b0, line_dirty,
                                 line_sharers, 12'b0, mem_addr};
        end
        else if (state == S_RESPOND) begin
            trace_event_valid = 1'b1;
            trace_event_data  = {trace_cycle, 4'd4, req_core, req_is_d,
                                 req_type, state, 1'b0, line_dirty,
                                 line_sharers, 12'b0, req_addr};
        end
    end

    assign debug_controller_state = state;

    generate
        if (DEBUG_TRACE_ENABLE) begin : GEN_CACHE_TRACE
            cache_debug_buffer #(
                .DEPTH(16), .ADDR_WIDTH(4), .DATA_WIDTH(96)
            ) u_cache_debug_buffer (
                .clk(clk), .rst(rst),
                .event_valid(trace_event_valid), .event_data(trace_event_data),
                .read_index(debug_trace_rd_index), .read_data(debug_trace_rd_data),
                .record_count(debug_trace_count), .write_index(debug_trace_write_index)
            );
        end
        else begin : GEN_NO_CACHE_TRACE
            assign debug_trace_rd_data     = 96'b0;
            assign debug_trace_count       = 5'b0;
            assign debug_trace_write_index = 4'b0;
        end
    endgenerate

    assign l2_cmd_valid = (state == S_L2_LOOKUP) || (state == S_L2_FILL) ||
                           (state == S_GRANT_WRITE_L2) || (state == S_WB_UPDATE_L2) ||
                           (state == S_ERROR_RESTORE_L2);
    assign l2_cmd_we    = (state != S_L2_LOOKUP);
    assign l2_cmd_addr  = (state == S_ERROR_RESTORE_L2) ? mem_line_addr : req_addr;
    assign l2_cmd_way   = line_way;
    assign l2_cmd_wdata = line_data;
    assign l2_cmd_w_valid  = (state == S_L2_FILL) || (state == S_GRANT_WRITE_L2) ||
                             (state == S_WB_UPDATE_L2) || (state == S_ERROR_RESTORE_L2);
    assign l2_cmd_w_dirty  = (state == S_ERROR_RESTORE_L2) ? recovery_dirty :
                              (state == S_WB_UPDATE_L2) ? 1'b1 :
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
    assign l2_cmd_w_sharers = (state == S_ERROR_RESTORE_L2) ? 4'b0 :
                               (state == S_L2_FILL)        ? 4'b0 :
                               (state == S_GRANT_WRITE_L2) ? grant_sharers :
                                                               line_sharers; // S_WB_UPDATE_L2: already resolved 1 full cycle earlier, safe to read directly

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            for (i = 0; i < 4; i = i + 1) begin
                dresp_valid_r[i]  <= 1'b0;
                dresp_error_r[i]  <= 1'b0;
                iresp_valid_r[i]  <= 1'b0;
                iresp_error_r[i]  <= 1'b0;
                dsnoop_valid_r[i] <= 1'b0;
            end
            mem_req_valid <= 1'b0;
            mem_we        <= 1'b0;
            mem_addr      <= 32'b0;
            mem_wdata     <= 32'b0;
            mem_wstrb     <= 4'b0;
            mem_word_idx  <= 3'd0;
            mem_line_addr <= 32'b0;
            mem_line_buf  <= {LINE_BITS{1'b0}};
            mem_waiting   <= 1'b0;
            victim_valid  <= 1'b0;
            transaction_error <= 1'b0;
            recovery_dirty <= 1'b0;
            req_core      <= 3'd0;
            req_is_d      <= 1'b0;
            req_type      <= 2'b00;
            req_addr      <= 32'b0;
            req_wr_line   <= {LINE_BITS{1'b0}};
            line_way      <= 2'b0;
            line_data     <= {LINE_BITS{1'b0}};
            line_sharers  <= 4'b0;
            line_dirty    <= 1'b0;
            snoop_todo    <= 4'b0;
            snoop_type_send <= 1'b0;
            snoop_addr_send <= 32'b0;
            snoop_after   <= S_IDLE;
            any_snoop_dirty <= 1'b0;
            snoop_dirty_data <= {LINE_BITS{1'b0}};
            rr_next          <= 3'd0;
            perf_total_requests <= 32'b0;
            perf_d_bus_reads    <= 32'b0;
            perf_d_rfos         <= 32'b0;
            perf_d_writebacks   <= 32'b0;
            perf_i_reads        <= 32'b0;
            perf_l2_hits        <= 32'b0;
            perf_l2_misses      <= 32'b0;
            perf_snoop_requests <= 32'b0;
            perf_mem_read_words <= 32'b0;
            perf_mem_write_words<= 32'b0;
            perf_busy_cycles    <= 32'b0;
            protocol_error      <= 1'b0;
            timeout_error       <= 1'b0;
            memory_error        <= 1'b0;
            watchdog_state      <= S_IDLE;
            watchdog_cycles     <= 32'b0;
            trace_cycle         <= 32'b0;
        end
        else begin
            // Default: all pulses low unless explicitly set below.
            for (i = 0; i < 4; i = i + 1) begin
                dresp_valid_r[i]  <= 1'b0;
                dresp_error_r[i]  <= 1'b0;
                iresp_valid_r[i]  <= 1'b0;
                iresp_error_r[i]  <= 1'b0;
                dsnoop_valid_r[i] <= 1'b0;
            end
            mem_req_valid <= 1'b0;
            mem_wstrb     <= 4'b0;
            trace_cycle <= trace_cycle + 32'd1;

            if (PERF_COUNTER_ENABLE && (state != S_IDLE))
                perf_busy_cycles <= perf_busy_cycles + 32'd1;

            // Detect a bus/snoop/requester handshake that leaves one
            // FSM state without progress for too long.  The flag is
            // sticky for ILA/software diagnosis; the transaction is
            // deliberately not abandoned because doing so could break
            // MSI atomicity or discard dirty data.
            if (state != watchdog_state) begin
                watchdog_state  <= state;
                watchdog_cycles <= 32'b0;
            end
            else if (state == S_IDLE) begin
                watchdog_cycles <= 32'b0;
            end
            else if (!timeout_error) begin
                if (watchdog_cycles >= (WATCHDOG_LIMIT - 1)) begin
                    timeout_error  <= 1'b1;
                    protocol_error <= 1'b1;
                end
                else begin
                    watchdog_cycles <= watchdog_cycles + 32'd1;
                end
            end

            case (state)
                // ==================================================
                S_IDLE: begin
                    if (arb_valid) begin
                        req_core <= arb_core;
                        transaction_error <= 1'b0;
                        victim_valid      <= 1'b0;
                        recovery_dirty    <= 1'b0;
                        rr_next  <= arb_core + 3'd1;
                        if (PERF_COUNTER_ENABLE) begin
                            perf_total_requests <= perf_total_requests + 32'd1;
                            if (arb_core[2])
                                perf_i_reads <= perf_i_reads + 32'd1;
                            else begin
                                case (dreq_type[arb_core[1:0]])
                                    2'b00: perf_d_bus_reads  <= perf_d_bus_reads + 32'd1;
                                    2'b01: perf_d_rfos       <= perf_d_rfos + 32'd1;
                                    2'b10: perf_d_writebacks <= perf_d_writebacks + 32'd1;
                                    default: ;
                                endcase
                            end
                        end
                        if ((arb_core[2] && (ireq_addr[arb_core[1:0]][4:0] != 5'b0)) ||
                            (!arb_core[2] &&
                             (dreq_type[arb_core[1:0]] != 2'b11) &&
                             (dreq_addr[arb_core[1:0]][4:0] != 5'b0)))
                            protocol_error <= 1'b1;
                        req_is_d <= ~arb_core[2];
                        if (~arb_core[2]) begin
                            req_type    <= dreq_type[arb_core[1:0]];
                            req_addr    <= (dreq_type[arb_core[1:0]] == 2'b11) ?
                                           {dreq_addr[arb_core[1:0]][31:2], 2'b00} :
                                           {dreq_addr[arb_core[1:0]][31:5], 5'b0};
                            req_wr_line <= dreq_line[arb_core[1:0]];
                        end
                        else begin
                            req_type    <= 2'b00; // READ semantics for I$
                            req_addr    <= {ireq_addr[arb_core[1:0]][31:5], 5'b0};
                        end
                        mem_waiting <= 1'b0;
                        state <= (!arb_core[2] &&
                                  (dreq_type[arb_core[1:0]] == 2'b11)) ?
                                 S_UNCACHED_MEM : S_L2_LOOKUP;
                    end
                end

                // ==================================================
                S_L2_LOOKUP: state <= S_L2_LOOKUP_WAIT; // one cycle for l2_cache's registered response

                S_L2_LOOKUP_WAIT: begin
                    if (l2_resp_valid) begin
                        if (PERF_COUNTER_ENABLE) begin
                            if (l2_resp_hit)
                                perf_l2_hits <= perf_l2_hits + 32'd1;
                            else
                                perf_l2_misses <= perf_l2_misses + 32'd1;
                        end
                        line_way <= l2_resp_way;

                        if (req_is_d && (req_type == 2'b10)) begin
                            // WRITEBACK: by the inclusion property this
                            // always hits (see header). Just update L2.
                            line_data    <= req_wr_line;
                            line_sharers <= l2_resp_sharers & ~(4'b0001 << req_core[1:0]);
                            if (!l2_resp_hit)
                                protocol_error <= 1'b1;
                            state        <= S_WB_UPDATE_L2;
                        end
                        else if (l2_resp_hit) begin
                            line_data    <= l2_resp_line;
                            line_sharers <= l2_resp_sharers;
                            // resp_victim_dirty describes the selected
                            // way on both hit and miss. Preserve it: L2
                            // may already be newer than DRAM after an
                            // earlier M->S downgrade/writeback.
                            line_dirty   <= l2_resp_victim_dirty;
                            victim_valid <= l2_resp_victim_valid;
                            any_snoop_dirty  <= 1'b0;
                            snoop_dirty_data <= {LINE_BITS{1'b0}};

                            if (!req_is_d) begin
                                // I$: no coherence involvement at all.
                                state <= S_RESPOND;
                            end
                            else begin
                                snoop_todo <= (l2_resp_sharers & ~(4'b0001 << req_core[1:0]));
                                snoop_type_send <= (req_type == 2'b00) ? 1'b1 : 1'b0; // READ->DOWNGRADE, RFO->INVALIDATE
                                snoop_addr_send <= req_addr;
                                snoop_after <= S_GRANT_WRITE_L2;
                                state <= S_SHARER_SNOOP_ISSUE;
                            end
                        end
                        else begin
                            // Miss in L2: may need to evict the victim way first.
                            line_data    <= l2_resp_line;      // victim's current data (for its own writeback, if needed)
                            line_sharers <= l2_resp_victim_sharers;
                            line_dirty   <= l2_resp_victim_dirty;
                            victim_valid <= l2_resp_victim_valid;
                            any_snoop_dirty  <= 1'b0;
                            snoop_dirty_data <= {LINE_BITS{1'b0}};
                            // L2 is inclusive: evicting a directory
                            // entry must snoop the VICTIM address, not
                            // the newly requested address.
                            snoop_addr_send <= {l2_resp_victim_tag, req_addr[16:5], 5'b0};
                            mem_line_addr   <= {l2_resp_victim_tag, req_addr[16:5], 5'b0};
                            mem_word_idx    <= 3'd0;
                            mem_waiting     <= 1'b0;

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
                                mem_word_idx <= 3'd0;
                                mem_waiting  <= 1'b0;
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
                    if (snoop_todo == 4'b0) begin
                        state <= snoop_after;
                    end
                    else begin
                        if (PERF_COUNTER_ENABLE)
                            perf_snoop_requests <= perf_snoop_requests + 32'd1;
                        // issue to the lowest set bit
                        if (snoop_todo[0]) begin dsnoop_valid_r[0] <= 1'b1; dsnoop_type_r[0] <= snoop_type_send; dsnoop_addr_r[0] <= snoop_addr_send; end
                        else if (snoop_todo[1]) begin dsnoop_valid_r[1] <= 1'b1; dsnoop_type_r[1] <= snoop_type_send; dsnoop_addr_r[1] <= snoop_addr_send; end
                        else if (snoop_todo[2]) begin dsnoop_valid_r[2] <= 1'b1; dsnoop_type_r[2] <= snoop_type_send; dsnoop_addr_r[2] <= snoop_addr_send; end
                        else if (snoop_todo[3]) begin dsnoop_valid_r[3] <= 1'b1; dsnoop_type_r[3] <= snoop_type_send; dsnoop_addr_r[3] <= snoop_addr_send; end
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
                        if ((dsnoop_ack_valid_vec & (dsnoop_ack_valid_vec - 4'b0001)) != 4'b0)
                            protocol_error <= 1'b1;
                        if (any_snoop_dirty &&
                            ((dsnoop_ack_valid[0] && dsnoop_ack_dirty[0]) ||
                             (dsnoop_ack_valid[1] && dsnoop_ack_dirty[1]) ||
                             (dsnoop_ack_valid[2] && dsnoop_ack_dirty[2]) ||
                             (dsnoop_ack_valid[3] && dsnoop_ack_dirty[3])))
                            protocol_error <= 1'b1;
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
                        mem_word_idx <= 3'd0;
                        mem_waiting  <= 1'b0;
                        state <= S_FETCH_MEM;
                    end
                    else if (!mem_waiting) begin
                        mem_req_valid <= 1'b1;
                        mem_we        <= 1'b1;
                        mem_addr      <= mem_line_addr + (mem_word_idx << 2);
                        mem_wdata     <= line_data[mem_word_idx*32 +: 32];
                        mem_wstrb     <= 4'b1111;
                        mem_waiting   <= 1'b1;
                        if (PERF_COUNTER_ENABLE)
                            perf_mem_write_words <= perf_mem_write_words + 32'd1;
                    end
                    else if (mem_valid) begin
                        mem_waiting <= 1'b0;
                        if (mem_error) begin
                            // Snoop invalidations may already have removed
                            // every other copy. Preserve the authoritative
                            // victim in L2 as dirty before failing the
                            // original requester; never discard partial WB.
                            memory_error      <= 1'b1;
                            transaction_error <= 1'b1;
                            recovery_dirty    <= 1'b1;
                            state             <= S_ERROR_RESTORE_L2;
                        end
                        else if (mem_word_idx == 3'd7) begin
                            mem_word_idx  <= 3'd0;
                            state         <= S_FETCH_MEM;
                        end
                        else begin
                            mem_word_idx  <= mem_word_idx + 3'd1;
                        end
                    end
                end

                S_FETCH_MEM: begin
                    if (!mem_waiting) begin
                        mem_req_valid <= 1'b1;
                        mem_we        <= 1'b0;
                        mem_addr      <= req_addr + (mem_word_idx << 2);
                        mem_wstrb     <= 4'b0000;
                        mem_waiting   <= 1'b1;
                        if (PERF_COUNTER_ENABLE)
                            perf_mem_read_words <= perf_mem_read_words + 32'd1;
                    end
                    else if (mem_valid) begin
                        mem_waiting <= 1'b0;
                        if (mem_error) begin
                            // A failed fill is never installed. If this miss
                            // selected a valid victim, restore that victim in
                            // L2 with no sharers; a completed victim WB makes
                            // it clean, otherwise the WB-error path above
                            // restores it dirty directly.
                            memory_error      <= 1'b1;
                            transaction_error <= 1'b1;
                            recovery_dirty    <= 1'b0;
                            state             <= victim_valid ? S_ERROR_RESTORE_L2 : S_RESPOND;
                        end
                        else begin
                            mem_line_buf[mem_word_idx*32 +: 32] <= mem_rdata;
                            if (mem_word_idx == 3'd7) begin
                                mem_word_idx  <= 3'd0;
                                line_data     <= { mem_rdata, mem_line_buf[223:0] }; // fold in the final word
                                line_dirty    <= 1'b0;
                                state         <= S_L2_FILL;
                            end
                            else begin
                                mem_word_idx  <= mem_word_idx + 3'd1;
                            end
                        end
                    end
                end

                // ==================================================
                // Strongly ordered, single-word MMIO access.  Request
                // metadata is packed by l1_dcache as:
                //   [36] write, [35:32] WSTRB, [31:0] shifted WDATA.
                // This path deliberately bypasses L2 and the MSI directory,
                // so a side-effecting peripheral read is issued exactly once
                // and no device response can later be satisfied from cache.
                S_UNCACHED_MEM: begin
                    if (!mem_waiting) begin
                        mem_req_valid <= 1'b1;
                        mem_we        <= req_wr_line[36];
                        mem_addr      <= req_addr;
                        mem_wdata     <= req_wr_line[31:0];
                        mem_wstrb     <= req_wr_line[36] ?
                                         req_wr_line[35:32] : 4'b0000;
                        mem_waiting   <= 1'b1;
                        if (PERF_COUNTER_ENABLE) begin
                            if (req_wr_line[36])
                                perf_mem_write_words <= perf_mem_write_words + 32'd1;
                            else
                                perf_mem_read_words <= perf_mem_read_words + 32'd1;
                        end
                    end
                    else if (mem_valid) begin
                        mem_waiting      <= 1'b0;
                        transaction_error <= mem_error;
                        if (mem_error)
                            memory_error <= 1'b1;
                        line_data <= {{(LINE_BITS-32){1'b0}}, mem_rdata};
                        state <= S_RESPOND;
                    end
                end

                S_L2_FILL: begin
                    // line_data/line_way already set; sharers start
                    // empty, dirty=0 (clean copy straight from DRAM).
                    line_sharers <= 4'b0;
                    line_dirty   <= 1'b0;
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

                // Rewrite the selected victim way under its original tag
                // after an external-memory failure. This state is the data-
                // preservation barrier before the failed requester is acked.
                S_ERROR_RESTORE_L2: state <= S_RESPOND;

                // ==================================================
                S_RESPOND: begin
                    if (req_is_d) begin
                        dresp_valid_r[req_core[1:0]] <= 1'b1;
                        dresp_error_r[req_core[1:0]] <= transaction_error;
                        dresp_line_r[req_core[1:0]]  <= line_data;
                        dresp_state_r[req_core[1:0]] <=
                            (req_type == 2'b10) ? 2'b00 :          // WRITEBACK ack, state field unused
                            (req_type == 2'b01) ? 2'b11 :          // RFO -> M
                                                  2'b01;           // every MSI read fill -> S
                    end
                    else begin
                        iresp_valid_r[req_core[1:0]] <= 1'b1;
                        iresp_error_r[req_core[1:0]] <= transaction_error;
                        iresp_line_r[req_core[1:0]]  <= line_data;
                    end
                    // Requesters hold valid until they observe this
                    // response. Waiting for deassertion prevents the
                    // just-completed level request being accepted again
                    // on the following edge.
                    state <= S_WAIT_REQ_DROP;
                end

                S_WAIT_REQ_DROP: begin
                    if (req_is_d) begin
                        if (!dreq_valid[req_core[1:0]]) state <= S_IDLE;
                    end
                    else begin
                        if (!ireq_valid[req_core[1:0]]) state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

// ============================================================
// Backward-compatible integrated facade.
//
// Existing unit tests and legacy integrations instantiate
// coherence_manager expecting it to own L2.  Keep that interface
// unchanged while the active SoC uses cache_controller_mmu and a peer
// L2.  The compatibility layer is intentionally policy-free.
// ============================================================
module coherence_manager #(
    parameter LINE_WORDS = 8,
    parameter PERF_COUNTER_ENABLE = 1,
    parameter DEBUG_TRACE_ENABLE = 0,
    parameter integer WATCHDOG_LIMIT = 1024
)(
    input  wire clk,
    input  wire rst,

    input  wire         c0_dreq_valid, input wire [1:0] c0_dreq_type, input wire [31:0] c0_dreq_addr, input wire [255:0] c0_dreq_line,
    output wire         c0_dresp_valid, output wire c0_dresp_error, output wire [255:0] c0_dresp_line, output wire [1:0] c0_dresp_state,
    output wire         c0_dsnoop_valid, output wire c0_dsnoop_type, output wire [31:0] c0_dsnoop_addr,
    input  wire         c0_dsnoop_ack_valid, input wire c0_dsnoop_ack_hit, input wire c0_dsnoop_ack_dirty, input wire [255:0] c0_dsnoop_ack_line,
    input  wire         c0_ireq_valid, input wire [31:0] c0_ireq_addr,
    output wire         c0_iresp_valid, output wire c0_iresp_error, output wire [255:0] c0_iresp_line,

    input  wire         c1_dreq_valid, input wire [1:0] c1_dreq_type, input wire [31:0] c1_dreq_addr, input wire [255:0] c1_dreq_line,
    output wire         c1_dresp_valid, output wire c1_dresp_error, output wire [255:0] c1_dresp_line, output wire [1:0] c1_dresp_state,
    output wire         c1_dsnoop_valid, output wire c1_dsnoop_type, output wire [31:0] c1_dsnoop_addr,
    input  wire         c1_dsnoop_ack_valid, input wire c1_dsnoop_ack_hit, input wire c1_dsnoop_ack_dirty, input wire [255:0] c1_dsnoop_ack_line,
    input  wire         c1_ireq_valid, input wire [31:0] c1_ireq_addr,
    output wire         c1_iresp_valid, output wire c1_iresp_error, output wire [255:0] c1_iresp_line,

    input  wire         c2_dreq_valid, input wire [1:0] c2_dreq_type, input wire [31:0] c2_dreq_addr, input wire [255:0] c2_dreq_line,
    output wire         c2_dresp_valid, output wire c2_dresp_error, output wire [255:0] c2_dresp_line, output wire [1:0] c2_dresp_state,
    output wire         c2_dsnoop_valid, output wire c2_dsnoop_type, output wire [31:0] c2_dsnoop_addr,
    input  wire         c2_dsnoop_ack_valid, input wire c2_dsnoop_ack_hit, input wire c2_dsnoop_ack_dirty, input wire [255:0] c2_dsnoop_ack_line,
    input  wire         c2_ireq_valid, input wire [31:0] c2_ireq_addr,
    output wire         c2_iresp_valid, output wire c2_iresp_error, output wire [255:0] c2_iresp_line,

    input  wire         c3_dreq_valid, input wire [1:0] c3_dreq_type, input wire [31:0] c3_dreq_addr, input wire [255:0] c3_dreq_line,
    output wire         c3_dresp_valid, output wire c3_dresp_error, output wire [255:0] c3_dresp_line, output wire [1:0] c3_dresp_state,
    output wire         c3_dsnoop_valid, output wire c3_dsnoop_type, output wire [31:0] c3_dsnoop_addr,
    input  wire         c3_dsnoop_ack_valid, input wire c3_dsnoop_ack_hit, input wire c3_dsnoop_ack_dirty, input wire [255:0] c3_dsnoop_ack_line,
    input  wire         c3_ireq_valid, input wire [31:0] c3_ireq_addr,
    output wire         c3_iresp_valid, output wire c3_iresp_error, output wire [255:0] c3_iresp_line,

    output wire         mem_req_valid,
    output wire         mem_we,
    output wire [31:0]  mem_addr,
    output wire [31:0]  mem_wdata,
    output wire [3:0]   mem_wstrb,
    input  wire [31:0]  mem_rdata,
    input  wire         mem_valid,
    input  wire         mem_error,

    output wire [31:0] perf_total_requests,
    output wire [31:0] perf_d_bus_reads,
    output wire [31:0] perf_d_rfos,
    output wire [31:0] perf_d_writebacks,
    output wire [31:0] perf_i_reads,
    output wire [31:0] perf_l2_hits,
    output wire [31:0] perf_l2_misses,
    output wire [31:0] perf_snoop_requests,
    output wire [31:0] perf_mem_read_words,
    output wire [31:0] perf_mem_write_words,
    output wire [31:0] perf_busy_cycles,
    output wire        protocol_error,
    output wire        timeout_error,
    output wire        memory_error,

    input  wire [3:0]  debug_trace_rd_index,
    output wire [95:0] debug_trace_rd_data,
    output wire [4:0]  debug_trace_count,
    output wire [3:0]  debug_trace_write_index,
    output wire [3:0]  debug_controller_state
);

    coherence_manager_engine #(
        .LINE_WORDS(LINE_WORDS),
        .PERF_COUNTER_ENABLE(PERF_COUNTER_ENABLE),
        .DEBUG_TRACE_ENABLE(DEBUG_TRACE_ENABLE),
        .WATCHDOG_LIMIT(WATCHDOG_LIMIT),
        .EXTERNAL_L2(0)
    ) u_engine (
        .l2_cmd_valid_o(), .l2_cmd_we_o(), .l2_cmd_addr_o(),
        .l2_cmd_way_o(), .l2_cmd_wdata_o(), .l2_cmd_w_valid_o(),
        .l2_cmd_w_dirty_o(), .l2_cmd_w_sharers_o(),
        .l2_resp_valid_i(1'b0), .l2_resp_hit_i(1'b0),
        .l2_resp_way_i(2'b0), .l2_resp_victim_tag_i(15'b0),
        .l2_resp_victim_valid_i(1'b0), .l2_resp_victim_dirty_i(1'b0),
        .l2_resp_victim_sharers_i(4'b0), .l2_resp_line_i(256'b0),
        .l2_resp_sharers_i(4'b0),
        .*
    );

endmodule
