module TagArray #(
    parameter int NUM_SETS  = 32,
    parameter int NUM_WAYS  = 2,
    parameter int TAG_WIDTH = 22,
    parameter int INDEX_WIDTH = $clog2(NUM_SETS)
) (
    input  wire                   clk,
    input  wire                   reset,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire                   write_enable,
    input  wire [NUM_WAYS-1:0]    way_select,
    input  wire [TAG_WIDTH-1:0]   tag_in,
    input  wire                   valid_in,
    input  wire                   dirty_in,
    output reg  [TAG_WIDTH-1:0]   tag_way0,
    output reg  [TAG_WIDTH-1:0]   tag_way1,
    output reg                    valid_way0,
    output reg                    valid_way1,
    output reg                    dirty_way0,
    output reg                    dirty_way1,
    output reg                    error_out
);

    timeunit 1ns; timeprecision 1ps;

    reg [TAG_WIDTH-1:0] tags  [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                 valid [0:NUM_SETS-1][0:NUM_WAYS-1];
    reg                 dirty [0:NUM_SETS-1][0:NUM_WAYS-1];

    always_comb begin
        tag_way0    = tags[index][0];
        tag_way1    = tags[index][1];
        valid_way0  = valid[index][0];
        valid_way1  = valid[index][1];
        dirty_way0  = dirty[index][0];
        dirty_way1  = dirty[index][1];
        error_out   = write_enable && (way_select != 2'b01) && (way_select != 2'b10);
    end

    integer i;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                tags[i][0]  <= '0;
                tags[i][1]  <= '0;
                valid[i][0] <= 1'b0;
                valid[i][1] <= 1'b0;
                dirty[i][0] <= 1'b0;
                dirty[i][1] <= 1'b0;
            end
        end else if (write_enable) begin
            if (way_select == 2'b01) begin
                tags[index][0]  <= tag_in;
                valid[index][0] <= valid_in;
                dirty[index][0] <= dirty_in;
            end else if (way_select == 2'b10) begin
                tags[index][1]  <= tag_in;
                valid[index][1] <= valid_in;
                dirty[index][1] <= dirty_in;
            end
        end
    end

endmodule
