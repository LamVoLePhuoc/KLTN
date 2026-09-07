`timescale 1ns / 1ps

module ALU (
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [4:0]  ALUControl,

    output wire        Carry,
    output wire        OverFlow,
    output wire        Zero,
    output wire        Negative,
    output wire [31:0] Result
);

    // ============================================================
    // 1. ALU CONTROL ENCODING
    // ============================================================

    // RV32I
    localparam ALU_ADD    = 5'b00000;
    localparam ALU_SUB    = 5'b00001;
    localparam ALU_SLL    = 5'b00010;
    localparam ALU_SLT    = 5'b00011;
    localparam ALU_SLTU   = 5'b00100;
    localparam ALU_XOR    = 5'b00101;
    localparam ALU_SRL    = 5'b00110;
    localparam ALU_SRA    = 5'b00111;
    localparam ALU_OR     = 5'b01000;
    localparam ALU_AND    = 5'b01001;

    // RV32M - không xử lý trong ALU nữa, chỉ giữ mã để tránh default sai
    // Kết quả thật của các lệnh này sẽ lấy từ MDU trong execute_stage.
    localparam ALU_MUL    = 5'b10000;
    localparam ALU_MULH   = 5'b10001;
    localparam ALU_MULHSU = 5'b10010;
    localparam ALU_MULHU  = 5'b10011;
    localparam ALU_DIV    = 5'b10100;
    localparam ALU_DIVU   = 5'b10101;
    localparam ALU_REM    = 5'b10110;
    localparam ALU_REMU   = 5'b10111;

    // RV32A atomic ALU operations
    localparam ALU_MAX    = 5'b11000;
    localparam ALU_MIN    = 5'b11001;
    localparam ALU_MAXU   = 5'b11010;
    localparam ALU_MINU   = 5'b11011;

    // ============================================================
    // 2. INTERNAL WIRES
    // ============================================================

    wire [32:0] add_w;
    wire [32:0] sub_w;

    assign add_w = {1'b0, A} + {1'b0, B};
    assign sub_w = {1'b0, A} + {1'b0, ~B} + 33'd1;

    reg [31:0] res_internal;
    reg        carry_internal;
    reg        ovf_internal;

    // ============================================================
    // 3. MAIN COMBINATIONAL LOGIC
    // ============================================================

    always @(*) begin
        res_internal   = 32'd0;
        carry_internal = 1'b0;
        ovf_internal   = 1'b0;

        case (ALUControl)

            // ----------------------------
            // RV32I
            // ----------------------------
            ALU_ADD: begin
                res_internal   = add_w[31:0];
                carry_internal = add_w[32];
                ovf_internal   = (A[31] == B[31]) && (res_internal[31] != A[31]);
            end

            ALU_SUB: begin
                res_internal   = sub_w[31:0];
                carry_internal = sub_w[32];
                ovf_internal   = (A[31] != B[31]) && (res_internal[31] != A[31]);
            end

            ALU_SLL: begin
                res_internal = A << B[4:0];
            end

            ALU_SRL: begin
                res_internal = A >> B[4:0];
            end

            ALU_SRA: begin
                res_internal = $signed(A) >>> B[4:0];
            end

            ALU_AND: begin
                res_internal = A & B;
            end

            ALU_OR: begin
                res_internal = A | B;
            end

            ALU_XOR: begin
                res_internal = A ^ B;
            end

            ALU_SLT: begin
                res_internal = {31'b0, ($signed(A) < $signed(B))};
            end

            ALU_SLTU: begin
                res_internal = {31'b0, (A < B)};
            end

            // ----------------------------
            // RV32M
            // ----------------------------
            // Các lệnh M đã được chuyển sang MDU.
            // Không dùng *, /, % ở đây để tránh tạo combinational multiplier/divider.
            ALU_MUL,
            ALU_MULH,
            ALU_MULHSU,
            ALU_MULHU,
            ALU_DIV,
            ALU_DIVU,
            ALU_REM,
            ALU_REMU: begin
                res_internal   = 32'd0;
                carry_internal = 1'b0;
                ovf_internal   = 1'b0;
            end

            // ----------------------------
            // RV32A atomic ALU operations
            // ----------------------------
            ALU_MAX: begin
                res_internal = ($signed(A) > $signed(B)) ? A : B;
            end

            ALU_MIN: begin
                res_internal = ($signed(A) < $signed(B)) ? A : B;
            end

            ALU_MAXU: begin
                res_internal = (A > B) ? A : B;
            end

            ALU_MINU: begin
                res_internal = (A < B) ? A : B;
            end

            default: begin
                res_internal   = 32'd0;
                carry_internal = 1'b0;
                ovf_internal   = 1'b0;
            end

        endcase
    end

    // ============================================================
    // 4. OUTPUT ASSIGNMENTS
    // ============================================================

    assign Result   = res_internal;
    assign Zero     = (res_internal == 32'd0);
    assign Negative = res_internal[31];
    assign Carry    = carry_internal;
    assign OverFlow = ovf_internal;

endmodule