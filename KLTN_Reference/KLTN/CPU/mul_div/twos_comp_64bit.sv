module twos_comp_64bit(in, out, en);

    timeunit 1ns; timeprecision 1ps;

    //variable declaration for 64bit twos complement calculator
    input en;
    input [63:0] in;
    output reg [63:0] out;

    //logic block 
    //when en == 1 -- out = 2's comp of inp
    //when en == 0 -- out = inp 
    always @(*) begin
        if (en) begin
            out = ~in + 64'd1;
        end
        else begin
            out = in;
        end
    end
        
endmodule