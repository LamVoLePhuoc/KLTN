module TagArray (
    input wire clk,
    input wire reset,
    input wire [4:0] index,
    input wire write_enable,
    input wire [1:0] way_select,
    input wire [21:0] tag_in,
    input wire valid_in,
    input wire dirty_in,
    output reg [21:0] tag_way0,
    output reg [21:0] tag_way1,
    output reg valid_way0,
    output reg valid_way1,
    output reg dirty_way0,
    output reg dirty_way1,
    output reg error_out
);

    timeunit 1ns; timeprecision 1ps;	

    reg [21:0] tags [0:31][0:1];
    reg valid [0:31][0:1];
    reg dirty [0:31][0:1];

    // Read logic (combinational)
    always @(*) begin
        
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
                tags[i][0] <= 22'b0;
                tags[i][1] <= 22'b0;
                valid[i][0] <= 1'b0;
                valid[i][1] <= 1'b0;
                dirty[i][0] <= 1'b0;
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
        end
    end
    
endmodule