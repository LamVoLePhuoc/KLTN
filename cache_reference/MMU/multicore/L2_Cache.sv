// L2_Cache: shared 512KB L2 (2-way, 8192 sets, 32B lines), full-line
// interface. Sits behind the interconnect; every private L1's miss-fill
// (read) and write-through (write) goes through here on its way to/from
// the DRAM backing store (mem_model256 in simulation).
module L2_Cache (
    input  wire         clk,
    input  wire         reset,

    input  wire [31:0]  cpu_addr,
    input  wire         cpu_read,
    input  wire         cpu_write,
    input  wire [255:0] cpu_wdata,
    output wire [255:0] cpu_rdata,
    output wire          cpu_ready,

    output wire [31:0]  mem_req_addr,
    output wire          mem_req_read,
    output wire          mem_req_write,
    output wire [255:0] mem_req_wdata,
    input  wire [255:0] mem_rdata,
    input  wire          mem_ready
);

    timeunit 1ns; timeprecision 1ps;

    wire [12:0] tag_index, data_index;
    wire [13:0] tag_way0, tag_way1;
    wire        valid_way0, valid_way1, dirty_way0, dirty_way1;
    wire [255:0] data_way0, data_way1;
    wire        hit_way0, hit_way1;
    wire [1:0]  data_way_select;
    wire        data_write_enable;
    wire [255:0] data_wdata;
    wire [13:0] tag_in;
    wire        valid_in, dirty_in;
    wire [1:0]  tag_way_select;
    wire        tag_write_enable;
    wire        tag_error, data_error, comp_hit, comp_miss, comp_error, fsm_error;

    L2_TagArray tag_array (
        .clk(clk), .reset(reset), .index(tag_index), .write_enable(tag_write_enable),
        .way_select(tag_way_select), .tag_in(tag_in), .valid_in(valid_in), .dirty_in(dirty_in),
        .tag_way0(tag_way0), .tag_way1(tag_way1), .valid_way0(valid_way0), .valid_way1(valid_way1),
        .dirty_way0(dirty_way0), .dirty_way1(dirty_way1), .error_out(tag_error)
    );

    L2_DataArray data_array (
        .clk(clk), .reset(reset), .index(data_index), .write_enable(data_write_enable),
        .way_select(data_way_select), .wdata(data_wdata), .data_way0(data_way0), .data_way1(data_way1),
        .error_out(data_error)
    );

    Comparator #(.TAG_WIDTH(14)) comp (
        .cpu_tag(cpu_addr[31:18]), .tag_way0(tag_way0), .tag_way1(tag_way1),
        .valid_way0(valid_way0), .valid_way1(valid_way1),
        .hit_way0(hit_way0), .hit_way1(hit_way1), .hit(comp_hit), .miss(comp_miss), .error_out(comp_error)
    );

    L2_CacheController ctrl (
        .clk(clk), .reset(reset),
        .cpu_addr(cpu_addr), .cpu_read(cpu_read), .cpu_write(cpu_write),
        .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata), .cpu_ready(cpu_ready),
        .tag_index(tag_index), .tag_way0(tag_way0), .tag_way1(tag_way1),
        .valid_way0(valid_way0), .valid_way1(valid_way1), .dirty_way0(dirty_way0), .dirty_way1(dirty_way1),
        .tag_write_enable(tag_write_enable), .tag_way_select(tag_way_select), .tag_in(tag_in),
        .valid_in(valid_in), .dirty_in(dirty_in), .tag_error(tag_error),
        .data_index(data_index), .data_way0(data_way0), .data_way1(data_way1),
        .data_wdata(data_wdata), .data_write_enable(data_write_enable), .data_way_select(data_way_select),
        .data_error(data_error), .hit_way0(hit_way0), .hit_way1(hit_way1),
        .comp_hit(comp_hit), .comp_miss(comp_miss), .comp_error(comp_error),
        .mem_req_addr(mem_req_addr), .mem_req_read(mem_req_read), .mem_req_write(mem_req_write),
        .mem_req_wdata(mem_req_wdata), .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .fsm_error(fsm_error)
    );

endmodule
