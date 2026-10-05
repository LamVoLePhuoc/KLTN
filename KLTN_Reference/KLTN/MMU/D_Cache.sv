module D_Cache (
    input          clk,
    input          reset,
    // CPU interface
    input  [31:0]  cpu_addr,
    input          cpu_read,
    input          cpu_write,
    input  [63:0]  cpu_wdata,
    output [63:0]  cpu_rdata,
    output         cpu_ready,

    // Module Wrapper interface (AXI-4)
    output [31:0]  mem_req_addr,     
    output         mem_req_read,
    output         mem_req_write,
    output [255:0] mem_req_wdata,
    input  [255:0] mem_rdata, 
    input          mem_ready
);

    timeunit 1ns; timeprecision 1ps;

    // Internal signals
    wire [4:0]  tag_index, data_index;
    wire [21:0] cpu_tag;
    wire [21:0] tag_way0, tag_way1;
    wire        valid_way0, valid_way1, dirty_way0, dirty_way1;
    wire [255:0] data_way0, data_way1;
    wire        hit_way0, hit_way1;
    wire [1:0]  data_way_select;
    wire        data_write_enable;
    wire [255:0] data_wdata;
    wire [21:0] tag_in;
    wire        valid_in;
    wire        dirty_in;
    wire [1:0]  tag_way_select;
    wire        tag_write_enable;
    wire tag_error, data_error, comp_hit, comp_miss, comp_error, fsm_error;
    
    assign cpu_tag   = cpu_addr[31:10];  // 22-bit tag (from cpu_addr[31:10])

    TagArray d_tag_array (
        .clk(clk), .index(tag_index), .write_enable(tag_write_enable),
        .way_select(tag_way_select), .tag_in(tag_in), .valid_in(valid_in),
        .dirty_in(dirty_in), .tag_way0(tag_way0), .tag_way1(tag_way1),
        .valid_way0(valid_way0), .valid_way1(valid_way1), .dirty_way0(dirty_way0),
        .dirty_way1(dirty_way1), .reset(reset), .error_out(tag_error)
    );

    DataArray d_data_array (
        .clk(clk), .index(data_index), .write_enable(data_write_enable),
        .way_select(data_way_select), .wdata(data_wdata), .data_way0(data_way0),
        .data_way1(data_way1), .reset(reset), .error_out(data_error)
    );

    Comparator d_comp (
        .cpu_tag(cpu_tag), .tag_way0(tag_way0), .tag_way1(tag_way1),
        .valid_way0(valid_way0), .valid_way1(valid_way1), .hit_way0(hit_way0),
        .hit_way1(hit_way1), .hit(comp_hit), .miss(comp_miss), .error_out(comp_error)
    );

    D_CacheController d_cache_ctrl (
        .clk(clk), .reset(reset), .cpu_addr(cpu_addr), .cpu_read(cpu_read),
        .cpu_write(cpu_write), .cpu_wdata(cpu_wdata), .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready), .tag_index(tag_index), .tag_way0(tag_way0),
        .tag_way1(tag_way1), .valid_way0(valid_way0), .valid_way1(valid_way1),
        .dirty_way0(dirty_way0), .dirty_way1(dirty_way1), .tag_write_enable(tag_write_enable),
        .tag_way_select(tag_way_select), .tag_in(tag_in), .valid_in(valid_in),
        .dirty_in(dirty_in), .tag_error(tag_error), .data_index(data_index),
        .data_way0(data_way0), .data_way1(data_way1), .data_wdata(data_wdata),
        .data_write_enable(data_write_enable), .data_way_select(data_way_select),
        .data_error(data_error), .hit_way0(hit_way0), .hit_way1(hit_way1),
        .comp_hit(comp_hit), .comp_miss(comp_miss), .comp_error(comp_error),
        .mem_req_addr(mem_req_addr), .mem_req_read(mem_req_read),
        .mem_req_write(mem_req_write), .mem_req_wdata(mem_req_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready), .fsm_error(fsm_error)
    );

endmodule
