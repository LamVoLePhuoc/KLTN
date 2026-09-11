module SharedCacheController #(
    parameter int ADDR_WIDTH     = 32,
    parameter int CPU_DATA_WIDTH = 32,
    parameter bit READ_ONLY      = 1'b0,
    parameter int LINE_WIDTH     = 256,
    parameter int NUM_SETS       = 512,
    parameter int INDEX_WIDTH    = $clog2(NUM_SETS),
    parameter int LINE_BYTES     = LINE_WIDTH / 8,
    parameter int LINE_BYTE_BITS = $clog2(LINE_BYTES),
    parameter int WORDS_PER_LINE = LINE_WIDTH / CPU_DATA_WIDTH,
    parameter int OFFSET_BITS    = (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE),
    parameter int TAG_WIDTH      = ADDR_WIDTH - INDEX_WIDTH - LINE_BYTE_BITS
) (
    input  wire                      clk,
    input  wire                      reset,

    input  wire [ADDR_WIDTH-1:0]     cpu_addr,
    input  wire                      cpu_read,
    input  wire                      cpu_write,
    input  wire [CPU_DATA_WIDTH-1:0] cpu_wdata,
    output reg  [CPU_DATA_WIDTH-1:0] cpu_rdata,
    output reg                       cpu_ready,

    output wire [INDEX_WIDTH-1:0]    tag_index,
    input  wire [TAG_WIDTH-1:0]      tag_way0,
    input  wire [TAG_WIDTH-1:0]      tag_way1,
    input  wire                      valid_way0,
    input  wire                      valid_way1,
    input  wire                      dirty_way0,
    input  wire                      dirty_way1,
    output reg                       tag_write_enable,
    output reg  [1:0]                tag_way_select,
    output reg  [TAG_WIDTH-1:0]      tag_in,
    output reg                       valid_in,
    output reg                       dirty_in,
    input  wire                      tag_error,

    output wire [INDEX_WIDTH-1:0]    data_index,
    input  wire [LINE_WIDTH-1:0]     data_way0,
    input  wire [LINE_WIDTH-1:0]     data_way1,
    output reg  [LINE_WIDTH-1:0]     data_wdata,
    output reg                       data_write_enable,
    output reg  [1:0]                data_way_select,
    input  wire                      data_error,

    input  wire                      hit_way0,
    input  wire                      hit_way1,
    input  wire                      comp_hit,
    input  wire                      comp_error,

    output reg  [ADDR_WIDTH-1:0]     mem_req_addr,
    output reg                       mem_req_read,
    output reg                       mem_req_write,
    output reg  [LINE_WIDTH-1:0]     mem_req_wdata,
    input  wire [LINE_WIDTH-1:0]     mem_rdata,
    input  wire                      mem_ready,
    output reg                       fsm_error,

    // Phase-3 coherence snoop-invalidate port (see SetAssociativeCache.sv).
    input  wire                      snoop_en,
    input  wire [ADDR_WIDTH-1:0]     snoop_addr,
    output wire [TAG_WIDTH-1:0]      snoop_active_tag,
    input  wire                      snoop_hit_way0,
    input  wire                      snoop_hit_way1,

    // Phase-3 coherence: pulses for exactly one cycle at the moment a
    // store's write-through to L2 actually completes (WRITE_THROUGH's
    // mem_ready), i.e. the instant the new value becomes globally
    // visible. CoherenceManager should broadcast the invalidate from
    // *this* event, not from the raw cpu_write request -- broadcasting
    // any earlier (e.g. off cpu_write directly) would let another core
    // get invalidated and re-fetch from L2 before the write-through has
    // actually landed there, racing back to the exact stale-read bug
    // this whole coherence path exists to prevent.
    output wire                      store_committed,
    output wire [ADDR_WIDTH-1:0]     store_committed_addr
);

    timeunit 1ns; timeprecision 1ps;

    localparam logic [3:0] IDLE          = 4'd0;
    localparam logic [3:0] WRITE_BACK    = 4'd1;
    localparam logic [3:0] REFILL        = 4'd2;
    localparam logic [3:0] RESPOND       = 4'd3;
    localparam logic [3:0] STORE_MISS    = 4'd4;
    localparam logic [3:0] SNOOP_CHECK   = 4'd5;
    localparam logic [3:0] SNOOP_WB      = 4'd6;
    localparam logic [3:0] SNOOP_INVAL   = 4'd7;
    localparam logic [3:0] WRITE_THROUGH = 4'd8;

    localparam int INDEX_LSB = LINE_BYTE_BITS;
    localparam int INDEX_MSB = INDEX_LSB + INDEX_WIDTH - 1;

    reg [3:0] state, next_state;
    reg       lru [0:NUM_SETS-1];
    reg [LINE_WIDTH-1:0] fill_line;

    // Write-through payload latch: captured at the moment a store
    // commits into L1 (hit in IDLE, or STORE_MISS), then drained to L2
    // from WRITE_THROUGH across as many cycles as the memory interface
    // needs (mem_req_addr/wdata must stay stable while mem_req_write is
    // asserted, so we can't keep reading live cpu_addr/cpu_wdata -- the
    // CPU may already be issuing its next request by the time this
    // drains). This is what keeps L2 authoritative immediately after
    // every store, which is what makes plain invalidate-only coherence
    // correct for the producer/consumer pattern (see CoherenceManager.sv
    // and SNOOP_CHECK/SNOOP_INVAL below): a consumer that gets
    // invalidated and then re-reads is guaranteed to find the fresh
    // value already at L2, without needing a read-side snoop/probe of
    // the producer's L1.
    reg [ADDR_WIDTH-1:0]  wt_addr;
    reg [LINE_WIDTH-1:0]  wt_data;

    // Phase-3 coherence: latch of the most recently received (and not
    // yet fully serviced) snoop request. Snoops are only actually acted
    // on from IDLE (see SNOOP_CHECK below), but the latch below captures
    // snoop_en regardless of what state we're in, so a snoop pulse that
    // arrives while we're mid-transaction is not lost -- it's serviced
    // (with bounded extra latency) as soon as we return to IDLE. Only
    // one snoop can be outstanding at a time; if a second snoop_en pulse
    // arrives while one is already pending/in-service, it is dropped --
    // acceptable here because CoherenceManager's broadcast-invalidate
    // keeps re-asserting snoop_en for the entire duration of the
    // originating store (see CoherenceManager.sv), so a dropped pulse
    // is almost always followed by another one for the same address.
    reg                   snoop_pending;
    reg [ADDR_WIDTH-1:0]  snoop_addr_latched;

    wire is_snoop_service;
    wire [INDEX_WIDTH-1:0] snoop_index_latched;

    assign is_snoop_service   = (state == SNOOP_CHECK) || (state == SNOOP_WB) || (state == SNOOP_INVAL);
    assign snoop_index_latched = snoop_addr_latched[INDEX_MSB:INDEX_LSB];
    assign snoop_active_tag    = snoop_addr_latched[ADDR_WIDTH-1 -: TAG_WIDTH];

    assign store_committed      = (state == WRITE_THROUGH) && mem_ready;
    assign store_committed_addr = wt_addr;

    wire [TAG_WIDTH-1:0] cpu_tag;
    wire [OFFSET_BITS-1:0] word_offset;
    wire replace_way;
    wire replace_way_eff;
    wire [LINE_WIDTH-1:0] hit_line;
    wire [ADDR_WIDTH-1:0] line_addr;

    assign cpu_tag        = cpu_addr[ADDR_WIDTH-1 -: TAG_WIDTH];
    // tag_index/data_index are normally driven by the CPU-side address,
    // but while a snoop is being serviced (SNOOP_CHECK/SNOOP_WB/
    // SNOOP_INVAL) they're redirected to the snooped line's index so the
    // (shared, single-port) tag/data arrays expose that line's state to
    // this controller instead.
    assign tag_index      = is_snoop_service ? snoop_index_latched : cpu_addr[INDEX_MSB:INDEX_LSB];
    assign data_index     = tag_index;
    assign word_offset    = (WORDS_PER_LINE <= 1) ? '0 : cpu_addr[LINE_BYTE_BITS-1 -: OFFSET_BITS];
    assign replace_way    = lru[tag_index];
    assign replace_way_eff = (!valid_way0) ? 1'b0 : (!valid_way1) ? 1'b1 : replace_way;
    assign hit_line       = hit_way0 ? data_way0 : data_way1;
    assign line_addr      = {cpu_addr[ADDR_WIDTH-1:LINE_BYTE_BITS], {LINE_BYTE_BITS{1'b0}}};

    function automatic [CPU_DATA_WIDTH-1:0] select_word(
        input [LINE_WIDTH-1:0] line,
        input [OFFSET_BITS-1:0] offset
    );
        select_word = line[LINE_WIDTH-1 - (offset * CPU_DATA_WIDTH) -: CPU_DATA_WIDTH];
    endfunction

    function automatic [LINE_WIDTH-1:0] patch_word(
        input [LINE_WIDTH-1:0] line,
        input [OFFSET_BITS-1:0] offset,
        input [CPU_DATA_WIDTH-1:0] word
    );
        patch_word = line;
        patch_word[LINE_WIDTH-1 - (offset * CPU_DATA_WIDTH) -: CPU_DATA_WIDTH] = word;
    endfunction

    function automatic [ADDR_WIDTH-1:0] victim_addr(
        input [TAG_WIDTH-1:0] victim_tag
    );
        victim_addr = {victim_tag, data_index, {LINE_BYTE_BITS{1'b0}}};
    endfunction

    integer i;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            fill_line <= '0;
            snoop_pending <= 1'b0;
            snoop_addr_latched <= '0;
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                lru[i] <= 1'b0;
            end
        end else begin
            state <= next_state;

            if (mem_ready && state == REFILL) begin
                fill_line <= mem_rdata;
            end

            if (comp_hit && state == IDLE && !snoop_pending) begin
                lru[tag_index] <= hit_way0 ? 1'b1 : 1'b0;
            end else if ((state == RESPOND || state == STORE_MISS) && cpu_ready) begin
                lru[tag_index] <= replace_way_eff ? 1'b0 : 1'b1;
            end

            // Latch the write-through payload at the exact cycle a store
            // commits, so WRITE_THROUGH can drain it to L2 independently
            // of whatever the CPU does next.
            if (state == IDLE && !snoop_pending && cpu_write && !READ_ONLY && comp_hit) begin
                wt_addr <= line_addr;
                wt_data <= patch_word(hit_line, word_offset, cpu_wdata);
            end else if (state == STORE_MISS) begin
                wt_addr <= line_addr;
                wt_data <= patch_word(fill_line, word_offset, cpu_wdata);
            end

            // Phase-3 coherence: latch/clear the pending-snoop flag. A
            // snoop is considered "finished" once SNOOP_CHECK finds
            // nothing to do, or once SNOOP_INVAL has just cleared the
            // matching line's valid bit; from either of those points a
            // fresh snoop_en pulse is immediately re-latchable in the
            // same cycle so back-to-back snoops aren't stalled an extra
            // cycle waiting to pass through IDLE.
            if ((state == SNOOP_CHECK && !(snoop_hit_way0 || snoop_hit_way1)) ||
                (state == SNOOP_INVAL)) begin
                if (snoop_en) begin
                    snoop_pending      <= 1'b1;
                    snoop_addr_latched <= snoop_addr;
                end else begin
                    snoop_pending <= 1'b0;
                end
            end else if (snoop_en && !snoop_pending) begin
                snoop_pending      <= 1'b1;
                snoop_addr_latched <= snoop_addr;
            end
        end
    end

    always_comb begin
        next_state        = state;
        cpu_ready         = 1'b0;
        cpu_rdata         = '0;
        tag_write_enable  = 1'b0;
        tag_way_select    = 2'b00;
        tag_in            = cpu_tag;
        valid_in          = 1'b0;
        dirty_in          = 1'b0;
        data_write_enable = 1'b0;
        data_way_select   = 2'b00;
        data_wdata        = '0;
        mem_req_addr      = '0;
        mem_req_read      = 1'b0;
        mem_req_write     = 1'b0;
        mem_req_wdata     = '0;
        fsm_error         = tag_error || data_error || comp_error;

        unique case (state)
            IDLE: begin
                if (snoop_pending) begin
                    // Coherence takes priority over a new CPU request:
                    // service the pending snoop first (tag_index/data_index
                    // are already redirected to the snooped set via
                    // is_snoop_service once we enter SNOOP_CHECK). Any
                    // pending cpu_read/cpu_write is simply deferred --
                    // cpu_ready stays 0 this cycle, so the requesting CPU
                    // keeps holding its request until we return to IDLE.
                    next_state = SNOOP_CHECK;
                end else if (cpu_read || (cpu_write && !READ_ONLY)) begin
                    if (comp_hit) begin
                        if (cpu_read) begin
                            cpu_rdata = select_word(hit_line, word_offset);
                            cpu_ready = 1'b1;
                        end else begin
                            data_way_select   = hit_way0 ? 2'b01 : 2'b10;
                            data_wdata        = patch_word(hit_line, word_offset, cpu_wdata);
                            data_write_enable = 1'b1;
                            tag_write_enable  = 1'b1;
                            tag_way_select    = data_way_select;
                            valid_in          = 1'b1;
                            // Write-through: the line is synced to L2 via
                            // WRITE_THROUGH below in the same transaction,
                            // so it's never actually "dirty" (differing
                            // from L2) at any point another core could
                            // observe it -- mark it clean, not dirty.
                            // (Critical: if this were left dirty, a later
                            // snoop-invalidate of this line would trigger
                            // SNOOP_WB and write this core's *old* copy
                            // back to L2, potentially clobbering a newer
                            // value some other core wrote in the meantime.)
                            dirty_in          = 1'b0;
                            cpu_ready         = 1'b1;
                            // Write-through: the CPU is unblocked
                            // immediately (its own L1 already has the
                            // new value), but the controller now drains
                            // the same value to L2 via WRITE_THROUGH
                            // before it will accept a new CPU request.
                            next_state        = WRITE_THROUGH;
                        end
                    end else if (!READ_ONLY && ((dirty_way0 && !replace_way_eff) || (dirty_way1 && replace_way_eff))) begin
                        next_state = WRITE_BACK;
                    end else begin
                        mem_req_addr = line_addr;
                        mem_req_read = 1'b1;
                        next_state   = REFILL;
                    end
                end
            end

            WRITE_BACK: begin
                mem_req_addr  = replace_way_eff ? victim_addr(tag_way1) : victim_addr(tag_way0);
                mem_req_wdata = replace_way_eff ? data_way1 : data_way0;
                mem_req_write = 1'b1;
                if (mem_ready) begin
                    mem_req_addr = line_addr;
                    mem_req_read = 1'b1;
                    next_state   = REFILL;
                end
            end

            REFILL: begin
                mem_req_addr = line_addr;
                mem_req_read = 1'b1;
                if (mem_ready) begin
                    data_way_select   = replace_way_eff ? 2'b10 : 2'b01;
                    data_wdata        = mem_rdata;
                    data_write_enable = 1'b1;
                    next_state        = cpu_write && !READ_ONLY ? STORE_MISS : RESPOND;
                end
            end

            RESPOND: begin
                cpu_rdata        = select_word(fill_line, word_offset);
                cpu_ready        = 1'b1;
                tag_write_enable = 1'b1;
                tag_way_select   = replace_way_eff ? 2'b10 : 2'b01;
                valid_in         = 1'b1;
                dirty_in         = 1'b0;
                next_state       = IDLE;
            end

            STORE_MISS: begin
                data_way_select   = replace_way_eff ? 2'b10 : 2'b01;
                data_wdata        = patch_word(fill_line, word_offset, cpu_wdata);
                data_write_enable = 1'b1;
                tag_write_enable  = 1'b1;
                tag_way_select    = data_way_select;
                valid_in          = 1'b1;
                // Write-through: see the identical comment in the
                // store-hit branch above -- this line is synced to L2 by
                // WRITE_THROUGH before any other core can observe it, so
                // it must be marked clean, not dirty.
                dirty_in          = 1'b0;
                cpu_ready         = 1'b1;
                // Write-through: same reasoning as the store-hit case
                // above -- drain to L2 via WRITE_THROUGH before IDLE.
                next_state        = WRITE_THROUGH;
            end

            WRITE_THROUGH: begin
                mem_req_addr  = wt_addr;
                mem_req_wdata = wt_data;
                mem_req_write = 1'b1;
                if (mem_ready) begin
                    next_state = IDLE;
                end
            end

            SNOOP_CHECK: begin
                // tag_index/data_index are redirected (is_snoop_service)
                // to snoop_index_latched, so tag_way0/1, valid_way0/1,
                // dirty_way0/1 and snoop_hit_way0/1 all reflect the
                // snooped set combinationally this same cycle.
                if (snoop_hit_way0 && dirty_way0) begin
                    next_state = SNOOP_WB;
                end else if (snoop_hit_way1 && dirty_way1) begin
                    next_state = SNOOP_WB;
                end else if (snoop_hit_way0 || snoop_hit_way1) begin
                    next_state = SNOOP_INVAL;
                end else begin
                    // Not cached here (or already invalid) -- nothing to do.
                    next_state = IDLE;
                end
            end

            SNOOP_WB: begin
                // Real MESI: a Modified (dirty) line must drain back to
                // memory before it can be invalidated, so the requesting
                // core's subsequent L2 read observes this core's
                // up-to-date data instead of stale L2/DRAM content.
                mem_req_addr  = snoop_hit_way0 ? victim_addr(tag_way0) : victim_addr(tag_way1);
                mem_req_wdata = snoop_hit_way0 ? data_way0 : data_way1;
                mem_req_write = 1'b1;
                if (mem_ready) begin
                    next_state = SNOOP_INVAL;
                end
            end

            SNOOP_INVAL: begin
                tag_write_enable = 1'b1;
                tag_way_select   = snoop_hit_way0 ? 2'b01 : 2'b10;
                tag_in           = snoop_hit_way0 ? tag_way0 : tag_way1;
                valid_in         = 1'b0;
                dirty_in         = 1'b0;
                next_state       = IDLE;
            end

            default: begin
                fsm_error  = 1'b1;
                next_state = IDLE;
            end
        endcase
    end

endmodule
