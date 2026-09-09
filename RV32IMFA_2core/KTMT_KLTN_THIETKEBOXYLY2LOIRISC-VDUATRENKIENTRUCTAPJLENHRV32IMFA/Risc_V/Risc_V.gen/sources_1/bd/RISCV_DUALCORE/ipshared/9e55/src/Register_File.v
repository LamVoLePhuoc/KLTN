module Register_File(
    input  wire        clk,
    input  wire        rst,
    input  wire        WE3,    // Write Enable
    input  wire [4:0]  A1,     // RS1
    input  wire [4:0]  A2,     // RS2
    input  wire [4:0]  A3,     // RD
    input  wire [31:0] WD3,    // Dữ liệu ghi (từ tầng WB)
    output wire [31:0] RD1,    // Dữ liệu đọc 1
    output wire [31:0] RD2     // Dữ liệu đọc 2
);
    // Khai báo mảng thanh ghi từ 1 đến 31 (Tiết kiệm x0)
    reg [31:0] Register [31:1]; 
    
    
    integer i; 

    // --- LOGIC GHI (Synchronous Write) ---
    always @(posedge clk) begin
        if (rst == 1'b0) begin 
            // Reset toàn bộ thanh ghi về 0
            for (i = 1; i < 32; i = i + 1) begin
                Register[i] <= 32'h0;
            end
        end else if (WE3 && (A3 != 5'd0)) begin
            Register[A3] <= WD3;
        end
    end

    // --- LOGIC ĐỌC (Asynchronous Read với Internal Forwarding) ---
    assign RD1 = (A1 == 5'd0) ? 32'd0 : 
                 ((A1 == A3) && WE3) ? WD3 : Register[A1];

    assign RD2 = (A2 == 5'd0) ? 32'd0 : 
                 ((A2 == A3) && WE3) ? WD3 : Register[A2];

endmodule