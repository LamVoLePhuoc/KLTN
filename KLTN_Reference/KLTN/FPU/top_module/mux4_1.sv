module mux4_1 #(parameter DataWidth = 1) (
    input logic [(DataWidth-1):0]   inpA,
    input logic [(DataWidth-1):0]   inpB,
    input logic [(DataWidth-1):0]   inpC,
    input logic [(DataWidth-1):0]   inpD,
    input logic [1:0]               sel,
    output logic [(DataWidth-1):0]  outp
);
    timeunit 1ns; timeprecision 1ps;
    
    always_comb begin
        case (sel)
            2'b00: outp = inpA;
            2'b01: outp = inpB; 
            2'b10: outp = inpC; 
            2'b11: outp = inpD;
            default: outp = 'x;
        endcase
    end
endmodule: mux4_1