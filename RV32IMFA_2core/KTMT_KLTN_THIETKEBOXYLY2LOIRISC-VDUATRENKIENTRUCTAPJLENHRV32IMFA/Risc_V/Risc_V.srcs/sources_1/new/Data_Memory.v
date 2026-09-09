module Data_Memory (
    input wire clk,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    input wire we,  // Write Enable
    input wire re,  // Read Enable
    output reg [31:0] rdata
);

    // Khai báo mảng nhớ: 256 từ (word) = 1KB
    reg [31:0] ram [0:255];

    // --- Write Logic (Đồng bộ theo xung nhịp) ---
    always @(posedge clk) begin
        if (we) begin
            // Chỉ lấy các bit [9:2] để index vào mảng 256 phần tử
            // (Bỏ 2 bit cuối vì địa chỉ chia hết cho 4)
            ram[addr[9:2]] <= wdata;
        end
    end

    // --- Read Logic (Bất đồng bộ - Combinational) ---
    // Đọc ra ngay lập tức khi địa chỉ thay đổi
    always @(*) begin
        if (re) 
            rdata = ram[addr[9:2]];
        else 
            rdata = 32'b0;
    end

endmodule