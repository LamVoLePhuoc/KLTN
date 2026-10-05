module Comparator #(
    parameter NUM_WAYS = 2,
    parameter TAG_WIDTH = 22
) (
    input wire [TAG_WIDTH-1:0] cpu_tag,
    input wire [TAG_WIDTH-1:0] tag_way0,
    input wire [TAG_WIDTH-1:0] tag_way1,
    input wire valid_way0,
    input wire valid_way1,
    output wire hit_way0,
    output wire hit_way1,
    output wire hit,
    output wire miss,
    output wire error_out
);

    timeunit 1ns; timeprecision 1ps;	
    
    // Compare tags and check valid bits
    assign hit_way0 = (cpu_tag == tag_way0) && valid_way0;
    assign hit_way1 = (cpu_tag == tag_way1) && valid_way1;

    // Overall hit signal (OR of individual hits)
    assign hit = hit_way0 || hit_way1;

    // Miss signal (no way reports a hit)
    assign miss = ~hit;

    // Error signal for invalid state (both ways report hit)
    assign error_out = hit_way0 && hit_way1;

endmodule