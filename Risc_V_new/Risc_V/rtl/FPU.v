`timescale 1ns / 1ps

`include "FP_sqrt.v"
`include "FP_CVT.v"
`include "FP_FMA.v"

module FPU (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_start,
    input  wire [4:0]  in_opcode,

    input  wire [31:0] in_rs1,
    input  wire [31:0] in_rs2,
    input  wire [31:0] in_rs3,

    output reg  [31:0] out_data,
    output reg         out_valid,
    output wire        out_stall
);

    // ============================================================
    // 1. FPU CONTROL ENCODING
    // Phai khop voi FPU_Decoder.v
    // ============================================================
    localparam [4:0]
        FADD_S      = 5'b00000,
        FSUB_S      = 5'b00001,
        FMUL_S      = 5'b00010,
        FDIV_S      = 5'b00011,
        FSQRT_S     = 5'b00100,

        FSGNJ_S     = 5'b00101,
        FSGNJN_S    = 5'b00110,
        FSGNJX_S    = 5'b00111,

        FEQ_S       = 5'b01000,
        FLT_S       = 5'b01001,
        FLE_S       = 5'b01010,

        FMIN_S      = 5'b01011,
        FMAX_S      = 5'b01100,

        FCVT_W_S    = 5'b01101,
        FCVT_WU_S   = 5'b01110,
        FCVT_S_W    = 5'b01111,
        FCVT_S_WU   = 5'b10000,

        FMV_X_W     = 5'b10001,
        FMV_W_X     = 5'b10010,
        FCLASS_S    = 5'b10011,

        FMADD_S     = 5'b10100,
        FMSUB_S     = 5'b10101,
        FNMSUB_S    = 5'b10110,
        FNMADD_S    = 5'b10111,

        INVALID_FPU = 5'b11111;

    localparam [31:0] CANONICAL_NAN = 32'h7fc00000;

    // ============================================================
    // 2. OPCODE GROUP DETECT
    // Dung de output mux khong lay nham ket qua cu.
    // ============================================================
    wire is_pipe_opcode;
    wire is_div_opcode;
    wire is_sqrt_opcode;
    wire is_fma_opcode;
    wire is_fast_opcode;

    assign is_pipe_opcode =
        (in_opcode == FADD_S) ||
        (in_opcode == FSUB_S) ||
        (in_opcode == FMUL_S);

    assign is_div_opcode  = (in_opcode == FDIV_S);
    assign is_sqrt_opcode = (in_opcode == FSQRT_S);

    assign is_fma_opcode =
        (in_opcode == FMADD_S)  ||
        (in_opcode == FMSUB_S)  ||
        (in_opcode == FNMSUB_S) ||
        (in_opcode == FNMADD_S);

    assign is_fast_opcode =
        (in_opcode == FSGNJ_S)   ||
        (in_opcode == FSGNJN_S)  ||
        (in_opcode == FSGNJX_S)  ||
        (in_opcode == FEQ_S)     ||
        (in_opcode == FLT_S)     ||
        (in_opcode == FLE_S)     ||
        (in_opcode == FMIN_S)    ||
        (in_opcode == FMAX_S)    ||
        (in_opcode == FCVT_W_S)  ||
        (in_opcode == FCVT_WU_S) ||
        (in_opcode == FCVT_S_W)  ||
        (in_opcode == FCVT_S_WU) ||
        (in_opcode == FMV_X_W)   ||
        (in_opcode == FMV_W_X)   ||
        (in_opcode == FCLASS_S)  ||
        (in_opcode == INVALID_FPU);

    // ============================================================
    // 3. FLOAT FIELD HELPERS
    // ============================================================
    wire        rs1_sign = in_rs1[31];
    wire        rs2_sign = in_rs2[31];

    wire [7:0]  rs1_exp  = in_rs1[30:23];
    wire [7:0]  rs2_exp  = in_rs2[30:23];

    wire [22:0] rs1_frac = in_rs1[22:0];
    wire [22:0] rs2_frac = in_rs2[22:0];

    wire rs1_is_zero      = (rs1_exp == 8'h00) && (rs1_frac == 23'd0);
    wire rs2_is_zero      = (rs2_exp == 8'h00) && (rs2_frac == 23'd0);

    wire rs1_is_subnormal = (rs1_exp == 8'h00) && (rs1_frac != 23'd0);

    wire rs1_is_inf       = (rs1_exp == 8'hff) && (rs1_frac == 23'd0);
    wire rs2_is_inf       = (rs2_exp == 8'hff) && (rs2_frac == 23'd0);

    wire rs1_is_nan       = (rs1_exp == 8'hff) && (rs1_frac != 23'd0);
    wire rs2_is_nan       = (rs2_exp == 8'hff) && (rs2_frac != 23'd0);

    wire rs1_is_snan      = rs1_is_nan && (rs1_frac[22] == 1'b0);
    wire rs1_is_qnan      = rs1_is_nan && (rs1_frac[22] == 1'b1);

    // ============================================================
    // 4. ADD / SUB INPUT
    // ============================================================
    reg [31:0] operand_b_adder;

    always @(*) begin
        if (in_opcode == FSUB_S)
            operand_b_adder = {~in_rs2[31], in_rs2[30:0]};
        else
            operand_b_adder = in_rs2;
    end

    // ============================================================
    // 5. COMPUTE MODULES
    // ============================================================

    // ----------------------------
    // FADD / FSUB
    // ----------------------------
    wire [31:0] w_add_out;

    FP_Add u_adder (
        .clk   (clk),
        .rst_n (rst_n),
        .A     (in_rs1),
        .B     (operand_b_adder),
        .Out   (w_add_out)
    );

    // ----------------------------
    // FMUL
    // ----------------------------
    wire [31:0] w_mul_out;

    FP_Mul u_multiplier (
        .clk     (clk),
        .rst_n   (rst_n),
        .A       (in_rs1),
        .B       (in_rs2),
        .Mul_Out (w_mul_out)
    );

    // ----------------------------
    // FDIV
    // ----------------------------
    wire [31:0] w_div_out;
    wire        w_div_stall;
    wire        w_div_start;

    assign w_div_start = in_start && is_div_opcode;

    FP_Div u_divider (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_start  (w_div_start),
        .in_A      (in_rs1),
        .in_B      (in_rs2),
        .out_stall (w_div_stall),
        .out_res   (w_div_out)
    );

    // ----------------------------
    // FSQRT
    // ----------------------------
    wire [31:0] w_sqrt_out;
    wire        w_sqrt_stall;
    wire        w_sqrt_start;

    assign w_sqrt_start = in_start && is_sqrt_opcode;

    FP_Sqrt u_sqrt (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_start  (w_sqrt_start),
        .in_A      (in_rs1),
        .out_stall (w_sqrt_stall),
        .out_res   (w_sqrt_out)
    );

    // ----------------------------
    // FCVT
    // ----------------------------
    wire [31:0] w_cvt_out;

    FP_CVT u_cvt (
        .op       (in_opcode),
        .in_data  (in_rs1),
        .out_data (w_cvt_out)
    );

    // ----------------------------
    // FMA group
    // ----------------------------
    wire [31:0] w_fma_out;
    wire        w_fma_stall;
    wire        w_fma_start;

    assign w_fma_start = in_start && is_fma_opcode;

    FP_FMA u_fma (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_start  (w_fma_start),
        .in_opcode (in_opcode),
        .in_A      (in_rs1),
        .in_B      (in_rs2),
        .in_C      (in_rs3),
        .out_stall (w_fma_stall),
        .out_res   (w_fma_out)
    );

    assign out_stall = w_div_stall | w_sqrt_stall | w_fma_stall;

    // ============================================================
    // 6. COMPARE LOGIC
    // FEQ/FLT/FLE voi NaN -> 0
    // +0 va -0 duoc xem la bang nhau
    // ============================================================
    reg cmp_eq;
    reg cmp_lt;

    always @(*) begin
        cmp_eq = 1'b0;
        cmp_lt = 1'b0;

        if (!rs1_is_nan && !rs2_is_nan) begin
            if (rs1_is_zero && rs2_is_zero) begin
                cmp_eq = 1'b1;
                cmp_lt = 1'b0;
            end
            else begin
                cmp_eq = (in_rs1 == in_rs2);

                if (rs1_sign != rs2_sign) begin
                    cmp_lt = rs1_sign;
                end
                else begin
                    if (rs1_sign)
                        cmp_lt = (in_rs1 > in_rs2);
                    else
                        cmp_lt = (in_rs1 < in_rs2);
                end
            end
        end
    end

    // ============================================================
    // 7. FMIN / FMAX LOGIC
    // NaN co ban:
    // - 1 operand NaN -> tra operand con lai
    // - ca 2 NaN -> canonical NaN
    // ============================================================
    reg [31:0] minmax_res;

    always @(*) begin
        minmax_res = 32'd0;

        if (rs1_is_nan && rs2_is_nan) begin
            minmax_res = CANONICAL_NAN;
        end
        else if (rs1_is_nan) begin
            minmax_res = in_rs2;
        end
        else if (rs2_is_nan) begin
            minmax_res = in_rs1;
        end
        else if (rs1_is_zero && rs2_is_zero) begin
            if (in_opcode == FMIN_S)
                minmax_res = (rs1_sign || rs2_sign) ? 32'h80000000 : 32'h00000000;
            else
                minmax_res = (rs1_sign && rs2_sign) ? 32'h80000000 : 32'h00000000;
        end
        else begin
            if (in_opcode == FMIN_S)
                minmax_res = cmp_lt ? in_rs1 : in_rs2;
            else
                minmax_res = cmp_lt ? in_rs2 : in_rs1;
        end
    end

    // ============================================================
    // 8. FCLASS.S LOGIC
    // bit 0 : -inf
    // bit 1 : negative normal
    // bit 2 : negative subnormal
    // bit 3 : -0
    // bit 4 : +0
    // bit 5 : positive subnormal
    // bit 6 : positive normal
    // bit 7 : +inf
    // bit 8 : signaling NaN
    // bit 9 : quiet NaN
    // ============================================================
    reg [31:0] class_res;

    always @(*) begin
        class_res = 32'd0;

        if (rs1_is_inf && rs1_sign)
            class_res[0] = 1'b1;
        else if (rs1_sign && (rs1_exp != 8'h00) && (rs1_exp != 8'hff))
            class_res[1] = 1'b1;
        else if (rs1_sign && rs1_is_subnormal)
            class_res[2] = 1'b1;
        else if (rs1_sign && rs1_is_zero)
            class_res[3] = 1'b1;
        else if (!rs1_sign && rs1_is_zero)
            class_res[4] = 1'b1;
        else if (!rs1_sign && rs1_is_subnormal)
            class_res[5] = 1'b1;
        else if (!rs1_sign && (rs1_exp != 8'h00) && (rs1_exp != 8'hff))
            class_res[6] = 1'b1;
        else if (rs1_is_inf && !rs1_sign)
            class_res[7] = 1'b1;
        else if (rs1_is_snan)
            class_res[8] = 1'b1;
        else if (rs1_is_qnan)
            class_res[9] = 1'b1;
    end

    // ============================================================
    // 9. PIPELINE / DONE TRACKING
    // FP_Add / FP_Mul latency hien dang gia dinh 5 cycles
    // ============================================================
    reg [4:0] pipe_valid;
    reg [4:0] pipe_is_adder;

    reg [31:0] r_fast_res;
    reg        r_fast_valid;

    reg prev_div_stall;
    reg prev_sqrt_stall;
    reg prev_fma_stall;

    wire w_div_done;
    wire w_sqrt_done;
    wire w_fma_done;

    assign w_div_done  = (prev_div_stall  == 1'b1) && (w_div_stall  == 1'b0);
    assign w_sqrt_done = (prev_sqrt_stall == 1'b1) && (w_sqrt_stall == 1'b0);
    assign w_fma_done  = (prev_fma_stall  == 1'b1) && (w_fma_stall  == 1'b0);

    // ============================================================
    // 10. MAIN SEQUENTIAL LOGIC
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_valid      <= 5'b00000;
            pipe_is_adder   <= 5'b00000;

            r_fast_res      <= 32'd0;
            r_fast_valid    <= 1'b0;

            prev_div_stall  <= 1'b0;
            prev_sqrt_stall <= 1'b0;
            prev_fma_stall  <= 1'b0;
        end
        else begin
            prev_div_stall  <= w_div_stall;
            prev_sqrt_stall <= w_sqrt_stall;
            prev_fma_stall  <= w_fma_stall;

            // ----------------------------------------------------
            // 5-cycle pipeline ops: FADD / FSUB / FMUL
            // ----------------------------------------------------
            if (in_start && is_pipe_opcode) begin
                pipe_valid    <= {pipe_valid[3:0], 1'b1};
                pipe_is_adder <= {pipe_is_adder[3:0], (in_opcode != FMUL_S)};
            end
            else begin
                pipe_valid    <= {pipe_valid[3:0], 1'b0};
                pipe_is_adder <= {pipe_is_adder[3:0], 1'b0};
            end

            // ----------------------------------------------------
            // Fast path ops: 1-cycle
            // ----------------------------------------------------
            r_fast_valid <= 1'b0;
            r_fast_res   <= 32'd0;

            if (in_start && is_fast_opcode && !out_stall) begin
                case (in_opcode)

                    // Sign injection
                    FSGNJ_S: begin
                        r_fast_res   <= {in_rs2[31], in_rs1[30:0]};
                        r_fast_valid <= 1'b1;
                    end

                    FSGNJN_S: begin
                        r_fast_res   <= {~in_rs2[31], in_rs1[30:0]};
                        r_fast_valid <= 1'b1;
                    end

                    FSGNJX_S: begin
                        r_fast_res   <= {in_rs1[31] ^ in_rs2[31], in_rs1[30:0]};
                        r_fast_valid <= 1'b1;
                    end

                    // Compare
                    FEQ_S: begin
                        r_fast_res   <= {31'd0, cmp_eq};
                        r_fast_valid <= 1'b1;
                    end

                    FLT_S: begin
                        r_fast_res   <= {31'd0, cmp_lt};
                        r_fast_valid <= 1'b1;
                    end

                    FLE_S: begin
                        r_fast_res   <= {31'd0, (cmp_lt || cmp_eq)};
                        r_fast_valid <= 1'b1;
                    end

                    // Min / Max
                    FMIN_S,
                    FMAX_S: begin
                        r_fast_res   <= minmax_res;
                        r_fast_valid <= 1'b1;
                    end

                    // Move raw bits
                    FMV_X_W,
                    FMV_W_X: begin
                        r_fast_res   <= in_rs1;
                        r_fast_valid <= 1'b1;
                    end

                    // Classify
                    FCLASS_S: begin
                        r_fast_res   <= class_res;
                        r_fast_valid <= 1'b1;
                    end

                    // Convert
                    FCVT_W_S,
                    FCVT_WU_S,
                    FCVT_S_W,
                    FCVT_S_WU: begin
                        r_fast_res   <= w_cvt_out;
                        r_fast_valid <= 1'b1;
                    end

                    INVALID_FPU: begin
                        r_fast_res   <= 32'd0;
                        r_fast_valid <= 1'b1;
                    end

                    default: begin
                        r_fast_res   <= 32'd0;
                        r_fast_valid <= 1'b0;
                    end

                endcase
            end
        end
    end

    // ============================================================
    // 11. OUTPUT MUX
    //
    // Quan trong:
    // Chi tra ket qua dung voi nhom opcode hien tai.
    // Neu khong gate nhu vay, FSQRT co the lay nham ket qua cu cua FADD.
    // ============================================================
    always @(*) begin
        out_valid = 1'b0;
        out_data  = 32'd0;

        if (is_div_opcode && w_div_done) begin
            out_data  = w_div_out;
            out_valid = 1'b1;
        end
        else if (is_sqrt_opcode && w_sqrt_done) begin
            out_data  = w_sqrt_out;
            out_valid = 1'b1;
        end
        else if (is_fma_opcode && w_fma_done) begin
            out_data  = w_fma_out;
            out_valid = 1'b1;
        end
        else if (is_pipe_opcode && pipe_valid[4]) begin
            out_data  = pipe_is_adder[4] ? w_add_out : w_mul_out;
            out_valid = 1'b1;
        end
        else if (is_fast_opcode && r_fast_valid) begin
            out_data  = r_fast_res;
            out_valid = 1'b1;
        end
    end

endmodule