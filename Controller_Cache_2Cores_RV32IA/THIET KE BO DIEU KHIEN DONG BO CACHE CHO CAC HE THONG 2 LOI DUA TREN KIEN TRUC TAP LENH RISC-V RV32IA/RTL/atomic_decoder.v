`timescale 1ns / 1ps

// from Lee Min Hunz with luv
module atomic_decoder (
    input               AtomicOp
,   input       [4:0]   funct5
,   output  reg         amo
,   output  reg [2:0]   amo_op
,   output  reg         lr
,   output  reg         sc
);

    always @(*) begin
        case ({AtomicOp, funct5})
            6'b100010: begin // LR.W
                amo     = 1'b0;
                amo_op  = 3'b000;
                lr      = 1'b1;
                sc      = 1'b0;
            end
            6'b100011: begin // SC.W
                amo     = 1'b0;
                amo_op  = 3'b000;
                lr      = 1'b0;
                sc      = 1'b1;
            end
            6'b100001: begin // AMOSWAP.W
                amo     = 1'b1;
                amo_op  = 3'b000; 
                lr      = 1'b0;
                sc      = 1'b0;
            end 
            6'b100000: begin // AMOADD.W
                amo     = 1'b1;
                amo_op  = 3'b001; 
                lr      = 1'b0;
                sc      = 1'b0;
            end 
            6'b101100: begin //AMOAND
                amo     = 1'b1;
                amo_op  = 3'b010; 
                lr      = 1'b0;
                sc      = 1'b0;
            end 
            6'b101000: begin //AMOOR
                amo     = 1'b1;
                amo_op  = 3'b011; 
                lr      = 1'b0;
                sc      = 1'b0;
            end 
            6'b100100: begin //AMOXOR
                amo     = 1'b1;
                amo_op  = 3'b100; 
                lr      = 1'b0;
                sc      = 1'b0;
            end
            6'b110100: begin // AMOMAX
                amo     = 1'b1;
                amo_op  = 3'b101; 
                lr      = 1'b0;
                sc      = 1'b0;
            end 
            6'b110000: begin // AMOMIN
                amo     = 1'b1;
                amo_op  = 3'b110; 
                lr      = 1'b0;
                sc      = 1'b0;
            end 
            default: begin
                amo     = 1'b0;
                amo_op  = 3'b000;
                lr      = 1'b0;
                sc      = 1'b0;
            end
        endcase
    end
endmodule