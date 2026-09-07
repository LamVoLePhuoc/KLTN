// Edge detector: registers `i` whenever `en` is asserted, and pulses `o`
// for one cycle when the newly-sampled `i` shows the configured edge
// relative to the previously captured value. Written to fill a genuinely
// missing dependency (rtl/common/edgedet/ was empty in this repo).
module edgedet #(
    parameter RISING_EDGE = 1'b1
)(
    input   clk,
    input   rst_n,
    input   i,
    input   en,
    output  o
);

    reg i_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_prev <= 1'b0;
        end else if (en) begin
            i_prev <= i;
        end
    end

    assign o = RISING_EDGE ? (en & i & ~i_prev) : (en & ~i & i_prev);

endmodule
