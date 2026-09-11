`timescale 1ns / 1ps

module hazard_unit(
    // --- 1. TÍN HIỆU TỪ DECODE STAGE ---
    input  wire [4:0] Rs1_D,
    input  wire [4:0] Rs2_D,
    input  wire [4:0] Rs1_F_D,
    input  wire [4:0] Rs2_F_D,
    input  wire [4:0] Rs3_F_D,

    // --- 2. TÍN HIỆU TỪ EXECUTE STAGE ---
    input  wire [4:0] Rs1_E,
    input  wire [4:0] Rs2_E,
    input  wire [4:0] Rs1_F_E,
    input  wire [4:0] Rs2_F_E,
    input  wire [4:0] Rs3_F_E,

    input  wire [4:0] RD_E,
    input  wire [4:0] RD_F_E,

    input  wire       MemReadE,
    input  wire       RegWriteE,
    input  wire       FPRegWriteE,

    input  wire       PCSrcE,
    input  wire       Stall_FPU_Req,
    input  wire       Stall_MDU_Req,   // THÊM: stall khi MDU đang xử lý lệnh M

    // --- 3. TÍN HIỆU TỪ MEMORY STAGE ---
    input  wire       RegWriteM,
    input  wire       FPRegWriteM,
    input  wire [4:0] RD_M,
    input  wire [4:0] RD_F_M,

    // --- 4. TÍN HIỆU TỪ WRITEBACK STAGE ---
    input  wire       RegWriteW,
    input  wire       FPRegWriteW,
    input  wire [4:0] RD_W,
    input  wire [4:0] RD_F_W,

    // --- OUTPUTS: FORWARDING ---
    output reg  [1:0] ForwardAE,
    output reg  [1:0] ForwardBE,
    output reg  [1:0] ForwardAE_F,
    output reg  [1:0] ForwardBE_F,
    output reg  [1:0] ForwardCE_F,

    // --- OUTPUTS: STALL / FLUSH CONTROL ---
    output reg        StallF,
    output reg        StallD,
    output reg        StallE,
    output reg        FlushD,
    output reg        FlushE,
    output reg        FlushM
);

    // =========================================================
    // 1. INTEGER FORWARDING
    // =========================================================
    always @(*) begin
        // Forward cho operand A
        if (RegWriteM && (RD_M != 5'd0) && (RD_M == Rs1_E))
            ForwardAE = 2'b10;
        else if (RegWriteW && (RD_W != 5'd0) && (RD_W == Rs1_E))
            ForwardAE = 2'b01;
        else
            ForwardAE = 2'b00;

        // Forward cho operand B
        // Store cũng dùng Rs2_E làm WriteDataE,
        // nên ForwardBE cũng áp dụng cho store data.
        if (RegWriteM && (RD_M != 5'd0) && (RD_M == Rs2_E))
            ForwardBE = 2'b10;
        else if (RegWriteW && (RD_W != 5'd0) && (RD_W == Rs2_E))
            ForwardBE = 2'b01;
        else
            ForwardBE = 2'b00;
    end

    // =========================================================
    // 2. FLOAT FORWARDING
    // =========================================================
    always @(*) begin
        if (FPRegWriteM && (RD_F_M == Rs1_F_E))
            ForwardAE_F = 2'b10;
        else if (FPRegWriteW && (RD_F_W == Rs1_F_E))
            ForwardAE_F = 2'b01;
        else
            ForwardAE_F = 2'b00;

        if (FPRegWriteM && (RD_F_M == Rs2_F_E))
            ForwardBE_F = 2'b10;
        else if (FPRegWriteW && (RD_F_W == Rs2_F_E))
            ForwardBE_F = 2'b01;
        else
            ForwardBE_F = 2'b00;

        if (FPRegWriteM && (RD_F_M == Rs3_F_E))
            ForwardCE_F = 2'b10;
        else if (FPRegWriteW && (RD_F_W == Rs3_F_E))
            ForwardCE_F = 2'b01;
        else
            ForwardCE_F = 2'b00;
    end

    // =========================================================
    // 3. LOAD-USE HAZARD DETECTION
    // =========================================================
    wire int_load_use;
    wire fp_load_use;
    wire load_use_hazard;

    assign int_load_use =
        MemReadE && RegWriteE &&
        (RD_E != 5'd0) &&
        (
            (RD_E == Rs1_D) ||
            (RD_E == Rs2_D)
        );

    assign fp_load_use =
        MemReadE && FPRegWriteE &&
        (
            (RD_F_E == Rs1_F_D) ||
            (RD_F_E == Rs2_F_D) ||
            (RD_F_E == Rs3_F_D)
        );

    assign load_use_hazard = int_load_use || fp_load_use;

    // =========================================================
    // 4. STALL / FLUSH CONTROL
    //
    // Priority:
    //   1) FPU/MDU stall
    //   2) load-use hazard
    //   3) taken branch/jump
    //
    // Khi MDU hoặc FPU đang busy:
    //   - StallF = 1: giữ PC
    //   - StallD = 1: giữ IF/ID
    //   - StallE = 1: giữ ID/EX, tức giữ lệnh đang ở EX
    //   - FlushM = 1: không cho kết quả rác đi xuống MEM
    // =========================================================
    always @(*) begin
        StallF = 1'b0;
        StallD = 1'b0;
        StallE = 1'b0;
        FlushD = 1'b0;
        FlushE = 1'b0;
        FlushM = 1'b0;

        if (Stall_FPU_Req || Stall_MDU_Req) begin
            StallF = 1'b1;
            StallD = 1'b1;
            StallE = 1'b1;
            FlushM = 1'b1;
        end
        else if (load_use_hazard) begin
            StallF = 1'b1;
            StallD = 1'b1;
            FlushE = 1'b1;
        end
        else if (PCSrcE) begin
            FlushD = 1'b1;
            FlushE = 1'b1;
        end
    end

endmodule