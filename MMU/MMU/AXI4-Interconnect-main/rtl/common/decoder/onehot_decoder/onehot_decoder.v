// Binary-to-one-hot decoder. Written to fill a genuinely missing dependency
// (rtl/common/decoder/onehot_decoder/ was empty in this repo).
module onehot_decoder #(
    parameter INPUT_W  = 3,
    parameter OUTPUT_W = 8
)(
    input      [INPUT_W-1:0]  i,
    output     [OUTPUT_W-1:0] o
);

    wire [OUTPUT_W-1:0] one = {{(OUTPUT_W-1){1'b0}}, 1'b1};
    assign o = one << i;

endmodule
