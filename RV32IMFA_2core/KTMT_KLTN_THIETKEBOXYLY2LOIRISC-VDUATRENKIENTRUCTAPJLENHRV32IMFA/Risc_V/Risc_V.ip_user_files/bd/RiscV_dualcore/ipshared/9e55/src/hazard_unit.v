module hazard_unit(
    input rst,

    // --- 1. TÍN HIỆU TỪ DECODE STAGE (Dùng cho Stall Logic) ---
    input [4:0] Rs1_D, Rs2_D,      // Địa chỉ nguồn tại Decode
    input [4:0] Rs1_F_D, Rs2_F_D,  // Địa chỉ nguồn Float tại Decode 

    // --- 2. TÍN HIỆU TỪ EXECUTE STAGE ---
    input [4:0] Rs1_E, Rs2_E,      // Địa chỉ nguồn Int
    input [4:0] Rs1_F_E, Rs2_F_E,  // Địa chỉ nguồn Float 
    input [4:0] RD_E,              // Địa chỉ đích Int (để check Load-Use)
    input [4:0] RD_F_E,            // Địa chỉ đích Float (để check Load-Use FP)
    input       ResultSrcE0,       // Bit 0 của ResultSrc (1 = Load instruction)
    input       Stall_FPU_Req,     // Tín hiệu yêu cầu Stall từ FPU 

    // --- 3. TÍN HIỆU TỪ MEMORY STAGE ---
    input       RegWriteM,         // Ghi Int
    input       FPRegWriteM,       // Ghi Float
    input [4:0] RD_M,              // Địa chỉ đích Int
    input [4:0] RD_F_M,            // Địa chỉ đích Float 

    // --- 4. TÍN HIỆU TỪ WRITEBACK STAGE ---
    input       RegWriteW,         // Ghi Int
    input       FPRegWriteW,       // Ghi Float 
    input [4:0] RD_W,              // Địa chỉ đích Int
    input [4:0] RD_F_W,            // Địa chỉ đích Float 

    // --- OUTPUTS: FORWARDING ---
    output reg [1:0] ForwardAE, ForwardBE,     // Cho Integer ALU
    output reg [1:0] ForwardAE_F, ForwardBE_F, // Cho FPU

    // --- OUTPUTS: STALL CONTROL ---
    output reg StallF,      // Dừng Fetch
    output reg StallD,      // Dừng Decode
    output reg StallE,      // Dừng Execute (để giữ lệnh FPU lại tính cho xong)
    output reg FlushD,      // Xóa Decode (khi Branch - Tùy chọn)
    output reg FlushE,      // Xóa Execute (Load-Use Hazard)
    output reg FlushM       // Xóa Memory (khi FPU Stall)
);

    // =========================================================================
    // 1. FORWARDING UNIT (INTEGER)
    // =========================================================================
    always @(*) begin
        // Forward A
        if (RegWriteM && (RD_M != 0) && (RD_M == Rs1_E))      ForwardAE = 2'b10;
        else if (RegWriteW && (RD_W != 0) && (RD_W == Rs1_E)) ForwardAE = 2'b01;
        else                                                  ForwardAE = 2'b00;

        // Forward B
        if (RegWriteM && (RD_M != 0) && (RD_M == Rs2_E))      ForwardBE = 2'b10;
        else if (RegWriteW && (RD_W != 0) && (RD_W == Rs2_E)) ForwardBE = 2'b01;
        else                                                  ForwardBE = 2'b00;
    end

    // =========================================================================
    // 2. FORWARDING UNIT (FLOAT) 
    // LƯU Ý: Float Register f0 KHÔNG PHẢI LUÔN LÀ 0.
    // Nên ta KHÔNG check điều kiện (RD != 0) cho Float.
    // =========================================================================
    always @(*) begin
        // Forward A (Float)
        if (FPRegWriteM && (RD_F_M == Rs1_F_E))      ForwardAE_F = 2'b10;
        else if (FPRegWriteW && (RD_F_W == Rs1_F_E)) ForwardAE_F = 2'b01;
        else                                         ForwardAE_F = 2'b00;

        // Forward B (Float)
        if (FPRegWriteM && (RD_F_M == Rs2_F_E))      ForwardBE_F = 2'b10;
        else if (FPRegWriteW && (RD_F_W == Rs2_F_E)) ForwardBE_F = 2'b01;
        else                                         ForwardBE_F = 2'b00;
    end

    // =========================================================================
    // 3. HAZARD DETECTION UNIT (STALL LOGIC)
    // =========================================================================
    
    // 3.1 Load-Use Hazard Detection
    // Nếu lệnh ở Execute là Load (ResultSrcE0=1) và đích của nó trùng với nguồn của lệnh ở Decode
    wire lwStall;
    assign lwStall = ResultSrcE0 && (
        (RD_E == Rs1_D) || (RD_E == Rs2_D) ||        // Int Dependency
        (RD_F_E == Rs1_F_D) || (RD_F_E == Rs2_F_D)   // Float Dependency 
    );

    // 3.2 Combine Stalls
    always @(*) begin
        // Default: Run normally
        StallF = 0; StallD = 0; StallE = 0; 
        FlushE = 0; FlushM = 0; FlushD = 0;

        // Ưu tiên 1: FPU Stall (Quan trọng nhất)
        if (Stall_FPU_Req) begin
            StallF = 1; // PC đứng yên
            StallD = 1; // Decode đứng yên
            StallE = 1; // Execute đứng yên (giữ FPU tính tiếp)
            FlushM = 1; // Đẩy bong bóng vào Memory
        end
        // Ưu tiên 2: Load-Use Hazard
        else if (lwStall) begin
            StallF = 1; // PC đứng yên
            StallD = 1; // Decode đứng yên
            FlushE = 1; // Execute xóa (bong bóng)
        end
    end

endmodule