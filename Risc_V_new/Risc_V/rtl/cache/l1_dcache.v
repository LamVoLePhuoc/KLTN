`timescale 1ns / 1ps

// ============================================================
// l1_dcache
//
// Private, per-core L1 data cache. PIPT, MSI. Sized per the FINAL
// architecture decision (Risc_V_new/README.md mục 4 -- 32KB D$
// separate from 32KB I$, not address_mapping's earlier "16KB shared"
// placeholder number):
//   32KB, 2-way set-associative, line = 32B (8 words)
//   offset = 5b, index = 9b (512 sets), tag = 18b
//
// Write-back, write-allocate, blocking (single outstanding request
// -- matches the core, which has no mechanism for more than one
// in-flight memory access at a time).
//
// Coherence: participates in the system's MSI protocol via a
// request port (to coherence_manager.v, for misses/upgrades/
// evictions) and a snoop port (from coherence_manager.v, for other
// cores' requests that need this cache to invalidate or downgrade).
// State per line: 2'b00=I, 2'b01=S, 2'b11=M. 2'b10 is deliberately
// unused so an old MESI Exclusive value cannot silently become a
// writable line after the protocol conversion.
//
// bus_req_type: 2'b00=READ (want S), 2'b01=RFO (want M,
// read-for-ownership/upgrade), 2'b10=WRITEBACK (voluntary eviction
// of a dirty line, no response data expected beyond the ack pulse),
// 2'b11=UNCACHED.  UNCACHED is one word and never allocates a line;
// bus_req_addr keeps the byte address while bus_req_line carries
// {write-enable, byte-strobe, shifted-write-data} in bits [36:0].
// snoop_type: 1'b0=INVALIDATE, 1'b1=DOWNGRADE (M -> S).
//
// IMPORTANT correctness note (local hit vs. snoop race):
// coherence_manager.v's transactions are atomic/serialized system-
// wide (see its header), which removes races BETWEEN cores' bus
// transactions -- but it does NOT remove the race between THIS
// core's own local hit (which never touches the bus/arbiter at all,
// by design, so it isn't serialized against anything) and an
// incoming snoop for the exact same line, issued because some OTHER
// core's transaction is being serviced right now. Concretely: core X
// holds line A Modified; core Y requests line A; the coherence
// manager snoops X to downgrade A -- meanwhile X's own pipeline may,
// on that very cycle, also be doing a plain write-hit on A. Both
// would try to update this module's metadata state for the same line on
// the same clock edge from what would otherwise be two independent
// paths. Resolved below by `snoop_conflict`: whenever an incoming
// snoop targets the exact line the core's own access is hitting on
// this cycle, the snoop wins and the core's own access is forced
// back to "not ready" (retried next cycle, by which point the snoop
// has resolved and the core's normal hit/upgrade-miss logic handles
// it correctly with no special-casing needed).
//
// Silent clean eviction: a victim way holding a clean S line
// for a different tag is simply dropped, with no WRITEBACK and no
// notice to the coherence manager. This can leave the directory
// "optimistically stale" (still listing this core as a sharer of a
// line it no longer has), which is safe, not a correctness bug: the
// only consequence is a future spurious snoop for that line, which
// this cache correctly acks as a clean miss (snoop_ack_hit=0) -- see
// coherence_manager.v, which uses that to prune the stale entry.
// Only a dirty (Modified) victim needs an explicit WRITEBACK, since
// only Modified data can be lost.
// ============================================================
module l1_dcache #(
    parameter INDEX_BITS  = 9,     // 512 sets (32KB, 2-way, 32B line)
    parameter LINE_WORDS  = 8,     // 32B line = 8 x 32-bit words
    // Physical 0xC000_0000..0xFFFF_FFFF is the MMIO/reserved region
    // selected by mmu_region_decode.v.  Keep the decode parameterized
    // so a board integration can move the device window coherently.
    parameter [31:0] UNCACHED_BASE = 32'hC000_0000,
    parameter [31:0] UNCACHED_MASK = 32'hC000_0000
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         flush,      // pulse: write back M lines, then invalidate the whole cache
    output wire         flush_busy,
    output reg          flush_done, // one-cycle pulse after the final set/way is clean and invalid

    // ---- Core side (matches mmu_core_wrapper's Mem_* shape) ----
    input  wire [31:0]  cpu_addr,
    input  wire [31:0]  cpu_wdata,
    input  wire         cpu_we,
    input  wire         cpu_re,
    input  wire [2:0]   cpu_memop,     // funct3 (SB/SH/SW, LB/LH/LW/LBU/LHU) -- see store_unit.v/load_unit.v
    input  wire         cpu_amo,       // AMO*.W RMW (LR/SC excluded)
    input  wire [4:0]   cpu_amo_op,
    input  wire [31:0]  cpu_amo_operand, // raw rs2, not a precomputed result
    output wire [31:0]  cpu_rdata,
    output wire         cpu_valid,     // 1 exactly when this access has completed (hit this cycle, or miss just resolved)
    output wire         cpu_error,     // asserted with cpu_valid when the miss/RFO failed

    // ---- Bus side (request to coherence_manager.v) ----
    output reg                        bus_req_valid,
    input  wire                       bus_req_ready,
    output reg  [1:0]                 bus_req_type,
    output reg  [31:0]                bus_req_addr,   // line-aligned
    output reg  [LINE_WORDS*32-1:0]   bus_req_line,   // valid for WRITEBACK only
    input  wire                       bus_resp_valid,
    input  wire                       bus_resp_error,
    input  wire [LINE_WORDS*32-1:0]   bus_resp_line,
    input  wire [1:0]                 bus_resp_state, // granted MSI state (S/M) -- ignored for WRITEBACK acks

    // ---- Snoop side (from coherence_manager.v) ----
    input  wire         snoop_valid,
    input  wire         snoop_type,
    input  wire [31:0]  snoop_addr,
    output reg           snoop_ack_valid,
    output reg           snoop_ack_hit,
    output reg           snoop_ack_dirty,
    output reg  [LINE_WORDS*32-1:0] snoop_ack_line,

    // A maintenance writeback has no architectural load/store to which
    // an access fault can be attached. Abort safely, retain the dirty
    // line and report a pulse for sticky ILA diagnostics upstream.
    output reg           flush_error
);

    localparam WAYS         = 2;
    localparam OFFSET_BITS  = 5;
    localparam TAG_BITS     = 32 - INDEX_BITS - OFFSET_BITS;
    localparam SETS         = (1 << INDEX_BITS);
    localparam LINE_BITS    = LINE_WORDS * 32;
    localparam META_BITS    = TAG_BITS + 2;

    localparam [1:0] ST_I = 2'b00, ST_S = 2'b01, ST_M = 2'b11;
    localparam [1:0] REQ_READ = 2'b00, REQ_RFO = 2'b01,
                     REQ_WRITEBACK = 2'b10, REQ_UNCACHED = 2'b11;

    wire [TAG_BITS-1:0]   addr_tag   = cpu_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] addr_index = cpu_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    wire [2:0]            addr_word  = cpu_addr[4:2];
    wire                  uncached_access =
                          ((cpu_addr & UNCACHED_MASK) ==
                           (UNCACHED_BASE & UNCACHED_MASK));

    wire [TAG_BITS-1:0]   snoop_tag   = snoop_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] snoop_index = snoop_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];

    // ------------------------------------------------------
    // Storage
    // ------------------------------------------------------
    // Tag and MSI state are stored beside one another in the same two-port
    // synchronous memory as the line lookup.  The former asynchronous,
    // resettable, multi-write arrays expanded into thousands of muxes/FFs
    // per cache and dominated synthesis time.
    // One true-dual-port block RAM per way: port A serves the local core
    // (and all writes), port B serves snoops.  cache_tdp_data_ram uses the
    // official XPM memory macro during synthesis, avoiding a very expensive
    // ambiguous RAM-inference pass, and a matching behavioural model in
    // simulation. Dedicated block RAM has synchronous reads, so cpu_valid
    // remains low for the added hit-lookup cycle.
    reg                    lru_r   [0:SETS-1];
    reg                    init_active;
    reg [INDEX_BITS-1:0]   init_index;

    // ------------------------------------------------------
    // Core-side lookup (combinational): report a tag match
    // regardless of state (needed to tell "upgrade in place" from
    // "genuine miss needing a victim"), plus whether the access is
    // actually allowed by the current state.
    // ------------------------------------------------------
    reg                  tag_hit_v;
    reg                  tag_hit_way_v;
    reg [1:0]             tag_hit_state_v;
    reg [LINE_BITS-1:0]   tag_hit_line_v;

    wire [LINE_BITS-1:0] core_way0_line;
    wire [LINE_BITS-1:0] core_way1_line;
    wire [LINE_BITS-1:0] snoop_way0_line;
    wire [LINE_BITS-1:0] snoop_way1_line;
    wire [META_BITS-1:0] core_meta_way0;
    wire [META_BITS-1:0] core_meta_way1;
    wire [META_BITS-1:0] snoop_meta_way0;
    wire [META_BITS-1:0] snoop_meta_way1;
    reg [31:0]          core_lookup_addr;
    reg                 core_lookup_valid;
    reg [INDEX_BITS-1:0] core_data_index;
    reg                 lookup_decision_ready_q;
    reg                 lookup_access_ok_q;
    reg                 lookup_req_re_q;
    reg                 lookup_req_we_q;
    reg [31:0]          snoop_lookup_addr;
    reg                 snoop_lookup_valid;
    reg                 snoop_lookup_type;
    reg [31:0]          snoop_pipe_addr;
    reg                 snoop_pipe_valid;
    reg                 snoop_pipe_type;

    wire [TAG_BITS-1:0] lookup_tag = core_lookup_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] lookup_index =
        core_lookup_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    wire [2:0] lookup_word = core_lookup_addr[4:2];
    wire core_lookup_ready = core_lookup_valid &&
                             (core_lookup_addr == cpu_addr) &&
                             (core_data_index == lookup_index);

    always @(*) begin
        tag_hit_v       = 1'b0;
        tag_hit_way_v   = 1'b0;
        tag_hit_state_v = ST_I;
        tag_hit_line_v  = {LINE_BITS{1'b0}};
        if ((core_meta_way0[1:0] != ST_I) &&
            (core_meta_way0[META_BITS-1:2] == lookup_tag)) begin
            tag_hit_v       = 1'b1;
            tag_hit_way_v   = 1'b0;
            tag_hit_state_v = core_meta_way0[1:0];
            tag_hit_line_v  = core_way0_line;
        end
        if ((core_meta_way1[1:0] != ST_I) &&
            (core_meta_way1[META_BITS-1:2] == lookup_tag)) begin
            tag_hit_v       = 1'b1;
            tag_hit_way_v   = 1'b1;
            tag_hit_state_v = core_meta_way1[1:0];
            tag_hit_line_v  = core_way1_line;
        end
    end

    wire snoop_conflict_now = snoop_valid && (snoop_index == addr_index) &&
                              tag_hit_v && (snoop_tag == addr_tag);
    wire [TAG_BITS-1:0] snoop_lookup_tag =
        snoop_lookup_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] snoop_lookup_index =
        snoop_lookup_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    wire [TAG_BITS-1:0] snoop_pipe_tag =
        snoop_pipe_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] snoop_pipe_index =
        snoop_pipe_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    wire snoop_conflict_pipe = snoop_pipe_valid &&
        (snoop_pipe_index == addr_index) &&
        (snoop_pipe_tag == addr_tag);
    wire snoop_conflict_pending = snoop_lookup_valid &&
        (snoop_lookup_index == addr_index) && tag_hit_v &&
        (snoop_lookup_tag == addr_tag);
    wire snoop_conflict = snoop_conflict_now | snoop_conflict_pipe |
                          snoop_conflict_pending;

    // Forward declarations used by the read-data mux below; the
    // miss/AMO FSM owns both registers later in the module.
    reg miss_done_pulse;
    reg miss_error_pulse;
    reg hit_write_done_pulse;
    reg hit_read_done_pulse;
    reg fsm_amo;

    wire access_ok = tag_hit_v & ~snoop_conflict &
                      (cpu_we ? (tag_hit_state_v == ST_M)
                               : (tag_hit_state_v == ST_S || tag_hit_state_v == ST_M));

    // Data is registered in its final, architecturally formatted form before
    // cpu_valid is asserted.  In particular, live cpu_addr/cpu_memop signals
    // no longer form a combinational path from the dTLB through load
    // forwarding and back into a following store/uncached request.
    reg [31:0] cpu_response_data;
    assign cpu_rdata = cpu_response_data;

    // Reuse the architectural store formatter for the device path.  Its
    // inputs are registered below before formatting; this deliberately cuts
    // the former ALU_ResultM/store-unit -> 256-bit bus_req_line path.  Cached
    // stores still merge locally in merge_line(); only uncached stores expose
    // these byte enables to the external memory boundary.
    reg  [31:0] uncached_addr_q;
    reg  [31:0] uncached_store_data_q;
    reg  [2:0]  uncached_memop_q;
    wire [31:0] uncached_wdata;
    wire [3:0]  uncached_wstrb;
    store_unit u_uncached_store_unit (
        .store_data (uncached_store_data_q),
        .addr_offset(uncached_addr_q[1:0]),
        .mem_op     (uncached_memop_q),
        .axi_wdata  (uncached_wdata),
        .axi_wstrb  (uncached_wstrb)
    );

    // ------------------------------------------------------
    // Snoop response (independent of the core-side FSM below --
    // see header note on why this is always live, 1-cycle latency)
    // ------------------------------------------------------
    reg                 snoop_hit_v;
    reg                 snoop_hit_way_v;
    reg [1:0]            snoop_hit_state_v;
    reg [LINE_BITS-1:0]  snoop_hit_line_v;

    always @(*) begin
        snoop_hit_v       = 1'b0;
        snoop_hit_way_v   = 1'b0;
        snoop_hit_state_v = ST_I;
        snoop_hit_line_v  = {LINE_BITS{1'b0}};
        if ((snoop_meta_way0[1:0] != ST_I) &&
            (snoop_meta_way0[META_BITS-1:2] == snoop_lookup_tag)) begin
            snoop_hit_v       = 1'b1;
            snoop_hit_way_v   = 1'b0;
            snoop_hit_state_v = snoop_meta_way0[1:0];
            snoop_hit_line_v  = snoop_way0_line;
        end
        if ((snoop_meta_way1[1:0] != ST_I) &&
            (snoop_meta_way1[META_BITS-1:2] == snoop_lookup_tag)) begin
            snoop_hit_v       = 1'b1;
            snoop_hit_way_v   = 1'b1;
            snoop_hit_state_v = snoop_meta_way1[1:0];
            snoop_hit_line_v  = snoop_way1_line;
        end
    end

    // ------------------------------------------------------
    // Helper: merge a byte/half/word store into one word of a line
    // (function, not a module, so it can be used combinationally
    // inside the always block below -- Verilog-2001 allows this).
    // Declared before first use since not every tool accepts a
    // forward reference to a function within the same module.
    // ------------------------------------------------------
    function [LINE_BITS-1:0] merge_line;
        input [LINE_BITS-1:0] line_in;
        input [2:0]           word_idx;
        input [2:0]           memop;
        input [31:0]          wdata;
        input [1:0]           byte_off;
        reg   [31:0]          old_word;
        reg   [31:0]          new_word;
        reg   [31:0]          shifted;
        reg   [3:0]           wstrb;
        begin
            old_word = line_in[word_idx*32 +: 32];
            case (memop)
                3'b000: begin // SB
                    wstrb   = 4'b0001 << byte_off;
                    shifted = wdata << (8 * byte_off);
                end
                3'b001: begin // SH
                    if (byte_off[1] == 1'b0) begin
                        wstrb   = 4'b0011;
                        shifted = wdata;
                    end else begin
                        wstrb   = 4'b1100;
                        shifted = wdata << 16;
                    end
                end
                default: begin // SW
                    wstrb   = 4'b1111;
                    shifted = wdata;
                end
            endcase
            new_word = { wstrb[3] ? shifted[31:24] : old_word[31:24],
                         wstrb[2] ? shifted[23:16] : old_word[23:16],
                         wstrb[1] ? shifted[15:8]  : old_word[15:8],
                         wstrb[0] ? shifted[7:0]   : old_word[7:0] };
            merge_line = line_in;
            merge_line[word_idx*32 +: 32] = new_word;
        end
    endfunction

    function [31:0] amo_result;
        input [31:0] old_word;
        input [31:0] operand;
        input [4:0]  amo_op;
        begin
            case (amo_op)
                5'b00000: amo_result = old_word + operand; // AMOADD.W
                5'b00001: amo_result = operand;            // AMOSWAP.W
                5'b00100: amo_result = old_word ^ operand; // AMOXOR.W
                5'b01000: amo_result = old_word | operand; // AMOOR.W
                5'b01100: amo_result = old_word & operand; // AMOAND.W
                5'b10000: amo_result = ($signed(old_word) < $signed(operand)) ? old_word : operand; // AMOMIN.W
                5'b10100: amo_result = ($signed(old_word) > $signed(operand)) ? old_word : operand; // AMOMAX.W
                5'b11000: amo_result = (old_word < operand) ? old_word : operand; // AMOMINU.W
                5'b11100: amo_result = (old_word > operand) ? old_word : operand; // AMOMAXU.W
                default:  amo_result = operand;
            endcase
        end
    endfunction

    function [LINE_BITS-1:0] merge_amo_line;
        input [LINE_BITS-1:0] line_in;
        input [2:0]           word_idx;
        input [4:0]           amo_op;
        input [31:0]          operand;
        reg [31:0]            old_word;
        begin
            old_word = line_in[word_idx*32 +: 32];
            merge_amo_line = line_in;
            merge_amo_line[word_idx*32 +: 32] = amo_result(old_word, operand, amo_op);
        end
    endfunction

    function [31:0] format_load;
        input [31:0] raw_data;
        input [1:0]  byte_off;
        input [2:0]  memop;
        reg [7:0]    selected_byte;
        reg [15:0]   selected_half;
        begin
            case (byte_off)
                2'b00: selected_byte = raw_data[7:0];
                2'b01: selected_byte = raw_data[15:8];
                2'b10: selected_byte = raw_data[23:16];
                default: selected_byte = raw_data[31:24];
            endcase
            selected_half = byte_off[1] ? raw_data[31:16] : raw_data[15:0];
            case (memop)
                3'b000: format_load = {{24{selected_byte[7]}}, selected_byte};
                3'b001: format_load = {{16{selected_half[15]}}, selected_half};
                3'b010: format_load = raw_data;
                3'b100: format_load = {24'b0, selected_byte};
                3'b101: format_load = {16'b0, selected_half};
                default: format_load = raw_data;
            endcase
        end
    endfunction

    // ------------------------------------------------------
    // Core-side miss/eviction FSM
    // ------------------------------------------------------
    localparam [3:0] S_IDLE = 4'd0, S_EVICT = 4'd1,
                     S_MISS_REQ = 4'd2, S_AFTER_EVICT = 4'd3,
                     S_FLUSH_SCAN = 4'd4, S_FLUSH_WB = 4'd5,
                     S_FLUSH_GAP = 4'd6, S_UNCACHED_REQ = 4'd7,
                     S_CACHE_WRITE = 4'd8, S_HIT_MERGE = 4'd9,
                     S_HIT_READ = 4'd10, S_UNCACHED_PACK = 4'd11,
                     S_MISS_PREP = 4'd12, S_FLUSH_REQ_PACK = 4'd13,
                     S_POST_RESPONSE = 4'd14,
                     S_MISS_DISPATCH = 4'd15;
    reg [3:0] state;

    reg                   fsm_way;
    reg [INDEX_BITS-1:0]  fsm_index;
    reg [TAG_BITS-1:0]    fsm_tag;
    reg                   fsm_we;       // pending access was a write (needs RFO + local merge on fill)
    reg [2:0]             fsm_memop;
    reg [31:0]            fsm_wdata;
    reg [4:0]              fsm_word_off; // {word[2:0], byte[1:0]} of the pending access, for the post-fill merge
    reg [4:0]              fsm_amo_op;
    reg [31:0]             fsm_amo_operand;

    // Miss/eviction preparation stage.  The victim BRAM outputs are sampled
    // here before any 256-bit payload or victim tag drives the bus request
    // registers.  This is intentionally separate from the refill/commit
    // stages below: ordinary misses pay one fixed cycle, while hits are
    // unaffected.
    reg [LINE_BITS-1:0]    miss_victim_line_q;
    reg [TAG_BITS-1:0]     miss_victim_tag_q;
    reg [1:0]              miss_victim_state_q;
    reg                    miss_tag_hit_q;

    // Every data/tag mutation is committed from these registers.  The old
    // direct write-hit path ran from ALU_ResultM through the combinational
    // dTLB, hit/AMO/store merge logic and the XPM input mux to RAMB36 in one
    // cycle.  Apart from missing 100 MHz by more than 5 ns, that also made
    // placement extremely sensitive.  S_CACHE_WRITE deliberately adds one
    // blocking cycle and presents registered address/data/control to BRAM.
    reg [LINE_BITS-1:0]    cache_write_line;
    reg                    cache_write_way;
    reg [INDEX_BITS-1:0]   cache_write_set;
    reg [TAG_BITS-1:0]     cache_write_tag;
    reg [1:0]              cache_write_state;
    reg                    cache_write_from_hit;

    // Write hits use an additional register boundary before the byte/AMO
    // merge.  Both BRAM way outputs are captured independently so the
    // translated address and tag-hit mux cannot be folded back into the
    // cache_write_line D path.  The core is already held by the blocking
    // cache handshake, therefore the extra cycle changes latency only, not
    // architectural ordering or the external interface.
    reg [LINE_BITS-1:0]    hit_stage_way0_line;
    reg [LINE_BITS-1:0]    hit_stage_way1_line;
    reg                    hit_stage_way;
    reg [INDEX_BITS-1:0]   hit_stage_set;
    reg [TAG_BITS-1:0]     hit_stage_tag;
    reg [4:0]              hit_stage_word_off;
    reg [2:0]              hit_stage_memop;
    reg [31:0]             hit_stage_wdata;
    reg                    hit_stage_amo;
    reg [4:0]              hit_stage_amo_op;
    reg [31:0]             hit_stage_amo_operand;

    // A flush is deliberately a small blocking walker instead of a
    // one-cycle valid-bit clear.  Dropping an M line would lose the
    // only up-to-date copy in an MSI system.  The request is latched
    // so a pulse arriving during an ordinary miss/eviction is served
    // as soon as that transaction completes.
    reg                   flush_pending;
    reg                   flush_seen;
    reg [INDEX_BITS-1:0]  flush_set;
    reg                   flush_way;
    reg [LINE_BITS-1:0]   flush_wb_line_q;
    reg [TAG_BITS-1:0]    flush_wb_tag_q;

    assign flush_busy = init_active | flush | flush_pending |
                        (state == S_FLUSH_SCAN) |
                        (state == S_FLUSH_REQ_PACK) |
                        (state == S_FLUSH_WB) |
                        (state == S_FLUSH_GAP);

    wire [LINE_BITS-1:0] victim_line = lru_r[lookup_index] ?
                                      core_way1_line : core_way0_line;
    wire [META_BITS-1:0] victim_meta = lru_r[lookup_index] ?
                                      core_meta_way1 : core_meta_way0;
    wire [1:0] victim_state = victim_meta[1:0];
    wire [TAG_BITS-1:0] victim_tag = victim_meta[META_BITS-1:2];
    wire [LINE_BITS-1:0] flush_line = flush_way ?
                                      core_way1_line : core_way0_line;
    wire [META_BITS-1:0] flush_meta = flush_way ?
                                      core_meta_way1 : core_meta_way0;
    wire [1:0] flush_state = flush_meta[1:0];
    wire [TAG_BITS-1:0] flush_tag = flush_meta[META_BITS-1:2];
    wire [INDEX_BITS-1:0] core_read_index =
        ((state == S_FLUSH_SCAN) || (state == S_FLUSH_REQ_PACK) ||
         (state == S_FLUSH_WB) ||
         (state == S_FLUSH_GAP)) ? flush_set : addr_index;
    // A snoop for the line being committed wins.  Aborting the local commit
    // (without producing cpu_valid) makes the held CPU request retry after
    // the snoop, at which point it follows the normal miss/RFO path.  This
    // preserves the local-hit-vs-snoop ordering guarantee despite the new
    // pipeline cycle.
    wire cache_write_snoop_conflict_now = snoop_valid &&
        (snoop_index == cache_write_set) && (snoop_tag == cache_write_tag);
    wire cache_write_snoop_conflict_pending = snoop_lookup_valid &&
        (snoop_lookup_index == cache_write_set) &&
        (snoop_lookup_tag == cache_write_tag);
    wire cache_write_snoop_conflict_pipe = snoop_pipe_valid &&
        (snoop_pipe_index == cache_write_set) &&
        (snoop_pipe_tag == cache_write_tag);
    // A cache commit is infrequent and blocking.  Conservatively retry it
    // behind any snoop already in the three-stage pipe instead of putting
    // three wide tag comparators on the metadata BRAM write-enable path.
    wire cache_write_snoop_conflict = (state == S_CACHE_WRITE) &&
        (snoop_valid | snoop_pipe_valid | snoop_lookup_valid);
    wire hit_stage_snoop_conflict_now = snoop_valid &&
        (snoop_index == hit_stage_set) && (snoop_tag == hit_stage_tag);
    wire hit_stage_snoop_conflict_pending = snoop_lookup_valid &&
        (snoop_lookup_index == hit_stage_set) &&
        (snoop_lookup_tag == hit_stage_tag);
    wire hit_stage_snoop_conflict_pipe = snoop_pipe_valid &&
        (snoop_pipe_index == hit_stage_set) &&
        (snoop_pipe_tag == hit_stage_tag);
    wire hit_stage_snoop_conflict =
        ((state == S_HIT_MERGE) || (state == S_HIT_READ)) &&
        (hit_stage_snoop_conflict_now | hit_stage_snoop_conflict_pipe |
         hit_stage_snoop_conflict_pending);
    wire miss_stage_snoop_conflict_now = snoop_valid &&
        (snoop_index == fsm_index) &&
        ((snoop_tag == fsm_tag) ||
         (!miss_tag_hit_q && (snoop_tag == miss_victim_tag_q)));
    wire miss_stage_snoop_conflict_pending = snoop_lookup_valid &&
        (snoop_lookup_index == fsm_index) &&
        ((snoop_lookup_tag == fsm_tag) ||
         (!miss_tag_hit_q && (snoop_lookup_tag == miss_victim_tag_q)));
    wire miss_stage_snoop_conflict_pipe = snoop_pipe_valid &&
        (snoop_pipe_index == fsm_index) &&
        ((snoop_pipe_tag == fsm_tag) ||
         (!miss_tag_hit_q && (snoop_pipe_tag == miss_victim_tag_q)));
    wire miss_stage_snoop_conflict = (state == S_MISS_DISPATCH) &&
        (miss_stage_snoop_conflict_now | miss_stage_snoop_conflict_pipe |
         miss_stage_snoop_conflict_pending);
    wire flush_pack_snoop_conflict_now = snoop_valid &&
        (snoop_index == flush_set) && (snoop_tag == flush_wb_tag_q);
    wire flush_pack_snoop_conflict_pending = snoop_lookup_valid &&
        (snoop_lookup_index == flush_set) &&
        (snoop_lookup_tag == flush_wb_tag_q);
    wire flush_pack_snoop_conflict_pipe = snoop_pipe_valid &&
        (snoop_pipe_index == flush_set) &&
        (snoop_pipe_tag == flush_wb_tag_q);
    wire flush_pack_snoop_conflict = (state == S_FLUSH_REQ_PACK) &&
        (flush_pack_snoop_conflict_now | flush_pack_snoop_conflict_pipe |
         flush_pack_snoop_conflict_pending);
    wire snoop_pipeline_busy = snoop_valid | snoop_pipe_valid |
                               snoop_lookup_valid;

    // All data mutations share one registered write command.  Keeping writes
    // on port A gives each bank one unambiguous write port.
    wire data_write_en = (state == S_CACHE_WRITE) &&
                         !cache_write_snoop_conflict;
    wire data_write_way = cache_write_way;
    wire [INDEX_BITS-1:0] data_write_set = cache_write_set;
    wire [INDEX_BITS-1:0] data_port_a_index = data_write_en ?
                                                 data_write_set : core_read_index;
    wire [LINE_BITS-1:0] hit_stage_line = hit_stage_way ?
        hit_stage_way1_line : hit_stage_way0_line;
    wire [LINE_BITS-1:0] hit_stage_write_line = hit_stage_amo ?
        merge_amo_line(hit_stage_line, hit_stage_word_off[4:2],
                       hit_stage_amo_op, hit_stage_amo_operand) :
        merge_line(hit_stage_line, hit_stage_word_off[4:2],
                   hit_stage_memop, hit_stage_wdata,
                   hit_stage_word_off[1:0]);
    wire [LINE_BITS-1:0] fill_write_line = fsm_we ?
        (fsm_amo ? merge_amo_line(bus_resp_line, fsm_word_off[4:2],
                                  fsm_amo_op, fsm_amo_operand) :
                   merge_line(bus_resp_line, fsm_word_off[4:2], fsm_memop,
                              fsm_wdata, fsm_word_off[1:0])) :
        bus_resp_line;
    wire [LINE_BITS-1:0] data_write_line = cache_write_line;

    // Metadata port A follows the core/flush lookup; port B follows the
    // independent snoop lookup.  A snoop has priority if both ports attempt
    // to update the same way/set on one edge, matching the old sequential
    // assignment order.
    wire flush_scan_invalidate = (state == S_FLUSH_SCAN) &&
                                 (core_data_index == flush_set) &&
                                 !snoop_pipeline_busy &&
                                 (flush_state != ST_M);
    wire flush_wb_invalidate = (state == S_FLUSH_WB) &&
                               bus_resp_valid && !bus_resp_error;
    wire meta_core_write = data_write_en |
                           flush_scan_invalidate | flush_wb_invalidate;
    wire meta_core_way = data_write_en ? cache_write_way : flush_way;
    wire [INDEX_BITS-1:0] meta_core_set = data_write_en ?
                                             cache_write_set : flush_set;
    wire [META_BITS-1:0] meta_core_din = data_write_en ?
        {cache_write_tag, cache_write_state} :
        {{TAG_BITS{1'b0}}, ST_I};

    // Scan invalidation is serialized behind snoops above.  If a snoop result
    // happens to coincide with completion of a dirty flush writeback, making
    // that snooped line Invalid is always coherence-safe (and avoids feeding
    // the maintenance BRAM tag back into port-B write data).
    wire snoop_flush_wins = (state == S_FLUSH_WB) &&
                            bus_resp_valid && !bus_resp_error;
    wire [1:0] snoop_next_state = snoop_flush_wins ? ST_I :
                                  (snoop_lookup_type ? ST_S : ST_I);
    wire snoop_meta_write = !init_active && snoop_lookup_valid && snoop_hit_v;
    wire snoop_meta_we_way0 = snoop_meta_write && !snoop_hit_way_v;
    wire snoop_meta_we_way1 = snoop_meta_write &&  snoop_hit_way_v;
    wire [META_BITS-1:0] snoop_meta_din =
        {snoop_lookup_tag, snoop_next_state};

    // core_read_index already selects flush_set in every maintenance state.
    // Only a registered cache commit needs to override it; keeping the flush
    // dirty/clean decision out of this address mux removes another metadata
    // BRAM-output -> BRAM-address feedback path.
    wire [INDEX_BITS-1:0] meta_port_a_index = init_active ? init_index :
                                              data_write_en ? cache_write_set :
                                                              core_read_index;
    // Only maintenance can now overlap a snoop metadata write; ordinary core
    // commits retry behind any snoop before asserting data_write_en.
    wire flush_meta_write = flush_scan_invalidate | flush_wb_invalidate;
    wire flush_meta_collision = flush_wb_invalidate && snoop_lookup_valid &&
                                (flush_set == snoop_lookup_index) &&
                                (flush_wb_tag_q == snoop_lookup_tag);
    wire meta_a_we_way0 = init_active ||
                          (data_write_en && !cache_write_way) ||
                          (flush_meta_write && !flush_way &&
                           !flush_meta_collision);
    wire meta_a_we_way1 = init_active ||
                          (data_write_en &&  cache_write_way) ||
                          (flush_meta_write &&  flush_way &&
                           !flush_meta_collision);
    wire [META_BITS-1:0] meta_a_din = init_active ? {META_BITS{1'b0}} :
                                                   meta_core_din;

    cache_tdp_data_ram #(
        .WIDTH     (LINE_BITS),
        .ADDR_WIDTH(INDEX_BITS)
    ) u_data_way0 (
        .clk   (clk),
        .we_a  (data_write_en && (data_write_way == 1'b0)),
        .addr_a(data_port_a_index),
        .din_a (data_write_line),
        .dout_a(core_way0_line),
        .we_b  (1'b0),
        .addr_b(snoop_index),
        .din_b ({LINE_BITS{1'b0}}),
        .dout_b(snoop_way0_line)
    );

    cache_tdp_data_ram #(
        .WIDTH     (LINE_BITS),
        .ADDR_WIDTH(INDEX_BITS)
    ) u_data_way1 (
        .clk   (clk),
        .we_a  (data_write_en && (data_write_way == 1'b1)),
        .addr_a(data_port_a_index),
        .din_a (data_write_line),
        .dout_a(core_way1_line),
        .we_b  (1'b0),
        .addr_b(snoop_index),
        .din_b ({LINE_BITS{1'b0}}),
        .dout_b(snoop_way1_line)
    );

    cache_tdp_data_ram #(
        .WIDTH     (META_BITS),
        .ADDR_WIDTH(INDEX_BITS)
    ) u_meta_way0 (
        .clk   (clk),
        .we_a  (meta_a_we_way0),
        .addr_a(meta_port_a_index),
        .din_a (meta_a_din),
        .dout_a(core_meta_way0),
        .we_b  (snoop_meta_we_way0),
        .addr_b(snoop_index),
        .din_b (snoop_meta_din),
        .dout_b(snoop_meta_way0)
    );

    cache_tdp_data_ram #(
        .WIDTH     (META_BITS),
        .ADDR_WIDTH(INDEX_BITS)
    ) u_meta_way1 (
        .clk   (clk),
        .we_a  (meta_a_we_way1),
        .addr_a(meta_port_a_index),
        .din_a (meta_a_din),
        .dout_a(core_meta_way1),
        .we_b  (snoop_meta_we_way1),
        .addr_b(snoop_index),
        .din_b (snoop_meta_din),
        .dout_b(snoop_meta_way1)
    );

    // Track the address associated with synchronous RAM port A.
    always @(posedge clk) begin
        core_data_index <= data_port_a_index;
        if (rst || init_active) begin
            core_lookup_addr  <= 32'b0;
            core_lookup_valid <= 1'b0;
            lookup_decision_ready_q <= 1'b0;
            lookup_access_ok_q      <= 1'b0;
            lookup_req_re_q         <= 1'b0;
            lookup_req_we_q         <= 1'b0;
            hit_stage_way0_line <= {LINE_BITS{1'b0}};
            hit_stage_way1_line <= {LINE_BITS{1'b0}};
            hit_stage_way        <= 1'b0;
            hit_stage_set        <= {INDEX_BITS{1'b0}};
            hit_stage_tag        <= {TAG_BITS{1'b0}};
            hit_stage_word_off   <= 5'b0;
            hit_stage_memop      <= 3'b0;
            hit_stage_wdata      <= 32'b0;
            hit_stage_amo        <= 1'b0;
            hit_stage_amo_op     <= 5'b0;
            hit_stage_amo_operand <= 32'b0;
        end
        else begin
            // The core request boundary is sampled only while the blocking
            // FSM can accept a new transaction.  Invalidating this pipeline
            // in every non-IDLE state is essential for read-first BRAM: a
            // just-completed fill/RMW must not leave its pre-commit miss
            // decision queued behind the response pulse.
            core_lookup_addr  <= cpu_addr;
            core_lookup_valid <= (state == S_IDLE) && (cpu_re | cpu_we);
            // Register the tag/MSI decision as well as the two BRAM lines.
            // State transitions in S_IDLE consume only this compact decision
            // stage, so metadata BRAM outputs never drive the high-fanout FSM
            // state enable directly.
            lookup_decision_ready_q <= core_lookup_ready &&
                                       (state == S_IDLE);
            lookup_access_ok_q      <= access_ok;
            lookup_req_re_q         <= (state == S_IDLE) && cpu_re;
            lookup_req_we_q         <= (state == S_IDLE) && cpu_we;
            // Capture unconditionally.  Conditional enables here would put
            // the dTLB/tag-hit decision on the CE pin of 512 line registers
            // and recreate the long path this stage is intended to cut.
            hit_stage_way0_line <= core_way0_line;
            hit_stage_way1_line <= core_way1_line;
            hit_stage_way        <= tag_hit_way_v;
            hit_stage_set        <= lookup_index;
            hit_stage_tag        <= lookup_tag;
            hit_stage_word_off   <= {lookup_word, core_lookup_addr[1:0]};
            hit_stage_memop      <= cpu_memop;
            hit_stage_wdata      <= cpu_wdata;
            hit_stage_amo        <= cpu_amo;
            hit_stage_amo_op     <= cpu_amo_op;
            hit_stage_amo_operand <= cpu_amo_operand;
        end
    end

    // Track the request associated with synchronous RAM port B.
    always @(posedge clk) begin
        if (rst || init_active) begin
            snoop_pipe_addr    <= 32'b0;
            snoop_pipe_valid   <= 1'b0;
            snoop_pipe_type    <= 1'b0;
            snoop_lookup_addr  <= 32'b0;
            snoop_lookup_valid <= 1'b0;
            snoop_lookup_type  <= 1'b0;
        end
        else begin
            snoop_pipe_addr    <= snoop_addr;
            snoop_pipe_valid   <= snoop_valid;
            snoop_pipe_type    <= snoop_type;
            snoop_lookup_addr  <= snoop_pipe_addr;
            snoop_lookup_valid <= snoop_pipe_valid;
            snoop_lookup_type  <= snoop_pipe_type;
        end
    end

    // cpu_valid is driven once, below (after the FSM always block),
    // as the OR of a same-cycle hit and a miss-just-resolved pulse.
    always @(posedge clk) begin
        if (rst) begin
            state           <= S_IDLE;
            bus_req_valid   <= 1'b0;
            miss_done_pulse <= 1'b0;
            miss_error_pulse <= 1'b0;
            hit_write_done_pulse <= 1'b0;
            hit_read_done_pulse <= 1'b0;
            flush_pending   <= 1'b0;
            flush_seen      <= 1'b0;
            flush_done      <= 1'b0;
            flush_error     <= 1'b0;
            flush_set       <= {INDEX_BITS{1'b0}};
            flush_way       <= 1'b0;
            fsm_amo         <= 1'b0;
            fsm_amo_op      <= 5'b0;
            fsm_amo_operand <= 32'b0;
            miss_victim_line_q  <= {LINE_BITS{1'b0}};
            miss_victim_tag_q   <= {TAG_BITS{1'b0}};
            miss_victim_state_q <= ST_I;
            miss_tag_hit_q      <= 1'b0;
            uncached_addr_q       <= 32'b0;
            uncached_store_data_q <= 32'b0;
            uncached_memop_q      <= 3'b0;
            cache_write_line <= {LINE_BITS{1'b0}};
            cache_write_way  <= 1'b0;
            cache_write_set  <= {INDEX_BITS{1'b0}};
            cache_write_tag  <= {TAG_BITS{1'b0}};
            cache_write_state <= ST_I;
            cache_write_from_hit <= 1'b0;
            flush_wb_line_q <= {LINE_BITS{1'b0}};
            flush_wb_tag_q  <= {TAG_BITS{1'b0}};
            cpu_response_data <= 32'b0;
            snoop_ack_valid <= 1'b0;
            snoop_ack_hit   <= 1'b0;
            snoop_ack_dirty <= 1'b0;
            snoop_ack_line  <= {LINE_BITS{1'b0}};
            init_active     <= 1'b1;
            init_index      <= {INDEX_BITS{1'b0}};
        end
        else begin
            miss_done_pulse <= 1'b0;
            miss_error_pulse <= 1'b0;
            hit_write_done_pulse <= 1'b0;
            hit_read_done_pulse <= 1'b0;
            flush_done      <= 1'b0;
            flush_error     <= 1'b0;
            flush_seen      <= flush;
            snoop_ack_valid <= 1'b0;

            if (flush && !flush_seen)
                flush_pending <= 1'b1;

            // Capture request/victim operands whenever the blocking FSM is
            // idle, independently of the hit/miss decision.  In particular,
            // do not use access_ok/tag compare as the clock-enable for these
            // wide registers: that previously replicated the metadata path
            // onto hundreds of FF CEs and became slower than the payload path
            // this stage was added to cut.
            if (!init_active && (state == S_IDLE)) begin
                fsm_way   <= tag_hit_v ? tag_hit_way_v : lru_r[lookup_index];
                fsm_index <= lookup_index;
                fsm_tag   <= lookup_tag;
                fsm_we    <= cpu_we;
                fsm_memop <= cpu_memop;
                fsm_wdata <= cpu_wdata;
                fsm_word_off <= uncached_access ?
                    {addr_word, cpu_addr[1:0]} :
                    {lookup_word, core_lookup_addr[1:0]};
                fsm_amo         <= cpu_amo;
                fsm_amo_op      <= cpu_amo_op;
                fsm_amo_operand <= cpu_amo_operand;
                miss_victim_tag_q   <= victim_tag;
                miss_victim_state_q <= victim_state;
                miss_tag_hit_q      <= tag_hit_v;
            end

            // Likewise, sample the selected maintenance line throughout the
            // scan state.  The dirty decision only advances the FSM; it no
            // longer drives a 256-bit register enable.
            if (!init_active && (state == S_FLUSH_SCAN)) begin
                flush_wb_tag_q  <= flush_tag;
                flush_wb_line_q <= flush_line;
            end

            if (init_active) begin
                // Invalidate one set in each way per cycle.  This keeps the
                // metadata and LRU stores as real RAMs instead of a resettable
                // bank of thousands of flops and muxes.
                bus_req_valid    <= 1'b0;
                lru_r[init_index] <= 1'b0;
                if (init_index == SETS-1) begin
                    init_active <= 1'b0;
                end
                else begin
                    init_index <= init_index + {{(INDEX_BITS-1){1'b0}}, 1'b1};
                end
            end
            else begin

            // Keep a fill/RFO request asserted through the registered cache
            // commit, not merely through controller acceptance.  This is the
            // completion barrier that prevents a following core's snoop from
            // arriving while the granted line is still in an AHB return
            // buffer and therefore not yet visible in this L1.

            case (state)
                // ------------------------------------------------
                S_IDLE: begin
                    if (flush_pending || (flush && !flush_seen)) begin
                        flush_pending <= 1'b0;
                        flush_set     <= {INDEX_BITS{1'b0}};
                        flush_way     <= 1'b0;
                        bus_req_valid <= 1'b0;
                        state         <= S_FLUSH_SCAN;
                    end
                    // miss_done_pulse acknowledges the request that was
                    // held throughout S_MISS_REQ.  The pipeline consumes
                    // that acknowledgement on this edge, so do not also
                    // reinterpret the still-held request as a fresh hit.
                    // This is essential for non-idempotent AMOs: otherwise
                    // a cold AMO would apply its RMW twice.
                    else if (!miss_done_pulse && !miss_error_pulse &&
                             !hit_write_done_pulse && !hit_read_done_pulse &&
                             (cpu_re | cpu_we) && uncached_access) begin
                        // Device accesses are strongly ordered by this
                        // blocking cache and bypass both tag/data arrays.
                        // AMOs require an atomic-capable system bus, which
                        // this AXI/AHB boundary does not advertise; fail them
                        // instead of silently degrading atomicity.
                        if (cpu_amo) begin
                            miss_error_pulse <= 1'b1;
                            state            <= S_POST_RESPONSE;
                        end
                        else begin
                            // Address/operand stage.  The blocking core keeps
                            // the architectural request stable, but only these
                            // local registers feed the store formatter and bus
                            // request payload in the following cycle.
                            uncached_addr_q       <= cpu_addr;
                            uncached_store_data_q <= cpu_wdata;
                            uncached_memop_q      <= cpu_memop;
                            state                 <= S_UNCACHED_PACK;
                        end
                    end
                    else if (!miss_done_pulse && !miss_error_pulse &&
                             !hit_write_done_pulse && !hit_read_done_pulse &&
                             (lookup_req_re_q | lookup_req_we_q) &&
                             lookup_decision_ready_q &&
                             lookup_access_ok_q && lookup_req_we_q) begin
                        // Request operands and both candidate BRAM lines were
                        // captured by the lookup pipeline above.  Perform the
                        // byte/AMO merge only after that register boundary.
                        state <= S_HIT_MERGE;
                    end
                    else if (!miss_done_pulse && !miss_error_pulse &&
                             !hit_write_done_pulse && !hit_read_done_pulse &&
                             lookup_req_re_q && !lookup_req_we_q &&
                             lookup_decision_ready_q &&
                             lookup_access_ok_q) begin
                        // As with write hits, do not expose a combinational
                        // dTLB/tag-hit path as the cache completion signal.
                        // The already captured way lines supply S_HIT_READ.
                        state <= S_HIT_READ;
                    end
                    else if (!miss_done_pulse && !miss_error_pulse &&
                             !hit_write_done_pulse && !hit_read_done_pulse &&
                             (lookup_req_re_q | lookup_req_we_q) &&
                             lookup_decision_ready_q &&
                             !lookup_access_ok_q) begin
                        // Need the bus. Decide the fill way and
                        // whether its current occupant (if any, and
                        // if it's actually a DIFFERENT line) needs a
                        // writeback first.
                        state               <= S_MISS_PREP;
                    end
                end

                // ------------------------------------------------
                // Register the selected victim payload only after the LRU/tag
                // decision has reached fsm_way.  Previously the asynchronous
                // LRU RAM output directly selected 256 bits here, creating a
                // fanout-257 route from the request address to every victim
                // line register.  This miss-only stage removes that cone from
                // the hit path and adds no cycles to hit throughput.
                S_MISS_PREP: begin
                    miss_victim_line_q <= fsm_way ? hit_stage_way1_line :
                                                       hit_stage_way0_line;
                    state <= S_MISS_DISPATCH;
                end

                // A snoop arriving anywhere in the added pipeline gap wins
                // and makes the held CPU request retry from S_IDLE against
                // the updated MSI state.
                S_MISS_DISPATCH: begin
                    if (miss_stage_snoop_conflict) begin
                        bus_req_valid <= 1'b0;
                        state         <= S_IDLE;
                    end
                    else if (!miss_tag_hit_q &&
                             (miss_victim_state_q == ST_M)) begin
                        bus_req_valid <= 1'b1;
                        bus_req_type  <= REQ_WRITEBACK;
                        bus_req_addr  <= {miss_victim_tag_q, fsm_index,
                                          {OFFSET_BITS{1'b0}}};
                        bus_req_line  <= miss_victim_line_q;
                        state         <= S_EVICT;
                    end
                    else begin
                        bus_req_valid <= 1'b1;
                        bus_req_type  <= fsm_we ? REQ_RFO : REQ_READ;
                        bus_req_addr  <= {fsm_tag, fsm_index,
                                          {OFFSET_BITS{1'b0}}};
                        state         <= S_MISS_REQ;
                    end
                end

                // ------------------------------------------------
                // Registered write-hit merge. A snoop that reaches this line
                // before the commit wins; leave the held CPU request
                // unacknowledged so it is re-evaluated against the new MSI
                // state after returning to S_IDLE.
                S_HIT_MERGE: begin
                    if (hit_stage_snoop_conflict) begin
                        state <= S_IDLE;
                    end
                    else begin
                        cache_write_line     <= hit_stage_write_line;
                        cache_write_way      <= hit_stage_way;
                        cache_write_set      <= hit_stage_set;
                        cache_write_tag      <= hit_stage_tag;
                        cache_write_state    <= ST_M;
                        cache_write_from_hit <= 1'b1;
                        if (hit_stage_amo)
                            cpu_response_data <=
                                hit_stage_line[hit_stage_word_off[4:2]*32 +: 32];
                        state                <= S_CACHE_WRITE;
                    end
                end

                // ------------------------------------------------
                // Registered read-hit response.  Registering both the raw
                // word and completion removes the previous combinational
                // dTLB -> D-cache hit -> access-fault/CSR timing path.
                S_HIT_READ: begin
                    if (hit_stage_snoop_conflict) begin
                        state <= S_IDLE;
                    end
                    else begin
                        cpu_response_data <= format_load(
                            hit_stage_line[hit_stage_word_off[4:2]*32 +: 32],
                            hit_stage_word_off[1:0], hit_stage_memop);
                        hit_read_done_pulse <= 1'b1;
                        state <= S_POST_RESPONSE;
                    end
                end

                // ------------------------------------------------
                S_EVICT: begin
                    if (bus_resp_valid) begin
                        bus_req_valid <= 1'b0;
                        if (bus_resp_error) begin
                            // The victim remains M and authoritative;
                            // fail the held CPU operation without dropping it.
                            miss_error_pulse <= 1'b1;
                            state            <= S_POST_RESPONSE;
                        end
                        else begin
                            // Insert one low-valid cycle between the
                            // writeback and the dependent fill/RFO.
                            state <= S_AFTER_EVICT;
                        end
                    end
                end

                S_AFTER_EVICT: begin
                    bus_req_valid <= 1'b1;
                    bus_req_type  <= fsm_we ? REQ_RFO : REQ_READ;
                    bus_req_addr  <= {fsm_tag, fsm_index, {OFFSET_BITS{1'b0}}};
                    state         <= S_MISS_REQ;
                end

                // ------------------------------------------------
                S_MISS_REQ: begin
                    if (bus_resp_valid) begin
                        if (bus_resp_error) begin
                            // Never install or modify a line returned with
                            // an error. The registered pulse completes the
                            // held load/store/AMO as an access fault.
                            bus_req_valid    <= 1'b0;
                            miss_error_pulse <= 1'b1;
                        end
                        else begin
                            // Register both data and metadata before driving
                            // the XPM write port. For an AMO, keep the old word
                            // for the architectural return value.
                            cache_write_line     <= fill_write_line;
                            cache_write_way      <= fsm_way;
                            cache_write_set      <= fsm_index;
                            cache_write_tag      <= fsm_tag;
                            cache_write_state    <= fsm_we ? ST_M : ST_S;
                            cache_write_from_hit <= 1'b0;
                            if (fsm_we && fsm_amo)
                                cpu_response_data <=
                                    bus_resp_line[fsm_word_off[4:2]*32 +: 32];
                            else if (!fsm_we)
                                cpu_response_data <= format_load(
                                    bus_resp_line[fsm_word_off[4:2]*32 +: 32],
                                    fsm_word_off[1:0], fsm_memop);
                            // MSI has no Exclusive state: every read fill is
                            // Shared even when this is the only copy.
                            state <= S_CACHE_WRITE;
                        end
                        if (bus_resp_error)
                            state <= S_POST_RESPONSE;
                    end
                end

                // ------------------------------------------------
                // Registered cache-array commit.  A same-line snoop aborts
                // the commit and leaves the CPU request unacknowledged so it
                // retries against the snoop-updated MSI state.
                S_CACHE_WRITE: begin
                    if (cache_write_snoop_conflict) begin
                        bus_req_valid <= 1'b0;
                        state <= S_IDLE;
                    end
                    else begin
                        bus_req_valid <= 1'b0;
                        if (cache_write_from_hit)
                            hit_write_done_pulse <= 1'b1;
                        else begin
                            lru_r[cache_write_set] <= ~cache_write_way;
                            miss_done_pulse        <= 1'b1;
                        end
                        state <= S_POST_RESPONSE;
                    end
                end

                // ------------------------------------------------
                // The core-side request is level-held until cpu_valid.  The
                // synchronous read-first RAMs can still hold the pre-commit
                // miss decision for that request when a fill/RMW completes.
                // Insert one deterministic response bubble before returning
                // to IDLE.  Requiring re/we to fall here deadlocks when the
                // core advances directly to another memory instruction and
                // keeps the request level asserted across the boundary.
                S_POST_RESPONSE: begin
                    bus_req_valid <= 1'b0;
                    state <= S_IDLE;
                end

                // ------------------------------------------------
                // Format and pack the registered uncached store operand.  A
                // read uses the same payload shape with write-enable low; its
                // data/strobes are ignored by the controller.
                S_UNCACHED_PACK: begin
                    bus_req_valid <= 1'b1;
                    bus_req_type  <= REQ_UNCACHED;
                    bus_req_addr  <= uncached_addr_q;
                    bus_req_line  <= {{(LINE_BITS-37){1'b0}},
                                      fsm_we, uncached_wstrb,
                                      uncached_wdata};
                    state         <= S_UNCACHED_REQ;
                end

                // ------------------------------------------------
                // A single-word, non-allocating device transaction.  The
                // coherence manager returns read data in response line word
                // zero only; the held CPU address/memop perform extraction
                // and sign extension through load_unit above.
                S_UNCACHED_REQ: begin
                    if (bus_resp_valid) begin
                        bus_req_valid <= 1'b0;
                        if (bus_resp_error) begin
                            miss_error_pulse <= 1'b1;
                        end
                        else begin
                            if (!fsm_we)
                                cpu_response_data <= format_load(
                                    bus_resp_line[31:0],
                                    fsm_word_off[1:0], fsm_memop);
                            miss_done_pulse    <= 1'b1;
                        end
                        state <= S_POST_RESPONSE;
                    end
                end

                // ------------------------------------------------
                // Safe whole-cache flush.  Clean S lines can be
                // invalidated locally.  An M line is written back
                // through the normal coherence-manager request path
                // before it is invalidated.  S_FLUSH_GAP guarantees a
                // low-valid cycle between consecutive writebacks.
                S_FLUSH_SCAN: begin
                    bus_req_valid <= 1'b0;
                    // The BRAM output belongs to the address sampled on the
                    // preceding clock.  After advancing flush_set, wait until
                    // port A has actually returned that set before deciding
                    // whether the line needs a writeback.
                    if (core_data_index != flush_set) begin
                        // wait for the synchronous RAM lookup
                    end
                    else if (snoop_pipeline_busy) begin
                        // Serialize maintenance metadata changes behind the
                        // registered snoop pipeline.  This is rare contention
                        // and avoids a BRAM-output feedback path into WE.
                    end
                    else if (flush_state == ST_M) begin
                        state <= S_FLUSH_REQ_PACK;
                    end
                    else begin
                        if ((flush_set == SETS-1) && (flush_way == 1'b1)) begin
                            flush_done <= 1'b1;
                            state      <= S_IDLE;
                        end
                        else if (flush_way == 1'b0) begin
                            flush_way <= 1'b1;
                        end
                        else begin
                            flush_way <= 1'b0;
                            flush_set <= flush_set + {{(INDEX_BITS-1){1'b0}}, 1'b1};
                        end
                    end
                end

                // Dirty maintenance lines have their own payload register
                // boundary.  This keeps the 256-bit BRAM read and bus request
                // fanout out of the scan/metadata decision cycle.
                S_FLUSH_REQ_PACK: begin
                    if (flush_pack_snoop_conflict) begin
                        bus_req_valid <= 1'b0;
                        state         <= S_FLUSH_SCAN;
                    end
                    else begin
                        bus_req_valid <= 1'b1;
                        bus_req_type  <= REQ_WRITEBACK;
                        bus_req_addr  <= {flush_wb_tag_q, flush_set,
                                          {OFFSET_BITS{1'b0}}};
                        bus_req_line  <= flush_wb_line_q;
                        state         <= S_FLUSH_WB;
                    end
                end

                S_FLUSH_WB: begin
                    if (bus_resp_valid) begin
                        bus_req_valid <= 1'b0;
                        if (bus_resp_error) begin
                            // Preserve the dirty line and terminate this
                            // maintenance pass without invalidating I$.
                            flush_error <= 1'b1;
                            state       <= S_IDLE;
                        end
                        else begin
                            if ((flush_set == SETS-1) && (flush_way == 1'b1)) begin
                                flush_done <= 1'b1;
                                state      <= S_IDLE;
                            end
                            else begin
                                if (flush_way == 1'b0) begin
                                    flush_way <= 1'b1;
                                end
                                else begin
                                    flush_way <= 1'b0;
                                    flush_set <= flush_set + {{(INDEX_BITS-1){1'b0}}, 1'b1};
                                end
                                state <= S_FLUSH_GAP;
                            end
                        end
                    end
                end

                S_FLUSH_GAP: begin
                    bus_req_valid <= 1'b0;
                    state         <= S_FLUSH_SCAN;
                end

                default: state <= S_IDLE;
            endcase

            // ---- Snoop response (runs every cycle, independent of `state` above) ----
            snoop_ack_valid <= snoop_lookup_valid;
            if (snoop_lookup_valid) begin
                snoop_ack_hit   <= snoop_hit_v;
                snoop_ack_dirty <= snoop_hit_v && (snoop_hit_state_v == ST_M);
                snoop_ack_line  <= snoop_hit_line_v;
            end
            end
        end
    end

    // Every cached hit completion is registered.  This avoids exposing tag,
    // translation, snoop-conflict and load formatting logic as a same-cycle
    // path back into the core's stall/fault/CSR controls.
    assign cpu_valid = hit_read_done_pulse | hit_write_done_pulse |
                       miss_done_pulse | miss_error_pulse;
    assign cpu_error = miss_error_pulse;

endmodule

// --------------------------------------------------------------------------
// Cache-line true-dual-port RAM
//
// Vivado's XPM removes inference ambiguity for the wide two-read/one-write
// cache array.  The behavioural branch keeps ordinary RTL simulators and the
// existing self-checking testbenches independent of vendor simulation libs.
// --------------------------------------------------------------------------
// Common synchronous true-dual-port Block RAM wrapper used by both cache-line
// data and compact tag/MSI metadata arrays.
module cache_tdp_data_ram #(
    parameter integer WIDTH = 256,
    parameter integer ADDR_WIDTH = 6
) (
    input  wire                  clk,
    input  wire                  we_a,
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [WIDTH-1:0]      din_a,
    output wire [WIDTH-1:0]      dout_a,
    input  wire                  we_b,
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [WIDTH-1:0]      din_b,
    output wire [WIDTH-1:0]      dout_b
);
`ifdef SYNTHESIS
    xpm_memory_tdpram #(
        .ADDR_WIDTH_A       (ADDR_WIDTH),
        .ADDR_WIDTH_B       (ADDR_WIDTH),
        .AUTO_SLEEP_TIME    (0),
        .BYTE_WRITE_WIDTH_A (WIDTH),
        .BYTE_WRITE_WIDTH_B (WIDTH),
        .CASCADE_HEIGHT     (0),
        .CLOCKING_MODE      ("common_clock"),
        .ECC_MODE           ("no_ecc"),
        .MEMORY_INIT_FILE   ("none"),
        .MEMORY_INIT_PARAM  ("0"),
        .MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE   ("block"),
        .MEMORY_SIZE        (WIDTH * (1 << ADDR_WIDTH)),
        .MESSAGE_CONTROL    (0),
        .READ_DATA_WIDTH_A  (WIDTH),
        .READ_DATA_WIDTH_B  (WIDTH),
        .READ_LATENCY_A     (1),
        // Port B is the coherence/maintenance lookup.  Its extra embedded
        // output register breaks the tag-BRAM -> tag-compare -> metadata-WE
        // feedback path without changing the core-side hit latency.
        .READ_LATENCY_B     (2),
        .READ_RESET_VALUE_A ("0"),
        .READ_RESET_VALUE_B ("0"),
        .RST_MODE_A         ("SYNC"),
        .RST_MODE_B         ("SYNC"),
        .SIM_ASSERT_CHK     (0),
        .USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT       (0),
        .WAKEUP_TIME        ("disable_sleep"),
        .WRITE_DATA_WIDTH_A (WIDTH),
        .WRITE_DATA_WIDTH_B (WIDTH),
        .WRITE_MODE_A       ("read_first"),
        .WRITE_MODE_B       ("read_first"),
        .WRITE_PROTECT      (1)
    ) u_xpm (
        .sleep          (1'b0),
        .clka           (clk),
        .rsta           (1'b0),
        .ena            (1'b1),
        .regcea         (1'b1),
        .wea            (we_a),
        .addra          (addr_a),
        .dina           (din_a),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .douta          (dout_a),
        .sbiterra       (),
        .dbiterra       (),
        .clkb           (clk),
        .rstb           (1'b0),
        .enb            (1'b1),
        .regceb         (1'b1),
        .web            (we_b),
        .addrb          (addr_b),
        .dinb           (din_b),
        .injectsbiterrb (1'b0),
        .injectdbiterrb (1'b0),
        .doutb          (dout_b),
        .sbiterrb       (),
        .dbiterrb       ()
    );
`else
    reg [WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];
    reg [WIDTH-1:0] dout_a_r;
    reg [WIDTH-1:0] dout_b_pipe_r;
    reg [WIDTH-1:0] dout_b_r;

    assign dout_a = dout_a_r;
    assign dout_b = dout_b_r;

    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;
        if (we_b)
            mem[addr_b] <= din_b;
        dout_a_r <= mem[addr_a];
        dout_b_pipe_r <= mem[addr_b];
        dout_b_r      <= dout_b_pipe_r;
    end
`endif
endmodule
