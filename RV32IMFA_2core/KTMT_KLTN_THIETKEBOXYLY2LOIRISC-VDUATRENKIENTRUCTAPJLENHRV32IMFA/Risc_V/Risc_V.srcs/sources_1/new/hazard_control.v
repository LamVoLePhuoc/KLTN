module hazard_control (
    // Inputs cơ bản
    input rst, // Thực ra không cần dùng trong logic này, nhưng giữ lại cũng không sao
    input PCSrcE, 
    input ResultSrcE, // Giả sử 1 = Load Instruction (MemRead)

    // Inputs địa chỉ thanh ghi INT
    input [4:0] RD_E, RS1_D, RS2_D,

    // Inputs địa chỉ thanh ghi FLOAT (BẮT BUỘC PHẢI THÊM)
    input [4:0] RD_F_E,      // Đích Float đang ở Execute (Lệnh Load)
    input [4:0] RS1_F_D,     // Nguồn 1 Float đang ở Decode
    input [4:0] RS2_F_D,     // Nguồn 2 Float đang ở Decode
    
    // Tín hiệu Stall từ FPU
    input Stall_FPU,

    // Outputs
    output reg StallF, StallD, StallE, StallM, StallW,
    output reg FlushD, FlushE, FlushM, FlushW,
    output reg lwStall, branchStall
);

    // Biến phụ trợ check Load-Use
    reg lwStall_Int;
    reg lwStall_Float;

    always @(*) begin
        // Mặc định gán về 0 để tránh Latch
        {StallF, StallD, StallE, StallM, StallW} = 0;
        {FlushD, FlushE, FlushM, FlushW} = 0;
        lwStall = 0;
        branchStall = 0;

        // ---------------------------------------------------------
        // 1. PHÁT HIỆN LOAD-USE HAZARD (Cả Int và Float)
        // ---------------------------------------------------------
        
        // Hazard Int: Load x1 -> Add x1
        lwStall_Int = ResultSrcE && (RD_E != 5'b0) && 
                      ((RD_E == RS1_D) || (RD_E == RS2_D));

        // Hazard Float: Load f1 -> FAdd f1
        // Lưu ý: Float không check != 0 vì f0 là thanh ghi có giá trị
        lwStall_Float = ResultSrcE && 
                        ((RD_F_E == RS1_F_D) || (RD_F_E == RS2_F_D));

        // Tổng hợp Stall do Load
        lwStall = lwStall_Int | lwStall_Float;

        // ---------------------------------------------------------
        // 2. PHÁT HIỆN BRANCH HAZARD
        // ---------------------------------------------------------
        branchStall = PCSrcE;

        // ---------------------------------------------------------
        // 3. TẠO TÍN HIỆU STALL/FLUSH (LOGIC CHÍNH)
        // ---------------------------------------------------------

        // --- STALL LOGIC ---
        // Dừng PC và Decode nếu có Load Hazard HOẶC FPU chưa xong
        StallF = lwStall | Stall_FPU; 
        StallD = lwStall | Stall_FPU;
        
        // Dừng Execute CHỈ KHI FPU cần thêm thời gian
        StallE = Stall_FPU; 
        
        // Memory và Writeback không bao giờ Stall (luôn trôi đi)
        StallM = 1'b0;
        StallW = 1'b0;

        // --- FLUSH LOGIC ---
        // Xóa Decode nếu Branch sai (Branch Hazard)
        FlushD = branchStall;

        // Xóa Execute nếu Load Hazard (đợi Load) HOẶC Branch sai
        // (Nếu FPU Stall thì KHÔNG Flush E, vì ta cần giữ lệnh đó lại tính tiếp)
        FlushE = lwStall | branchStall; 

        // Xóa Memory nếu FPU Stall (để chặn rác trôi xuống Mem)
        // Hoặc có thể thêm logic Branch nếu branch được quyết định ở Ex
        FlushM = Stall_FPU;
        
        // Writeback không cần flush
        FlushW = 1'b0;
    end
endmodule