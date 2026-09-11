// L2_DataArray: 512KB data storage for the shared L2 (2-way, 8192 sets,
// 32-byte / 256-bit lines). Same style as the L1 DataArray.sv, wider index.
module L2_DataArray (
    input  wire         clk,
    input  wire         reset,
    input  wire [12:0]  index,
    input  wire         write_enable,
    input  wire [1:0]   way_select,
    input  wire [255:0] wdata,
    output reg  [255:0] data_way0,
    output reg  [255:0] data_way1,
    output reg           error_out
);

    timeunit 1ns; timeprecision 1ps;

    reg [255:0] data [0:8191][0:1];

    always @(*) begin
        data_way0 = data[index][0];
        data_way1 = data[index][1];
        error_out = write_enable && (way_select != 2'b01 && way_select != 2'b10);
    end

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 8192; i = i + 1) begin
                data[i][0] <= 256'b0;
                data[i][1] <= 256'b0;
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
