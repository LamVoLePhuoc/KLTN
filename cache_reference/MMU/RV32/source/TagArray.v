module TagArray (
    input wire clk,                  // Clock input
    input wire reset,                // Active-high reset
    input wire [4:0] index,          // Set index (0-31 for 32 sets)
    input wire write_enable,         // Write enable signal
    input wire [1:0] way_select,     // Way selection (2'b01: way 0, 2'b10: way 1)
    input wire [21:0] tag_in,        // Input tag (22 bits)
    input wire valid_in,             // Input valid bit
    input wire dirty_in,             // Input dirty bit (for D_Cache, unused in I_Cache)
    output reg [21:0] tag_way0,      // Tag output for way 0
    output reg [21:0] tag_way1,      // Tag output for way 1
    output reg valid_way0,           // Valid bit output for way 0
    output reg valid_way1,           // Valid bit output for way 1
    output reg dirty_way0,           // Dirty bit output for way 0 (for D_Cache)
    output reg dirty_way1,           // Dirty bit output for way 1 (for D_Cache)
    output reg error_out             // Error signal for invalid way_select
);

    // Cache storage arrays
    reg [21:0] tags [0:31][0:1];     // Tag array: 32 sets, 2 ways
    reg valid [0:31][0:1];           // Valid bit array
    reg dirty [0:31][0:1];           // Dirty bit array (for D_Cache)

    // Read logic (combinational)
    always @(*) begin
        // Output tags, valid, and dirty bits for the selected set
        tag_way0 = tags[index][0];
        tag_way1 = tags[index][1];
        valid_way0 = valid[index][0];
        valid_way1 = valid[index][1];
        dirty_way0 = dirty[index][0];
        dirty_way1 = dirty[index][1];

        // Error detection for invalid way_select
        error_out = write_enable && (way_select != 2'b01 && way_select != 2'b10);
    end

    // Write and reset logic (sequential)
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize all arrays to zero on reset
            for (i = 0; i < 32; i = i + 1) begin
                tags[i][0] <= 22'b0;    // Clear tags (optional, for clarity)
                tags[i][1] <= 22'b0;
                valid[i][0] <= 1'b0;    // Clear valid bits
                valid[i][1] <= 1'b0;
                dirty[i][0] <= 1'b0;    // Clear dirty bits
                dirty[i][1] <= 1'b0;
            end
        end else if (write_enable) begin
            // Write to the selected way (only one way at a time)
            if (way_select == 2'b01) begin
                tags[index][0] <= tag_in;
                valid[index][0] <= valid_in;
                dirty[index][0] <= dirty_in;
            end else if (way_select == 2'b10) begin
                tags[index][1] <= tag_in;
                valid[index][1] <= valid_in;
                dirty[index][1] <= dirty_in;
            end
            // Note: Invalid way_select (2'b00, 2'b11) is ignored and flagged by error_out
        end
    end

endmodule