module Mux_3_by_1 (
    input  [31:0] a,
    input  [31:0] b,
    input  [31:0] c,
    input  [1:0]  s,
    output [31:0] d
);
    assign d = (s == 2'b00) ? a :
               (s == 2'b01) ? b :
               (s == 2'b10) ? c :
               32'h00000000;
endmodule