module if_id_registers #(
    parameter RESET_VECTOR = 32'h0000_0000  
)(
    // --- Tín hiệu điều khiển hệ thống ---
    input clk,
    input rst,          // Reset mức thấp (Active Low)

    // --- Tín hiệu điều khiển luồng lệnh ---
    input stall,        // Dừng do Hazard nội bộ 
    input bus_ready,    // Dừng do Bus bận (Lõi kia đang dùng bộ nhớ)
    input flush,        // Xóa pipeline (do lệnh nhảy hoặc lỗi)

    // --- Đầu vào từ tầng Fetch (F) ---
    input [31:0] InstrF,
    input [31:0] PCF,
    input [31:0] PCPlus4F,

    // --- Đầu ra đến tầng Decode (D) ---
    output reg [31:0] InstrD,
    output reg [31:0] PCD,
    output reg [31:0] PCPlus4D
);
    localparam NOP_INSTRUCTION = 32'h00000013;

    always @(posedge clk or negedge rst) begin
        // 1. Ưu tiên cao nhất: Reset hệ thống
        if (rst == 1'b0) begin
            InstrD   <= NOP_INSTRUCTION;
            PCD      <= RESET_VECTOR;
            PCPlus4D <= RESET_VECTOR + 4;
        end
        
        // 2. Ưu tiên nhì: Flush (Xóa lệnh khi nhảy sai)
        else if (flush) begin
            InstrD   <= NOP_INSTRUCTION; // Biến lệnh hiện tại thành NOP
            PCD      <= 32'h0;           // Xóa địa chỉ để tránh nhầm lẫn
            PCPlus4D <= 32'h0;
        end
        
        // 3. Cập nhật dữ liệu: Chỉ khi KHÔNG bị stall nội bộ VÀ Bus đã sẵn sàng
        else if (!stall && bus_ready) begin
            InstrD   <= InstrF;
            PCD      <= PCF;
            PCPlus4D <= PCPlus4F;
        end
        
        // 4. Trường hợp Stall (stall=1 hoặc bus_ready=0): 
        // Các thanh ghi giữ nguyên giá trị (implicit hold)
    end
endmodule