module Comparator #(
    parameter NUM_WAYS = 2,        // Number of ways (default: 2 for 2-way set associative)
    parameter TAG_WIDTH = 22       // Tag width (default: 22 bits)
) (
    input wire [TAG_WIDTH-1:0] cpu_tag,    // Tag from CPU address
    input wire [TAG_WIDTH-1:0] tag_way0,   // Tag from way 0
    input wire [TAG_WIDTH-1:0] tag_way1,   // Tag from way 1
    input wire valid_way0,                 // Valid bit for way 0
    input wire valid_way1,                 // Valid bit for way 1
    output wire hit_way0,                  // Hit signal for way 0
    output wire hit_way1,                  // Hit signal for way 1
    output wire hit,                       // Overall hit signal (any way)
    output wire miss,                      // Miss signal (no way hit)
    output wire error_out                  // Error signal for invalid state (both ways hit)
);

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