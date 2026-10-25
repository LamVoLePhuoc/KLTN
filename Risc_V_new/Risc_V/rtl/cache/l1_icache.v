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
    output wire         flush_busy,
    output reg          flush_done,

    // ---- Core side (PIPT, always-active fetch, matches fetch_stage.v) ----
    input  wire [31:0]  cpu_addr,
    output wire [31:0]  cpu_rdata,
    output wire         cpu_valid,   // 1 exactly when cpu_rdata is valid for cpu_addr this cycle
    output wire         cpu_error,   // asserted with cpu_valid when the line fill failed

    // ---- Bus side (line-fill request to the coherence/L2 subsystem) ----
    output reg               bus_req_valid,
    input  wire              bus_req_ready,
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
    // Synchronous single-port BRAMs, one data and one metadata RAM per way.
    // This adds one lookup cycle but prevents Vivado from expanding the
    // former asynchronous 32-KB array into a very large LUT network.
    // ------------------------------------------------------
    wire [LINE_BITS-1:0] way0_line;
    wire [LINE_BITS-1:0] way1_line;
    wire [TAG_BITS-1:0] way0_tag;
    wire [TAG_BITS-1:0] way1_tag;
    reg [SETS-1:0] valid_way0_r;
    reg [SETS-1:0] valid_way1_r;
    (* ram_style = "distributed" *) reg lru_r [0:SETS-1];

    reg [31:0] lookup_addr;
    reg        lookup_valid;
    wire [TAG_BITS-1:0] lookup_tag = lookup_addr[31:32-TAG_BITS];
    wire [INDEX_BITS-1:0] lookup_index =
        lookup_addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    wire [2:0] lookup_word = lookup_addr[4:2];
    wire lookup_ready = lookup_valid && (lookup_addr == cpu_addr);

    reg flush_pending;

    assign flush_busy = flush_pending | flush;

    reg hit_v;
    reg [LINE_BITS-1:0] hit_line_v;
    always @(*) begin
        hit_v      = 1'b0;
        hit_line_v = {LINE_BITS{1'b0}};
        if (valid_way0_r[lookup_index] && (way0_tag == lookup_tag)) begin
            hit_v      = 1'b1;
            hit_line_v = way0_line;
        end
        if (valid_way1_r[lookup_index] && (way1_tag == lookup_tag)) begin
            hit_v      = 1'b1;
            hit_line_v = way1_line;
        end
    end

    wire [31:0] hit_word = hit_line_v[lookup_word*32 +: 32];

    // ------------------------------------------------------
    // Miss FSM (blocking, single outstanding request)
    // ------------------------------------------------------
    localparam S_IDLE = 1'b0, S_MISS = 1'b1;
    reg state;
    reg [INDEX_BITS-1:0] miss_index;
    reg [TAG_BITS-1:0]   miss_tag;
    reg                  miss_way;
    reg [2:0]            miss_word;
    reg                  fill_done_pulse;
    reg [31:0]           fill_return_word;

    wire miss_error = (state == S_MISS) && bus_resp_valid &&
                      bus_resp_error && !flush_busy;
    assign cpu_valid = !flush_busy &&
                       (((state == S_IDLE) && lookup_ready && hit_v) |
                        fill_done_pulse | miss_error);
    assign cpu_error = miss_error;
    assign cpu_rdata = fill_done_pulse ? fill_return_word : hit_word;

    wire fill_write_en = (state == S_MISS) && bus_resp_valid &&
                         !bus_resp_error && !flush_pending && !flush;
    wire victim_way = !valid_way0_r[lookup_index] ? 1'b0 :
                      !valid_way1_r[lookup_index] ? 1'b1 : lru_r[lookup_index];
    wire [INDEX_BITS-1:0] ram_index = fill_write_en ? miss_index : addr_index;

    cache_sp_ram #(.WIDTH(LINE_BITS), .ADDR_WIDTH(INDEX_BITS)) u_data_way0 (
        .clk(clk), .we(fill_write_en && !miss_way), .addr(ram_index),
        .din(bus_resp_line), .dout(way0_line)
    );
    cache_sp_ram #(.WIDTH(LINE_BITS), .ADDR_WIDTH(INDEX_BITS)) u_data_way1 (
        .clk(clk), .we(fill_write_en && miss_way), .addr(ram_index),
        .din(bus_resp_line), .dout(way1_line)
    );
    cache_sp_ram #(.WIDTH(TAG_BITS), .ADDR_WIDTH(INDEX_BITS)) u_meta_way0 (
        .clk(clk), .we(fill_write_en && !miss_way),
        .addr(ram_index), .din(miss_tag), .dout(way0_tag)
    );
    cache_sp_ram #(.WIDTH(TAG_BITS), .ADDR_WIDTH(INDEX_BITS)) u_meta_way1 (
        .clk(clk), .we(fill_write_en && miss_way),
        .addr(ram_index), .din(miss_tag), .dout(way1_tag)
    );

    // Associate the registered BRAM outputs with the fetch address sampled
    // on the same edge.  During initialization no lookup may complete.
    always @(posedge clk) begin
        if (rst || flush) begin
            lookup_addr  <= 32'b0;
            lookup_valid <= 1'b0;
        end
        else begin
            lookup_addr  <= cpu_addr;
            lookup_valid <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state         <= S_IDLE;
            bus_req_valid <= 1'b0;
            bus_req_addr  <= 32'b0;
            flush_pending <= 1'b0;
            flush_done    <= 1'b0;
            fill_done_pulse <= 1'b0;
            fill_return_word <= 32'b0;
            valid_way0_r  <= {SETS{1'b0}};
            valid_way1_r  <= {SETS{1'b0}};
        end
        else begin
            flush_done <= 1'b0;
            fill_done_pulse <= 1'b0;
            if (bus_req_valid && bus_req_ready)
                bus_req_valid <= 1'b0;

            case (state)
                    S_IDLE: begin
                        if (flush_pending || flush) begin
                            flush_pending <= 1'b0;
                            valid_way0_r  <= {SETS{1'b0}};
                            valid_way1_r  <= {SETS{1'b0}};
                            bus_req_valid <= 1'b0;
                            flush_done    <= 1'b1;
                        end
                        else if (!fill_done_pulse && lookup_ready && !hit_v) begin
                            miss_index    <= lookup_index;
                            miss_tag      <= lookup_tag;
                            miss_way      <= victim_way;
                            miss_word     <= lookup_word;
                            bus_req_valid <= 1'b1;
                            bus_req_addr  <= {lookup_tag, lookup_index,
                                              {OFFSET_BITS{1'b0}}};
                            state         <= S_MISS;
                        end
                    end

                    S_MISS: begin
                        if (flush)
                            flush_pending <= 1'b1;
                        if (bus_resp_valid) begin
                            bus_req_valid <= 1'b0;
                            if (fill_write_en) begin
                                lru_r[miss_index] <= ~miss_way;
                                if (miss_way)
                                    valid_way1_r[miss_index] <= 1'b1;
                                else
                                    valid_way0_r[miss_index] <= 1'b1;
                                fill_return_word <= bus_resp_line[miss_word*32 +: 32];
                                fill_done_pulse  <= 1'b1;
                            end
                            if (flush_pending || flush) begin
                                valid_way0_r <= {SETS{1'b0}};
                                valid_way1_r <= {SETS{1'b0}};
                                flush_pending <= 1'b0;
                                flush_done <= 1'b1;
                            end
                            state <= S_IDLE;
                        end
                    end

                    default: state <= S_IDLE;
            endcase
        end
    end

endmodule

// Single-port cache RAM. Vivado synthesis uses the official XPM so the
// intended BRAM implementation is explicit; simulation uses an equivalent
// read-first behavioural model and needs no vendor library.
module cache_sp_ram #(
    parameter integer WIDTH = 256,
    parameter integer ADDR_WIDTH = 9
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
