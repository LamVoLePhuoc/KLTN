module SetAssociativeCache #(
    parameter int ADDR_WIDTH     = 32,
    parameter int CPU_DATA_WIDTH = 32,
    parameter bit READ_ONLY      = 1'b0,
    parameter int LINE_WIDTH     = 256,
    parameter int NUM_SETS       = 512,
    parameter int INDEX_WIDTH    = $clog2(NUM_SETS),
    parameter int LINE_BYTES     = LINE_WIDTH / 8,
    parameter int LINE_BYTE_BITS = $clog2(LINE_BYTES),
    parameter int TAG_WIDTH      = ADDR_WIDTH - INDEX_WIDTH - LINE_BYTE_BITS
) (
    input  wire                      clk,
    input  wire                      reset,

    input  wire [ADDR_WIDTH-1:0]     cpu_addr,
    input  wire                      cpu_read,
    input  wire                      cpu_write,
    input  wire [CPU_DATA_WIDTH-1:0] cpu_wdata,
    output wire [CPU_DATA_WIDTH-1:0] cpu_rdata,
    output wire                      cpu_ready,

    output wire [ADDR_WIDTH-1:0]     mem_req_addr,
    output wire                      mem_req_read,
    output wire                      mem_req_write,
    output wire [LINE_WIDTH-1:0]     mem_req_wdata,
    input  wire [LINE_WIDTH-1:0]     mem_rdata,
    input  wire                      mem_ready,
    output wire                      error_out,

    // Phase-3 coherence snoop-invalidate port. Pulse snoop_en with the
    // address of a line that another core just stored to; if this array
    // holds a (now-stale) copy, SharedCacheController writes it back to
    // memory first if dirty (real MESI: a Modified line must drain
    // before it can be invalidated), then clears its valid bit so the
    // next access re-fetches the fresh line. Tie snoop_en to 0 for
    // caches that don't participate in coherence (the read-only L1
    // I-caches, and the shared L2 itself).
    input  wire                      snoop_en,
    input  wire [ADDR_WIDTH-1:0]     snoop_addr,

    // Phase-3 coherence: pulses once a store's write-through to L2 has
    // actually landed (see SharedCacheController.sv). Tie off/ignore for
    // caches that don't originate coherence traffic (I-caches, L2).
    output wire                      store_committed,
    output wire [ADDR_WIDTH-1:0]     store_committed_addr
);

    timeunit 1ns; timeprecision 1ps;

    wire [INDEX_WIDTH-1:0] tag_index;
    wire [INDEX_WIDTH-1:0] data_index;
    wire [TAG_WIDTH-1:0]   cpu_tag;
    wire [TAG_WIDTH-1:0]   tag_way0;
    wire [TAG_WIDTH-1:0]   tag_way1;
    wire                   valid_way0;
    wire                   valid_way1;
    wire                   dirty_way0;
    wire                   dirty_way1;
    wire [LINE_WIDTH-1:0]  data_way0;
    wire [LINE_WIDTH-1:0]  data_way1;
    wire                   hit_way0;
    wire                   hit_way1;
    wire                   comp_hit;
    wire                   comp_miss;
    wire                   tag_write_enable;
    wire [1:0]             tag_way_select;
    wire [TAG_WIDTH-1:0]   tag_in;
    wire                   valid_in;
    wire                   dirty_in;
    wire                   data_write_enable;
    wire [1:0]             data_way_select;
    wire [LINE_WIDTH-1:0]  data_wdata;
    wire                   tag_error;
    wire                   data_error;
    wire                   comp_error;
    wire                   fsm_error;

    assign cpu_tag   = cpu_addr[ADDR_WIDTH-1 -: TAG_WIDTH];
    assign error_out = tag_error || data_error || comp_error || fsm_error;

    CacheTagArray #(
        .NUM_SETS(NUM_SETS),
        .TAG_WIDTH(TAG_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) tag_array (
        .clk(clk),
        .reset(reset),
        .index(tag_index),
        .write_enable(tag_write_enable),
        .way_select(tag_way_select),
        .tag_in(tag_in),
        .valid_in(valid_in),
        .dirty_in(dirty_in),
        .tag_way0(tag_way0),
        .tag_way1(tag_way1),
        .valid_way0(valid_way0),
        .valid_way1(valid_way1),
        .dirty_way0(dirty_way0),
        .dirty_way1(dirty_way1),
        .error_out(tag_error)
    );

    // Phase-3 coherence: second, independent comparator that checks
    // whatever set `tag_index` currently points at against the tag of
    // the snoop request SharedCacheController is actively servicing
    // (snoop_active_tag). The controller drives tag_index (shared with
    // the normal CPU path) to the snooped line's index while servicing
    // it -- at that moment tag_way0/tag_way1/dirty_way0/dirty_way1 above
    // correctly reflect the *snooped* set, and this comparator tells the
    // controller whether (and in which way) that set holds the line.
    wire [TAG_WIDTH-1:0] snoop_active_tag;
    wire                 snoop_hit_way0;
    wire                 snoop_hit_way1;
    wire                 snoop_comp_error;

    CacheComparator #(
        .TAG_WIDTH(TAG_WIDTH)
    ) snoop_comparator (
        .cpu_tag(snoop_active_tag),
        .tag_way0(tag_way0),
        .tag_way1(tag_way1),
        .valid_way0(valid_way0),
        .valid_way1(valid_way1),
        .hit_way0(snoop_hit_way0),
        .hit_way1(snoop_hit_way1),
        .hit(),
        .miss(),
        .error_out(snoop_comp_error)
    );

    CacheDataArray #(
        .NUM_SETS(NUM_SETS),
        .LINE_WIDTH(LINE_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) data_array (
        .clk(clk),
        .reset(reset),
        .index(data_index),
        .write_enable(data_write_enable),
        .way_select(data_way_select),
        .wdata(data_wdata),
        .data_way0(data_way0),
        .data_way1(data_way1),
        .error_out(data_error)
    );

    CacheComparator #(
        .TAG_WIDTH(TAG_WIDTH)
    ) comparator (
        .cpu_tag(cpu_tag),
        .tag_way0(tag_way0),
        .tag_way1(tag_way1),
        .valid_way0(valid_way0),
        .valid_way1(valid_way1),
        .hit_way0(hit_way0),
        .hit_way1(hit_way1),
        .hit(comp_hit),
        .miss(comp_miss),
        .error_out(comp_error)
    );

    SharedCacheController #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .CPU_DATA_WIDTH(CPU_DATA_WIDTH),
        .READ_ONLY(READ_ONLY),
        .LINE_WIDTH(LINE_WIDTH),
        .NUM_SETS(NUM_SETS),
        .INDEX_WIDTH(INDEX_WIDTH),
        .LINE_BYTES(LINE_BYTES),
        .LINE_BYTE_BITS(LINE_BYTE_BITS),
        .TAG_WIDTH(TAG_WIDTH)
    ) controller (
        .clk(clk),
        .reset(reset),
        .cpu_addr(cpu_addr),
        .cpu_read(cpu_read),
        .cpu_write(cpu_write),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .tag_index(tag_index),
        .tag_way0(tag_way0),
        .tag_way1(tag_way1),
        .valid_way0(valid_way0),
        .valid_way1(valid_way1),
        .dirty_way0(dirty_way0),
        .dirty_way1(dirty_way1),
        .tag_write_enable(tag_write_enable),
        .tag_way_select(tag_way_select),
        .tag_in(tag_in),
        .valid_in(valid_in),
        .dirty_in(dirty_in),
        .tag_error(tag_error),
        .data_index(data_index),
        .data_way0(data_way0),
        .data_way1(data_way1),
        .data_wdata(data_wdata),
        .data_write_enable(data_write_enable),
        .data_way_select(data_way_select),
        .data_error(data_error),
        .hit_way0(hit_way0),
        .hit_way1(hit_way1),
        .comp_hit(comp_hit),
        .comp_error(comp_error),
        .mem_req_addr(mem_req_addr),
        .mem_req_read(mem_req_read),
        .mem_req_write(mem_req_write),
        .mem_req_wdata(mem_req_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .fsm_error(fsm_error),
        .snoop_en(snoop_en),
        .snoop_addr(snoop_addr),
        .snoop_active_tag(snoop_active_tag),
        .snoop_hit_way0(snoop_hit_way0),
        .snoop_hit_way1(snoop_hit_way1),
        .store_committed(store_committed),
        .store_committed_addr(store_committed_addr)
    );

endmodule
