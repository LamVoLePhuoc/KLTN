// Classic 2-entry skid buffer: decouples a backward (input) ready/valid
// handshake from a forward (output) one at full throughput, using one main
// register plus one overflow ("skid") register for the cycle where the
// downstream stalls right as a new beat arrives. Written to fill a
// genuinely missing dependency (rtl/common/skid_buffer/ was empty in this
// repo). SBUF_TYPE is accepted for interface compatibility with the
// existing callers (dsp_*/sa_* pass 1 or 3) but this implementation is
// functionally correct for any value -- it does not change buffering
// depth/style by type.
module skid_buffer #(
    parameter SBUF_TYPE  = 1,
    parameter DATA_WIDTH = 8
)(
    input                        clk,
    input                        rst_n,
    input      [DATA_WIDTH-1:0]  bwd_data_i,
    input                        bwd_valid_i,
    input                        fwd_ready_i,
    output     [DATA_WIDTH-1:0]  fwd_data_o,
    output                       bwd_ready_o,
    output                       fwd_valid_o
);

    reg [DATA_WIDTH-1:0] data_r;
    reg                  valid_r;
    reg [DATA_WIDTH-1:0] skid_data_r;
    reg                  skid_valid_r;

    wire out_fire = valid_r & fwd_ready_i;
    wire in_fire  = bwd_valid_i & bwd_ready_o;

    // We can always accept a new beat as long as the skid (overflow) slot
    // is empty -- worst case it lands in skid this cycle if the main
    // register is stalled.
    assign bwd_ready_o = ~skid_valid_r;
    assign fwd_data_o  = data_r;
    assign fwd_valid_o = valid_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_r       <= {DATA_WIDTH{1'b0}};
            valid_r      <= 1'b0;
            skid_data_r  <= {DATA_WIDTH{1'b0}};
            skid_valid_r <= 1'b0;
        end else begin
            if (out_fire || !valid_r) begin
                // Main register is free this cycle: drain the skid slot
                // first (preserves ordering), else take a fresh beat.
                if (skid_valid_r) begin
                    data_r       <= skid_data_r;
                    valid_r      <= 1'b1;
                    skid_valid_r <= 1'b0;
                end else if (bwd_valid_i) begin
                    data_r  <= bwd_data_i;
                    valid_r <= 1'b1;
                end else begin
                    valid_r <= 1'b0;
                end
            end else if (in_fire) begin
                // Main register is full and stalled, but a new beat was
                // still accepted this cycle (skid was empty) -- park it.
                skid_data_r  <= bwd_data_i;
                skid_valid_r <= 1'b1;
            end
        end
    end

endmodule
