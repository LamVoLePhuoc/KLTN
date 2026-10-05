module mux2_1 #(parameter DataWidth = 1) (
    input logic [(DataWidth-1):0]   inpA,
    input logic [(DataWidth-1):0]   inpB,
    input logic                     sel,
    output logic [(DataWidth-1):0]  outp
);
    timeunit 1ns; timeprecision 1ps;
    
    always_comb begin
        case (sel)
            1'b0: outp = inpA;
            1'b1: outp = inpB; 
            default: outp = 'x;
        endcase
    end
endmodule: mux2_1