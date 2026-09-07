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
    output reg error_out,

    // Phase-2 addition: coherence snoop-invalidate port. When another
    // core writes a line through to the shared L2, the interconnect
    // pulses snoop_en with that line's {index,tag} on every *other*
    // core's private D-cache TagArray; if this array is holding a
    // (now-stale) copy, its valid bit is cleared so the next access
    // re-fetches the fresh line from L2. Unused/tied to 0 in I_Cache
    // (instructions aren't written by other cores in this design).
    input wire        snoop_en,
    input wire [4:0]  snoop_index,
    input wire [21:0] snoop_tag
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
        end else begin
            if (write_enable) begin
                // Write to the selected way (only one way at a time).
                // NOTE: if a snoop for this exact {index,tag} arrives on
                // the same cycle as this fill, the fill must not latch
                // valid=1 — the snoop branch below reads the *old*
                // (pre-edge) tags/valid regs, since nonblocking
                // assignments in the other branch haven't committed yet,
                // so it can't see or clear a same-cycle fill on its own.
                // Force the freshly-filled line invalid in that case so
                // the next access re-fetches from L2 instead of
                // permanently latching stale pre-publish data.
                if (way_select == 2'b01) begin
                    tags[index][0] <= tag_in;
                    valid[index][0] <= (snoop_en && snoop_index == index && snoop_tag == tag_in)
                                        ? 1'b0 : valid_in;
                    dirty[index][0] <= dirty_in;
                end else if (way_select == 2'b10) begin
                    tags[index][1] <= tag_in;
                    valid[index][1] <= (snoop_en && snoop_index == index && snoop_tag == tag_in)
                                        ? 1'b0 : valid_in;
                    dirty[index][1] <= dirty_in;
                end
            end
            // Coherence snoop-invalidate: independent of the normal CPU
            // write path above. If this array already holds the snooped
            // {index,tag} and it's valid, drop it. (Same-cycle collision
            // with a fill of the exact same line is handled above, in
            // the write_enable branch, since this branch only sees
            // pre-edge register values and cannot observe this cycle's
            // fill.)
            if (snoop_en) begin
                if (tags[snoop_index][0] == snoop_tag && valid[snoop_index][0]) begin
                    valid[snoop_index][0] <= 1'b0;
                end
                if (tags[snoop_index][1] == snoop_tag && valid[snoop_index][1]) begin
                    valid[snoop_index][1] <= 1'b0;
                end
            end
        end
    end
    
endmodule