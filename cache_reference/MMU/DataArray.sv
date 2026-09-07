module DataArray (
    input wire clk,
    input wire reset,
    input wire [4:0] index,
    input wire write_enable,
    input wire [1:0] way_select,
    input wire [255:0] wdata,
    output reg [255:0] data_way0,
    output reg [255:0] data_way1,
    output reg error_out
);

    timeunit 1ns; timeprecision 1ps;

    // Cache data storage array
    reg [255:0] data [0:31][0:1];

    // Read logic (combinational)
    always @(*) begin
        // Output data for the selected set
        data_way0 = data[index][0];
        data_way1 = data[index][1];

        // Error detection for invalid way_select
        error_out = write_enable && (way_select != 2'b01 && way_select != 2'b10);
    end

    // Write and reset logic (sequential)
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize all data to zero on reset
            for (i = 0; i < 32; i = i + 1) begin
                data[i][0] <= 256'b0;    // Clear data for way 0
                data[i][1] <= 256'b0;    // Clear data for way 1
            end
        end else if (write_enable) begin
            // Write to the selected way (only one way at a time)
            if (way_select == 2'b01) begin
                data[index][0] <= wdata;
            end else if (way_select == 2'b10) begin
                data[index][1] <= wdata;
            end
            // Note: Invalid way_select (2'b00, 2'b11) is ignored and flagged by error_out
        end
    end

endmodule