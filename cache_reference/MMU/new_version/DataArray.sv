module DataArray #(
    parameter int NUM_SETS    = 32,
    parameter int NUM_WAYS    = 2,
    parameter int LINE_WIDTH  = 256,
    parameter int INDEX_WIDTH = $clog2(NUM_SETS)
) (
    input  wire                   clk,
    input  wire                   reset,
    input  wire [INDEX_WIDTH-1:0] index,
    input  wire                   write_enable,
    input  wire [NUM_WAYS-1:0]    way_select,
    input  wire [LINE_WIDTH-1:0]  wdata,
    output reg  [LINE_WIDTH-1:0]  data_way0,
    output reg  [LINE_WIDTH-1:0]  data_way1,
    output reg                    error_out
);

    timeunit 1ns; timeprecision 1ps;

    reg [LINE_WIDTH-1:0] data [0:NUM_SETS-1][0:NUM_WAYS-1];

    always_comb begin
        data_way0 = data[index][0];
        data_way1 = data[index][1];
        error_out = write_enable && (way_select != 2'b01) && (way_select != 2'b10);
    end

    integer i;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                data[i][0] <= '0;
                data[i][1] <= '0;
            end
        end else if (write_enable) begin
            if (way_select == 2'b01) begin
                data[index][0] <= wdata;
            end else if (way_select == 2'b10) begin
                data[index][1] <= wdata;
            end
        end
    end

endmodule
