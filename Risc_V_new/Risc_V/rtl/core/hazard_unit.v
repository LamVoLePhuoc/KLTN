`timescale 1ns / 1ps

module hazard_unit(
    // --- 1. TÍN HIỆU TỪ DECODE STAGE ---
    input  wire [4:0] Rs1_D,
    input  wire [4:0] Rs2_D,

    // --- 2. TÍN HIỆU TỪ EXECUTE STAGE ---
    input  wire [4:0] Rs1_E,
    input  wire [4:0] Rs2_E,

    input  wire [4:0] RD_E,

    input  wire       MemReadE,
    input  wire       RegWriteE,

    input  wire       PCSrcE,
    input  wire       Stall_MDU_Req,   // THÊM: stall khi MDU đang xử lý lệnh M

    // --- 3. TÍN HIỆU TỪ MEMORY STAGE ---
    input  wire       RegWriteM,
    input  wire [4:0] RD_M,

    // --- 4. TÍN HIỆU TỪ WRITEBACK STAGE ---
    input  wire       RegWriteW,
    input  wire [4:0] RD_W,

    // --- OUTPUTS: FORWARDING ---
    output reg  [1:0] ForwardAE,
    output reg  [1:0] ForwardBE,

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
    // 2. LOAD-USE HAZARD DETECTION
    // =========================================================
    wire load_use_hazard;

    assign load_use_hazard =
        MemReadE && RegWriteE &&
        (RD_E != 5'd0) &&
        (
            (RD_E == Rs1_D) ||
            (RD_E == Rs2_D)
        );

    // =========================================================
    // 3. STALL / FLUSH CONTROL
    //
    // Priority:
    //   1) MDU stall
    //   2) load-use hazard
    //   3) taken branch/jump
    //
    // Khi MDU đang busy:
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

        if (Stall_MDU_Req) begin
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
