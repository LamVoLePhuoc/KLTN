`timescale 1ns / 1ps

// Asynchronous assertion, synchronous deassertion reset conditioner.
// ARESETN may arrive asynchronously from the board.  Both synchronizer
// stages clear immediately when it is asserted, while release requires two
// clean rising clock edges.  Downstream active-high and active-low resets are
// therefore phase aligned and cannot leave reset on different clock edges.
module reset_sync (
    input  wire clk,
    input  wire arst_n,
    output wire srst,
    output wire srst_n
);
    (* ASYNC_REG = "TRUE" *) reg [1:0] release_ff;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            release_ff <= 2'b00;
        else
            release_ff <= {release_ff[0], 1'b1};
    end

    assign srst_n = release_ff[1];
    assign srst   = ~release_ff[1];
endmodule
