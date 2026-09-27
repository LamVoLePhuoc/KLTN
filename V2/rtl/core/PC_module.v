module PC_module #(
    parameter [31:0] RESET_VECTOR = 32'h0000_0000
) (
    input         clk,
    input         rst,
    input         PC_Write,
    input  [31:0] PC_Next,
    output reg [31:0] PC
);

    always @(posedge clk) begin
        if (rst)
            PC <= RESET_VECTOR;
        else if (PC_Write)
            PC <= PC_Next;
    end

endmodule