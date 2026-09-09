module FP_Register_File (
    input  wire        clk,
    input  wire        rst,  
    input  wire        WE3,    // Write Enable
    input  wire [4:0]  A1,     // rs1 address
    input  wire [4:0]  A2,     // rs2 address
    input  wire [4:0]  A3,     // rs3 address (Cần cho lệnh FMADD - Nhân cộng)
    input  wire [4:0]  A_W,    // Write address (rd)
    input  wire [31:0] WD3,    // Dữ liệu ghi 32-bit cho tập F
    output wire [31:0] RD1,
    output wire [31:0] RD2,
    output wire [31:0] RD3     // Output cho cổng đọc thứ 3
);

    reg [31:0] regs [0:31]; 
    integer i;

    // Logic Đọc: Có Internal Forwarding để tránh Hazard trong 1 chu kỳ
    // Nếu đang ghi vào A_W mà trùng với địa chỉ đang đọc -> Lấy luôn WD3
    assign RD1 = (WE3 && (A1 == A_W)) ? WD3 : regs[A1];
    assign RD2 = (WE3 && (A2 == A_W)) ? WD3 : regs[A2];
    assign RD3 = (WE3 && (A3 == A_W)) ? WD3 : regs[A3];

    // Logic Ghi và Reset
    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
        end else if (WE3) begin
            // KHÔNG chặn A_W != 0 vì f0 là thanh ghi bình thường
            regs[A_W] <= WD3;
        end
    end

endmodule