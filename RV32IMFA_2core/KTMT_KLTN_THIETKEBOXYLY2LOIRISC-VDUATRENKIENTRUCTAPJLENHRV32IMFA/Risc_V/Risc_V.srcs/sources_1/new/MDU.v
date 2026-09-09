
module MDU(
    input  wire        clk,
    input  wire        rst,

    input  wire        start,
    input  wire [4:0]  op,
    input  wire [31:0] A,
    input  wire [31:0] B,

    output reg         busy,
    output reg         done,
    output reg  [31:0] result
);

    // ============================================================
    // ALU CONTROL ENCODING FOR RV32M
    // ============================================================
    localparam ALU_MUL    = 5'b10000;
    localparam ALU_MULH   = 5'b10001;
    localparam ALU_MULHSU = 5'b10010;
    localparam ALU_MULHU  = 5'b10011;
    localparam ALU_DIV    = 5'b10100;
    localparam ALU_DIVU   = 5'b10101;
    localparam ALU_REM    = 5'b10110;
    localparam ALU_REMU   = 5'b10111;

    localparam [31:0] MIN_INT = 32'h80000000;

    // ============================================================
    // INTERNAL REGISTERS
    // ============================================================
    reg [5:0]  cnt;

    reg [31:0] dividend;
    reg [31:0] divisor;
    reg [31:0] quotient;
    reg [32:0] remainder;

    reg sign_q;
    reg sign_r;
    reg is_rem;

    // ============================================================
    // OP DECODE
    // ============================================================
    wire is_mul =
        (op == ALU_MUL)    ||
        (op == ALU_MULH)   ||
        (op == ALU_MULHSU) ||
        (op == ALU_MULHU);

    wire is_divrem =
        (op == ALU_DIV)  ||
        (op == ALU_DIVU) ||
        (op == ALU_REM)  ||
        (op == ALU_REMU);

    // ============================================================
    // MULTIPLICATION
    // MUL/MULH/MULHU/MULHSU xử lý trong MDU.
    // MULHSU dùng ép kiểu rõ ràng để tránh lỗi mixed signed/unsigned.
    // ============================================================
    wire signed [63:0] prod_ss;
    wire        [63:0] prod_uu;
    wire signed [64:0] prod_su;

    assign prod_ss = $signed(A) * $signed(B);
    assign prod_uu = $unsigned(A) * $unsigned(B);
    assign prod_su = $signed({A[31], A}) * $signed({1'b0, B});

    // ============================================================
    // ABS FUNCTION FOR SIGNED DIV/REM
    // ============================================================
    function [31:0] abs32;
        input [31:0] x;
        begin
            abs32 = x[31] ? (~x + 32'd1) : x;
        end
    endfunction

    // ============================================================
    // RESTORING DIVISION STEP
    // Mỗi cycle xử lý 1 bit.
    // ============================================================
    wire [32:0] rem_shift;
    wire [31:0] div_shift;
    wire        can_sub;
    wire [32:0] rem_next;
    wire [31:0] quo_next;

    assign rem_shift = {remainder[31:0], dividend[31]};
    assign div_shift = {dividend[30:0], 1'b0};

    assign can_sub   = (rem_shift >= {1'b0, divisor});
    assign rem_next  = can_sub ? (rem_shift - {1'b0, divisor}) : rem_shift;
    assign quo_next  = {quotient[30:0], can_sub};

    // ============================================================
    // MAIN FSM
    // ============================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy      <= 1'b0;
            done      <= 1'b0;
            result    <= 32'd0;

            cnt       <= 6'd0;
            dividend  <= 32'd0;
            divisor   <= 32'd0;
            quotient  <= 32'd0;
            remainder <= 33'd0;

            sign_q    <= 1'b0;
            sign_r    <= 1'b0;
            is_rem    <= 1'b0;
        end
        else begin
            done <= 1'b0;

            // ====================================================
            // START NEW OPERATION
            // ====================================================
            if (start && !busy) begin

                // ------------------------------
                // MUL group: 1-cycle latency
                // ------------------------------
                if (is_mul) begin
                    busy <= 1'b1;
                    cnt  <= 6'd1;

                    case (op)
                        ALU_MUL: begin
                            result <= prod_ss[31:0];
                        end

                        ALU_MULH: begin
                            result <= prod_ss[63:32];
                        end

                        ALU_MULHSU: begin
                            result <= prod_su[63:32];
                        end

                        ALU_MULHU: begin
                            result <= prod_uu[63:32];
                        end

                        default: begin
                            result <= 32'd0;
                        end
                    endcase
                end

                // ------------------------------
                // DIV/REM group
                // ------------------------------
                else if (is_divrem) begin

                    // Case 1: divide by zero
                    if (B == 32'd0) begin
                        busy <= 1'b1;
                        cnt  <= 6'd1;

                        case (op)
                            ALU_DIV: begin
                                result <= 32'hffffffff;
                            end

                            ALU_DIVU: begin
                                result <= 32'hffffffff;
                            end

                            ALU_REM: begin
                                result <= A;
                            end

                            ALU_REMU: begin
                                result <= A;
                            end

                            default: begin
                                result <= 32'd0;
                            end
                        endcase
                    end

                    // Case 2: signed overflow
                    // 0x80000000 / -1 = 0x80000000
                    // 0x80000000 % -1 = 0
                    else if (
                        ((op == ALU_DIV) || (op == ALU_REM)) &&
                        (A == MIN_INT) &&
                        (B == 32'hffffffff)
                    ) begin
                        busy <= 1'b1;
                        cnt  <= 6'd1;

                        if (op == ALU_DIV)
                            result <= MIN_INT;
                        else
                            result <= 32'd0;
                    end

                    // Case 3: normal division
                    else begin
                        busy <= 1'b1;
                        cnt  <= 6'd32;

                        is_rem <= (op == ALU_REM) || (op == ALU_REMU);

                        sign_q <= ((op == ALU_DIV) || (op == ALU_REM)) &&
                                  (A[31] ^ B[31]);

                        sign_r <= ((op == ALU_DIV) || (op == ALU_REM)) &&
                                  A[31];

                        dividend  <= ((op == ALU_DIV) || (op == ALU_REM)) ? abs32(A) : A;
                        divisor   <= ((op == ALU_DIV) || (op == ALU_REM)) ? abs32(B) : B;
                        quotient  <= 32'd0;
                        remainder <= 33'd0;
                    end
                end

                // Unknown op
                else begin
                    busy   <= 1'b0;
                    done   <= 1'b0;
                    result <= 32'd0;
                    cnt    <= 6'd0;
                end
            end

            // ====================================================
            // OPERATION RUNNING
            // ====================================================
            else if (busy) begin

                // Last cycle: operation done
                if (cnt == 6'd1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    cnt  <= 6'd0;
                end

                // Division iteration
                else begin
                    dividend  <= div_shift;
                    remainder <= rem_next;
                    quotient  <= quo_next;
                    cnt       <= cnt - 6'd1;

                    // cnt == 2 means rem_next/quo_next is final result
                    if (cnt == 6'd2) begin
                        if (is_rem) begin
                            result <= sign_r ? (~rem_next[31:0] + 32'd1)
                                             : rem_next[31:0];
                        end
                        else begin
                            result <= sign_q ? (~quo_next + 32'd1)
                                             : quo_next;
                        end
                    end
                end
            end
        end
    end

endmodule