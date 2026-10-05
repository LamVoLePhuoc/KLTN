module ROB_counter (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       stall,
    input  logic [6:0] opcode,
    output logic [4:0] ROB
);
    timeunit 1ns; timeprecision 1ps;

    logic [4:0] counter;

    always_ff @(posedge clk, negedge rst_n) begin
        if (~rst_n) begin
            counter <= 5'd1;
        end
        else begin
            if (~stall & (opcode != 7'b1111111) & (opcode != 7'b0100111) & (opcode != 7'b0100011)) begin
                if (counter != 5'd31) begin
                    counter <= counter + 5'd1;
                end
                else begin
                    counter <= 5'd1;
                end
            end
            else begin
                counter <= counter;
            end
        end
    end

    assign ROB = counter;

endmodule: ROB_counter