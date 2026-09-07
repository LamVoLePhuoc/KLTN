// One-hot-to-binary encoder. Written to fill a genuinely missing dependency
// (rtl/common/encoder/onehot_encoder/ was empty in this repo). Callers only
// ever drive a true one-hot input (exactly one bit set), so a plain
// OR-reduction of the set bit's index is sufficient and avoids any
// priority bias.
module onehot_encoder #(
    parameter INPUT_W  = 8,
    parameter OUTPUT_W = 3
)(
    input      [INPUT_W-1:0]   i,
    output reg [OUTPUT_W-1:0]  o
);

    integer idx;
    always @(*) begin
        o = {OUTPUT_W{1'b0}};
        for (idx = 0; idx < INPUT_W; idx = idx + 1) begin
            if (i[idx]) begin
                o = o | idx[OUTPUT_W-1:0];
            end
        end
    end

endmodule
