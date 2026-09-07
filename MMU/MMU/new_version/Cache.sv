module Cache #(
    parameter int CPU_DATA_WIDTH = 32,
    parameter bit READ_ONLY      = 1'b0,
    parameter int LINE_WIDTH     = 256,
    parameter int NUM_SETS       = 32,
    parameter int NUM_WAYS       = 2,
    parameter int TAG_WIDTH      = 22,
    parameter int INDEX_WIDTH    = $clog2(NUM_SETS)
) (
    input  wire                      clk,
    input  wire                      reset,

    input  wire [31:0]               cpu_addr,
    input  wire                      cpu_read,
    input  wire                      cpu_write,
    input  wire [CPU_DATA_WIDTH-1:0] cpu_wdata,
    output wire [CPU_DATA_WIDTH-1:0] cpu_rdata,
    output wire                      cpu_ready,

    output wire [31:0]               mem_req_addr,
    output wire                      mem_req_read,
    output wire                      mem_req_write,
    output wire [LINE_WIDTH-1:0]     mem_req_wdata,
    input  wire [LINE_WIDTH-1:0]     mem_rdata,
    input  wire                      mem_ready
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
    wire [LINE_WIDTH-1:0]  data_wdata;
    wire                   data_write_enable;
    wire [1:0]             data_way_select;
    wire [TAG_WIDTH-1:0]   tag_in;
    wire                   valid_in;
    wire                   dirty_in;
    wire                   tag_write_enable;
    wire [1:0]             tag_way_select;
    wire                   tag_error;
    wire                   data_error;
    wire                   comp_error;
    wire                   fsm_error;

    assign cpu_tag = cpu_addr[31:10];

    TagArray #(
        .NUM_SETS(NUM_SETS),
        .NUM_WAYS(NUM_WAYS),
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

    DataArray #(
        .NUM_SETS(NUM_SETS),
        .NUM_WAYS(NUM_WAYS),
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

    Comparator #(
        .TAG_WIDTH(TAG_WIDTH)
    ) comp (
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

    CacheController #(
        .CPU_DATA_WIDTH(CPU_DATA_WIDTH),
        .READ_ONLY(READ_ONLY),
        .LINE_WIDTH(LINE_WIDTH),
        .NUM_SETS(NUM_SETS),
        .TAG_WIDTH(TAG_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) cache_ctrl (
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
        .comp_miss(comp_miss),
        .comp_error(comp_error),
        .mem_req_addr(mem_req_addr),
        .mem_req_read(mem_req_read),
        .mem_req_write(mem_req_write),
        .mem_req_wdata(mem_req_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready),
        .fsm_error(fsm_error)
    );

endmodule
