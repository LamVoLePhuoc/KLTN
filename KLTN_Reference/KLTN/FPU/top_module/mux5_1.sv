module mux5_1 #(parameter DataWidth = 1) (
    input logic [(DataWidth-1):0]   inpA,
    input logic [(DataWidth-1):0]   inpB,
    input logic [(DataWidth-1):0]   inpC,
    input logic [(DataWidth-1):0]   inpD,
    input logic [(DataWidth-1):0]   inpE,
    input logic [2:0]               sel,
    output logic [(DataWidth-1):0]  outp
);
    timeunit 1ns; timeprecision 1ps;
    
    always_comb begin
        case (sel)
            3'b000: outp = inpA;
            3'b001: outp = inpB; 
            3'b010: outp = inpC; 
            3'b011: outp = inpD;
            3'b100: outp = inpE;
            default: outp = 'x;
        endcase
    end
endmodule: mux5_1