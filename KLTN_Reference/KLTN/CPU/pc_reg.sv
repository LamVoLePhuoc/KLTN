module pc_reg (
    input clk, rstn, en, cache_ready_i,
    input [12:0] next_pc,
    output logic [12:0] pc
);
    timeunit 1ns; timeprecision 1ps;

    logic cache_ready;

    always_ff @(posedge clk, negedge rstn)
        if (!rstn) pc = 0;
        else if (en & cache_ready) pc = {next_pc[12:1],1'b0};

    always_ff @(negedge clk) begin
        cache_ready <= cache_ready_i;
    end

endmodule
