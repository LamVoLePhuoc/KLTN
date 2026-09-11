`timescale 1ns / 1ps

// ============================================================
// l1_dcache
//
// Private, per-core L1 data cache. PIPT, MESI, per address_mapping:
//   16KB, 2-way set-associative, line = 32B (8 words)
//   offset = 5b, index = 8b (256 sets), tag = 19b
//
// Write-back, write-allocate, blocking (single outstanding request
// -- matches the core, which has no mechanism for more than one
// in-flight memory access at a time).
//
// Coherence: participates in the system's MESI protocol via a
// request port (to coherence_manager.v, for misses/upgrades/
// evictions) and a snoop port (from coherence_manager.v, for other
// cores' requests that need this cache to invalidate or downgrade).
// State per line: 2'b00=I, 2'b01=S, 2'b10=E, 2'b11=M.
//
// bus_req_type: 2'b00=READ (want S or E), 2'b01=RFO (want M,
// read-for-ownership/upgrade), 2'b10=WRITEBACK (voluntary eviction
// of a dirty line, no response data expected beyond the ack pulse).
// snoop_type: 1'b0=INVALIDATE, 1'b1=DOWNGRADE (M/E -> S).
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
// would try to update this module's state_r for the same line on
// the same clock edge from what would otherwise be two independent
// paths. Resolved below by `snoop_conflict`: whenever an incoming
// snoop targets the exact line the core's own access is hitting on
// this cycle, the snoop wins and the core's own access is forced
// back to "not ready" (retried next cycle, by which point the snoop
// has resolved and the core's normal hit/upgrade-miss logic handles
// it correctly with no special-casing needed).
//
// Silent clean eviction: a victim way holding a clean (S or E) line
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
    parameter INDEX_BITS  = 8,     // 256 sets
    parameter LINE_WORDS  = 8      // 32B line = 8 x 32-bit words
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         flush,      // pulse: drop all lines with no writeback (sim/debug use only)

    // ---- Core side (matches mmu_core_wrapper's Mem_* shape) ----
    input  wire [31:0]  cpu_addr,
    input  wire [31:0]  cpu_wdata,
    input  wire         cpu_we,
    input  wire         cpu_re,
    input  wire [2:0]   cpu_memop,     // funct3 (SB/SH/SW, LB/LH/LW/LBU/LHU) -- see store_unit.v/load_unit.v
    output wire [31:0]  cpu_rdata,
    output wire         cpu_valid,     // 1 exactly when this access has completed (hit this cycle, or miss just resolved)

    // ---- Bus side (request to coherence_manager.v) ----
    output reg                        bus_req_valid,
    output reg  [1:0]                 bus_req_type,
    output reg  [31:0]                bus_req_addr,   // line-aligned
    output reg  [LINE_WORDS*32-1:0]   bus_req_line,   // valid for WRITEBACK only
    input  wire                       bus_resp_valid,
    input  wire [LINE_WORDS*32-1:0]   bus_resp_line,
    input  wire [1:0]                 bus_resp_state, // granted MESI state (S/E/M) -- ignored for WRITEBACK acks

    // ---- Snoop side (from coherence_manager.v) ----
    input  wire         snoop_valid,
    input  wire         snoop_type,
    input  wire [31:0]  snoop_addr,
    output reg           snoop_ack_valid,
    output reg           snoop_ack_hit,
    output reg           snoop_ack_dirty,
    output reg  [LINE_WORDS*32-1:0] snoop_ack_line
);

    localparam WAYS         = 2;
    localparam OFFSET_BITS  = 5;
    localparam TAG_BITS     = 32 - INDEX_BITS - OFFSET_BITS;
    localparam SETS         = (1 << INDEX_BITS);
    localparam LINE_BITS    = LINE_WORDS * 32;

    localparam [1:0] ST_I = 2'b00, ST_S = 2'b01, ST_E = 2'b10, ST_M = 2'b11;
    localparam [1:0] REQ_READ = 2'b00, REQ_RFO = 2'b01, REQ_WRITEBACK = 2'b10;

    wire [TAG_BITS-1:0]   addr_tag   = cpu_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] addr_index = cpu_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    wire [2:0]            addr_word  = cpu_addr[4:2];

    wire [TAG_BITS-1:0]   snoop_tag   = snoop_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] snoop_index = snoop_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];

    // ------------------------------------------------------
    // Storage
    // ------------------------------------------------------
    reg [1:0]              state_r [0:WAYS-1][0:SETS-1]; // 2'b00 = invalid
    reg [TAG_BITS-1:0]     tag_r   [0:WAYS-1][0:SETS-1];
    reg [LINE_BITS-1:0]    data_r  [0:WAYS-1][0:SETS-1];
    reg                    lru_r   [0:SETS-1];

    integer w, s;

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

    always @(*) begin
        tag_hit_v       = 1'b0;
        tag_hit_way_v   = 1'b0;
        tag_hit_state_v = ST_I;
        tag_hit_line_v  = {LINE_BITS{1'b0}};
        for (w = 0; w < WAYS; w = w + 1) begin
            if ((state_r[w][addr_index] != ST_I) && (tag_r[w][addr_index] == addr_tag)) begin
                tag_hit_v       = 1'b1;
                tag_hit_way_v   = w[0];
                tag_hit_state_v = state_r[w][addr_index];
                tag_hit_line_v  = data_r[w][addr_index];
            end
        end
    end

    wire snoop_conflict = snoop_valid && (snoop_index == addr_index) &&
                          tag_hit_v && (snoop_tag == addr_tag);

    wire access_ok = tag_hit_v & ~snoop_conflict &
                      (cpu_we ? (tag_hit_state_v == ST_M || tag_hit_state_v == ST_E)
                               : (tag_hit_state_v != ST_I));

    wire [31:0] hit_word_raw = tag_hit_line_v[addr_word*32 +: 32];

    load_unit u_load_unit (
        .raw_data    (hit_word_raw),
        .addr_offset (cpu_addr[1:0]),
        .mem_op      (cpu_memop),
        .load_data   (cpu_rdata)
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
        for (w = 0; w < WAYS; w = w + 1) begin
            if ((state_r[w][snoop_index] != ST_I) && (tag_r[w][snoop_index] == snoop_tag)) begin
                snoop_hit_v       = 1'b1;
                snoop_hit_way_v   = w[0];
                snoop_hit_state_v = state_r[w][snoop_index];
                snoop_hit_line_v  = data_r[w][snoop_index];
            end
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

    // ------------------------------------------------------
    // Core-side miss/eviction FSM
    // ------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0, S_EVICT = 2'd1, S_MISS_REQ = 2'd2;
    reg [1:0] state;

    reg                   fsm_way;
    reg [INDEX_BITS-1:0]  fsm_index;
    reg [TAG_BITS-1:0]    fsm_tag;
    reg                   fsm_we;       // pending access was a write (needs RFO + local merge on fill)
    reg [2:0]             fsm_memop;
    reg [31:0]            fsm_wdata;
    reg [4:0]              fsm_word_off; // {word[2:0], byte[1:0]} of the pending access, for the post-fill merge

    // cpu_valid is driven once, below (after the FSM always block),
    // as the OR of a same-cycle hit and a miss-just-resolved pulse.
    reg miss_done_pulse;

    always @(posedge clk) begin
        if (rst) begin
            state           <= S_IDLE;
            bus_req_valid   <= 1'b0;
            miss_done_pulse <= 1'b0;
            for (s = 0; s < SETS; s = s + 1) begin
                lru_r[s] <= 1'b0;
                for (w = 0; w < WAYS; w = w + 1) begin
                    state_r[w][s] <= ST_I;
                end
            end
        end
        else if (flush) begin
            state         <= S_IDLE;
            bus_req_valid <= 1'b0;
            for (s = 0; s < SETS; s = s + 1) begin
                for (w = 0; w < WAYS; w = w + 1) begin
                    state_r[w][s] <= ST_I;
                end
            end
        end
        else begin
            miss_done_pulse <= 1'b0;

            case (state)
                // ------------------------------------------------
                S_IDLE: begin
                    if ((cpu_re | cpu_we) && access_ok && cpu_we) begin
                        // Write hit on E or M: local, silent, no bus
                        // traffic (this IS the point of MESI's E
                        // state, and M was already exclusive).
                        data_r[tag_hit_way_v][addr_index]  <= merge_line(tag_hit_line_v, addr_word, cpu_memop, cpu_wdata, cpu_addr[1:0]);
                        state_r[tag_hit_way_v][addr_index] <= ST_M;
                    end
                    else if ((cpu_re | cpu_we) && !access_ok) begin
                        // Need the bus. Decide the fill way and
                        // whether its current occupant (if any, and
                        // if it's actually a DIFFERENT line) needs a
                        // writeback first.
                        fsm_way   <= tag_hit_v ? tag_hit_way_v : lru_r[addr_index];
                        fsm_index <= addr_index;
                        fsm_tag   <= addr_tag;
                        fsm_we    <= cpu_we;
                        fsm_memop <= cpu_memop;
                        fsm_wdata <= cpu_wdata;
                        fsm_word_off <= {addr_word, cpu_addr[1:0]};

                        if (!tag_hit_v &&
                            (state_r[lru_r[addr_index]][addr_index] == ST_M)) begin
                            // Genuine miss, LRU victim is dirty: writeback first.
                            bus_req_valid <= 1'b1;
                            bus_req_type  <= REQ_WRITEBACK;
                            bus_req_addr  <= {tag_r[lru_r[addr_index]][addr_index], addr_index, {OFFSET_BITS{1'b0}}};
                            bus_req_line  <= data_r[lru_r[addr_index]][addr_index];
                            state         <= S_EVICT;
                        end
                        else begin
                            // Either an upgrade-in-place (tag_hit_v=1,
                            // no eviction needed), or the victim is
                            // clean/invalid (silently droppable).
                            bus_req_valid <= 1'b1;
                            bus_req_type  <= cpu_we ? REQ_RFO : REQ_READ;
                            bus_req_addr  <= {addr_tag, addr_index, {OFFSET_BITS{1'b0}}};
                            state         <= S_MISS_REQ;
                        end
                    end
                end

                // ------------------------------------------------
                S_EVICT: begin
                    if (bus_resp_valid) begin
                        bus_req_valid <= 1'b1;
                        bus_req_type  <= fsm_we ? REQ_RFO : REQ_READ;
                        bus_req_addr  <= {fsm_tag, fsm_index, {OFFSET_BITS{1'b0}}};
                        state         <= S_MISS_REQ;
                    end
                end

                // ------------------------------------------------
                S_MISS_REQ: begin
                    if (bus_resp_valid) begin
                        bus_req_valid <= 1'b0;

                        if (fsm_we) begin
                            // Read-for-ownership done: apply the
                            // pending store on top of the fetched
                            // (pre-store) line before committing it.
                            data_r[fsm_way][fsm_index] <= merge_line(bus_resp_line, fsm_word_off[4:2], fsm_memop, fsm_wdata, fsm_word_off[1:0]);
                            state_r[fsm_way][fsm_index] <= ST_M;
                        end
                        else begin
                            data_r[fsm_way][fsm_index]  <= bus_resp_line;
                            state_r[fsm_way][fsm_index] <= bus_resp_state;
                        end
                        tag_r[fsm_way][fsm_index] <= fsm_tag;
                        lru_r[fsm_index]          <= ~fsm_way;

                        miss_done_pulse <= 1'b1;
                        state           <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase

            // ---- Snoop response (runs every cycle, independent of `state` above) ----
            snoop_ack_valid <= snoop_valid;
            if (snoop_valid) begin
                snoop_ack_hit   <= snoop_hit_v;
                snoop_ack_dirty <= snoop_hit_v && (snoop_hit_state_v == ST_M);
                snoop_ack_line  <= snoop_hit_line_v;
                if (snoop_hit_v) begin
                    if (snoop_type == 1'b0) begin
                        // INVALIDATE
                        state_r[snoop_hit_way_v][snoop_index] <= ST_I;
                    end
                    else begin
                        // DOWNGRADE (M or E -> S); dirty data already
                        // captured into snoop_ack_line above for the
                        // coherence manager to write back / forward.
                        state_r[snoop_hit_way_v][snoop_index] <= ST_S;
                    end
                end
            end
        end
    end

    // Registered miss-resolve pulse doubles as the other half of
    // cpu_valid (see the wire assign above, which only covers hits).
    // Both cannot be true the same cycle (miss_done_pulse only fires
    // from S_MISS_REQ, at which point state==S_IDLE only starts the
    // *next* cycle, and cpu_valid's hit term requires state==S_IDLE
    // this cycle) -- combined with a plain OR below.
    wire cpu_valid_hit  = (state == S_IDLE) && access_ok && (cpu_re | cpu_we);
    assign cpu_valid = cpu_valid_hit | miss_done_pulse;

endmodule
