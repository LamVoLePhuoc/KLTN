module clk_divider (
    input  logic clk,
    input  logic rst_n,
    output logic core_clk,
    output logic mem_clk
);

    timeunit 1ns; timeprecision 1ps;
    
    logic [1:0] cnt;

    assign mem_clk = clk;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cnt      <= 2'd0;
            core_clk <= 1'b0;
        end 
        else begin
            if (cnt == 2'd2) begin
                cnt      <= 2'd0;
                core_clk <= ~core_clk;
            end 
            else begin
                cnt <= cnt + 2'd1;
            end
        end
    end

endmodule: clk_divider