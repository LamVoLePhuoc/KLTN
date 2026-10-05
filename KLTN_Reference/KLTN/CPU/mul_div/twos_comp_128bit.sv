module twos_comp_128bit(in, out, en);

    timeunit 1ns; timeprecision 1ps;

    //variable declaration for 128bit twos complement calculator
    input en;
    input [127:0] in;
    output reg [127:0] out;

    //logic block 
    //when en == 1 -- out = 2's comp of inp
    //when en == 0 -- out = inp 
    always @(*) begin
        if (en) begin
            out = ~in + 128'd1;
        end
        else begin
            out = in;
        end
    end
        
endmodule