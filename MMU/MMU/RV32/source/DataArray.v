module DataArray (
    input wire clk,                  // Clock input
    input wire reset,                // Active-high reset
    input wire [4:0] index,          // Set index (0-31 for 32 sets)
    input wire write_enable,         // Write enable signal (unused in I_Cache)
    input wire [1:0] way_select,     // Way selection (2'b01: way 0, 2'b10: way 1)
    input wire [255:0] wdata,        // Input data (256 bits, 32 bytes)
    output reg [255:0] data_way0,    // Data output for way 0
    output reg [255:0] data_way1,    // Data output for way 1
    output reg error_out             // Error signal for invalid way_select
);

    // Cache data storage array
    reg [255:0] data [0:31][0:1];    // Data array: 32 sets, 2 ways

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