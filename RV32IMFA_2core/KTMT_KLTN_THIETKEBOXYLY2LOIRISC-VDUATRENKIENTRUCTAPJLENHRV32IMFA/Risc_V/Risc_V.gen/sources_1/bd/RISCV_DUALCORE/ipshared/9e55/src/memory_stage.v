module memory_stage(
    input clk, rst,
    
    // --- Control Signals ---
    input MemWriteM,
    input MemReadM,        
    input AtomicM,
    
    // --- Data Inputs ---
    input [31:0] ALU_ResultM,  // Đây chính là Địa chỉ (Addr)
    input [31:0] WriteDataM,
    
    // --- Tín hiệu Snoop từ Core kia ---
    input [31:0] Snoop_Addr,   // Core kia đang ghi vào đâu?
    input        Snoop_WE,     // Core kia có đang ghi ko?

    // --- Giao tiếp với Bus/Arbiter ---
    output [31:0] bus_addr,
    output [31:0] bus_write_data,
    output        bus_mem_write, 
    output        bus_mem_read,  
    input  [31:0] bus_read_data, 
    
    // --- Output về lõi (WB Stage) ---
    output [31:0] ReadDataM
);

    // --- LOGIC ATOMIC (RESERVATION STATION) ---
    reg [31:0] reservation_addr;
    reg        reservation_valid;

    wire is_LR = AtomicM & ~MemWriteM; 
    wire is_SC = AtomicM &  MemWriteM; 

    always @(posedge clk or negedge rst) begin
        if (!rst) begin
            reservation_valid <= 1'b0;
            reservation_addr  <= 32'h0;
        end else begin
            // 1. Logic đặt chỗ của bản thân
            if (is_LR) begin
                reservation_valid <= 1'b1;
                reservation_addr  <= ALU_ResultM;
            end else if (is_SC) begin
                reservation_valid <= 1'b0; // Dùng xong (dù fail hay pass) thì bỏ chỗ
            end
            
            // 2.S Logic Snoop: Bị Core kia ghi đè -> Hủy chỗ
            if (reservation_valid && Snoop_WE && (Snoop_Addr == reservation_addr)) begin
                reservation_valid <= 1'b0;
            end
        end
    end

    // Kiểm tra SC thành công
    wire sc_success = is_SC & reservation_valid & (ALU_ResultM == reservation_addr);

    // --- XỬ LÝ TÍN HIỆU RA BUS ---
    assign bus_addr       = ALU_ResultM;
    assign bus_write_data = WriteDataM;
    
    // Chỉ ghi RAM thật khi: (Store thường) HOẶC (SC và Thành công)
    assign bus_mem_write  = (MemWriteM & ~AtomicM) | sc_success;
    
    // Đọc RAM khi: (Load thường) HOẶC (LR)
    assign bus_mem_read   = MemReadM; 

    // --- XỬ LÝ DỮ LIỆU TRẢ VỀ (DATA MUX) ---
    // Nếu là SC -> Trả về 0 (Success) hoặc 1 (Fail).
    // Nếu là Load/LR -> Lấy dữ liệu từ Bus.
    assign ReadDataM = is_SC ? {31'b0, ~sc_success} : bus_read_data;

endmodule