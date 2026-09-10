`timescale 1ns/1ps
// from Lee Min Hunz with luv
module plru(
    input       clk
,   input       rst_n
,   input       prev_bit
,   input       left_hit
,   input       right_hit
,   output reg  plru_bit
);
    // always @(*) begin
    //     case({left_hit, right_hit})
    //         2'b10: begin    // hit trai -> set 1
    //             plru_bit = 1'b1;
    //         end 
    //         2'b01: begin    // hit phai -> set 0
    //             plru_bit = 1'b0;
    //         end 
    //         default: begin
    //             plru_bit = prev_bit;
    //         end 
    //     endcase
    // end 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            plru_bit <= 1'b0;
        end
        else begin
            case({left_hit, right_hit})
                2'b10: begin    // hit trai -> set 1
                    plru_bit <= 1'b1;
                end 
                2'b01: begin    // hit phai -> set 0
                    plru_bit <= 1'b0;
                end 
                default: begin
                    plru_bit <= prev_bit;
                end 
            endcase    
        end   
    end
endmodule