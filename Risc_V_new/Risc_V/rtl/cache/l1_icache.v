`timescale 1ns / 1ps

// ============================================================
// l1_icache
//
// Private, per-core L1 instruction cache. PIPT (sits downstream of
// the MMU -- cpu_addr is already a physical address, matching where
// mmu_core_wrapper.v's own header comment said an L1 cache belongs:
// "between the core's pipeline (VA) and whatever sits downstream on
// the memory side"). Sized per the FINAL architecture decision
// (Risc_V_new/README.md mục 4 -- 32KB I$ separate from 32KB D$, not
// address_mapping's earlier "16KB shared" placeholder number):
//   32KB, 2-way set-associative, line = 32B (8 words)
//   offset = 5b, index = 9b (512 sets), tag = 18b
//
// Read-only, blocking (single outstanding miss -- matches the core,
// which has no mechanism for more than one in-flight memory access
// at a time anyway, see Stall_Core_External throughout this repo).
//
// Deliberately NOT coherence-participating: no MSI state and no
// snoop port.  Instruction/data synchronization is instead explicit:
// core_l1_wrapper turns architectural FENCE.I into an ordered D$
// clean followed by this cache's whole-cache invalidation while the
// core is stalled.  External agents such as DMA must use the same
// Cache_Flush hook after modifying executable memory.  Keeping I$
// outside the directory avoids treating read-only instruction copies
// as D$ sharers while still providing the required synchronization
// point for self-modifying/generated code.
// ============================================================
// NOTE: hardcoded to WAYS=2 (matches address_mapping exactly) -- the
// way index / LRU bit below are single bits, not a generic log2(WAYS)
// width, so this is not a drop-in "set WAYS=4" parametrization.
module l1_icache #(
    parameter INDEX_BITS  = 9,     // 512 sets (32KB, 2-way, 32B line)
    parameter LINE_WORDS  = 8      // 32B line = 8 x 32-bit words
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         flush,     // pulse: invalidate the whole cache

    // ---- Core side (PIPT, always-active fetch, matches fetch_stage.v) ----
    input  wire [31:0]  cpu_addr,
    output wire [31:0]  cpu_rdata,
    output wire         cpu_valid,   // 1 exactly when cpu_rdata is valid for cpu_addr this cycle
    output wire         cpu_error,   // asserted with cpu_valid when the line fill failed

    // ---- Bus side (line-fill request to the coherence/L2 subsystem) ----
    output reg               bus_req_valid,
    output reg  [31:0]       bus_req_addr,   // line-aligned (offset bits = 0)
    input  wire              bus_resp_valid,
    input  wire              bus_resp_error,
    input  wire [LINE_WORDS*32-1:0] bus_resp_line // word 0 in bits[31:0], word 1 in [63:32], ...
);

    localparam WAYS         = 2;
    localparam OFFSET_BITS  = 5;               // 32B line
    localparam TAG_BITS     = 32 - INDEX_BITS - OFFSET_BITS;
    localparam SETS         = (1 << INDEX_BITS);
    localparam LINE_BITS    = LINE_WORDS * 32;

    wire [TAG_BITS-1:0]   addr_tag    = cpu_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] addr_index  = cpu_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    wire [2:0]            addr_word   = cpu_addr[4:2]; // word within the 8-word line

    // ------------------------------------------------------
    // Storage: WAYS x SETS tag/valid, WAYS x SETS x LINE_BITS data
    // ------------------------------------------------------
    reg                    valid_r [0:WAYS-1][0:SETS-1];
    reg [TAG_BITS-1:0]     tag_r   [0:WAYS-1][0:SETS-1];
    reg [LINE_BITS-1:0]    data_r  [0:WAYS-1][0:SETS-1];
    reg                    lru_r   [0:SETS-1]; // 1 bit/set: which way to evict next (round-robin/PLRU-1)

    integer w, s;

    // ------------------------------------------------------
    // Lookup (combinational)
    // ------------------------------------------------------
    reg        hit_v;
    reg [LINE_BITS-1:0] hit_line_v;

    always @(*) begin
        hit_v      = 1'b0;
        hit_line_v = {LINE_BITS{1'b0}};
        for (w = 0; w < WAYS; w = w + 1) begin
            if (valid_r[w][addr_index] && (tag_r[w][addr_index] == addr_tag)) begin
                hit_v      = 1'b1;
                hit_line_v = data_r[w][addr_index];
            end
        end
    end

    wire [31:0] hit_word = hit_line_v[addr_word*32 +: 32];

    // ------------------------------------------------------
    // Miss FSM (blocking, single outstanding request)
    // ------------------------------------------------------
    localparam S_IDLE = 1'b0, S_MISS = 1'b1;
    reg  state;
    reg  [INDEX_BITS-1:0] miss_index;
    reg  [TAG_BITS-1:0]   miss_tag;
    reg                   miss_way; // which way we are about to fill

    // A failed fill completes the held fetch without installing a cache
    // line.  Keeping the error combinational with the response lets the
    // core capture the access-fault tag on the same edge that terminates
    // the miss; the following trap redirect prevents a retry of the old PC.
    wire miss_error = (state == S_MISS) && bus_resp_valid && bus_resp_error;
    assign cpu_valid = ((state == S_IDLE) && hit_v) | miss_error;
    assign cpu_error = miss_error;
    assign cpu_rdata = hit_word;

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            bus_req_valid <= 1'b0;
            bus_req_addr  <= 32'b0;
            for (s = 0; s < SETS; s = s + 1) begin
                lru_r[s] <= 1'b0;
                for (w = 0; w < WAYS; w = w + 1) begin
                    valid_r[w][s] <= 1'b0;
                end
            end
        end
        else if (flush) begin
            state         <= S_IDLE;
            bus_req_valid <= 1'b0;
            for (s = 0; s < SETS; s = s + 1) begin
                for (w = 0; w < WAYS; w = w + 1) begin
                    valid_r[w][s] <= 1'b0;
                end
            end
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (!hit_v) begin
                        miss_index    <= addr_index;
                        miss_tag      <= addr_tag;
                        miss_way      <= lru_r[addr_index];
                        bus_req_valid <= 1'b1;
                        bus_req_addr  <= {addr_tag, addr_index, {OFFSET_BITS{1'b0}}};
                        state         <= S_MISS;
                    end
                end

                S_MISS: begin
                    if (bus_resp_valid) begin
                        bus_req_valid <= 1'b0;
                        if (!bus_resp_error) begin
                            valid_r[miss_way][miss_index] <= 1'b1;
                            tag_r[miss_way][miss_index]   <= miss_tag;
                            data_r[miss_way][miss_index]  <= bus_resp_line;
                            lru_r[miss_index]             <= ~miss_way; // evict the other way next time
                        end
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
