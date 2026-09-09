module PC_module #(parameter RESET_VECTOR = 32'h0000_0000) (
    input clk, rst, PC_Write,
    input [31:0] PC_Next,
    output reg [31:0] PC
);
    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) 
            PC <= RESET_VECTOR; // Lõi sẽ bắt đầu tại địa chỉ được cấu hình
        else if (PC_Write)
            PC <= PC_Next;
    end
endmodule