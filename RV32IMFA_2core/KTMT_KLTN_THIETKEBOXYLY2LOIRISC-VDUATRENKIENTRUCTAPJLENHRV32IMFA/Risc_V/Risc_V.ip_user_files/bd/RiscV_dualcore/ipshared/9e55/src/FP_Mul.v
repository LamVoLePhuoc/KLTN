(* multstyle = "dsp" *)
module FP_Mul (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] A,
    input  wire [31:0] B,
    output reg  [31:0] Mul_Out
);

    integer i;
    wire [23:0] mA = {1'b1, A[22:0]};
    wire [23:0] mB = {1'b1, B[22:0]};
    wire [24:0] mB_ext = {mB, 1'b0};

    // ========================================================
    // STAGE 1: BOOTH ENCODING (Chỉ tạo giá trị thô, chưa dịch)
    // ========================================================
    reg signed [25:0] s1_raw_pp [0:12];
    reg [8:0] s1_exp; reg s1_sign, s1_nan, s1_inf, s1_zero;

    always @(posedge clk) begin
        s1_sign <= A[31] ^ B[31];
        s1_exp  <= A[30:23] + B[30:23] - 8'd127;
        s1_nan  <= (A[30:23] == 8'hFF && A[22:0] != 0) || (B[30:23] == 8'hFF && B[22:0] != 0);
        s1_inf  <= (A[30:23] == 8'hFF) || (B[30:23] == 8'hFF);
        s1_zero <= (A[30:23] == 0) || (B[30:23] == 0);

        for (i = 0; i < 12; i = i + 1) begin
            case (mB_ext[i*2 +: 3])
                3'b001, 3'b010: s1_raw_pp[i] <= $signed({2'b0, mA});
                3'b011:          s1_raw_pp[i] <= $signed({1'b0, mA, 1'b0});
                3'b100:          s1_raw_pp[i] <= -$signed({1'b0, mA, 1'b0});
                3'b101, 3'b110: s1_raw_pp[i] <= -$signed({2'b0, mA});
                default:         s1_raw_pp[i] <= 26'd0;
            endcase
        end
        s1_raw_pp[12] <= (mB_ext[24:23] == 2'b01) ? $signed({2'b0, mA}) : 
                         (mB_ext[24:23] == 2'b10) ? -$signed({2'b0, mA}) : 26'd0;
    end

    // ========================================================
    // STAGE 2: DỊCH BIT & CỘNG TẦNG 1 (13 hàng -> 7 hàng)
    // ========================================================
    reg signed [47:0] s2_pp_shifted [0:12];
    reg [47:0] s2_tree_l1 [0:6];
    reg [8:0] s2_exp; reg s2_sign, s2_nan, s2_inf, s2_zero;

    always @(posedge clk) begin
        for (i = 0; i < 13; i = i + 1) s2_pp_shifted[i] <= $signed(s1_raw_pp[i]) << (i*2);
        
        s2_tree_l1[0] <= s2_pp_shifted[0] + s2_pp_shifted[1];
        s2_tree_l1[1] <= s2_pp_shifted[2] + s2_pp_shifted[3];
        s2_tree_l1[2] <= s2_pp_shifted[4] + s2_pp_shifted[5];
        s2_tree_l1[3] <= s2_pp_shifted[6] + s2_pp_shifted[7];
        s2_tree_l1[4] <= s2_pp_shifted[8] + s2_pp_shifted[9];
        s2_tree_l1[5] <= s2_pp_shifted[10] + s2_pp_shifted[11];
        s2_tree_l1[6] <= s2_pp_shifted[12];

        s2_exp <= s1_exp; s2_sign <= s1_sign;
        s2_nan <= s1_nan; s2_inf <= s1_inf; s2_zero <= s1_zero;
    end

    // ========================================================
    // STAGE 3: CỘNG TẦNG 2 (7 hàng -> 2 hàng final)
    // ========================================================
    reg [47:0] s3_tree_l2 [0:1];
    reg [8:0] s3_exp; reg s3_sign, s3_nan, s3_inf, s3_zero;

    always @(posedge clk) begin
        s3_tree_l2[0] <= (s2_tree_l1[0] + s2_tree_l1[1]) + (s2_tree_l1[2] + s2_tree_l1[3]);
        s3_tree_l2[1] <= (s2_tree_l1[4] + s2_tree_l1[5]) + s2_tree_l1[6];
        
        s3_exp <= s2_exp; s3_sign <= s2_sign;
        s3_nan <= s2_nan; s3_inf <= s2_inf; s3_zero <= s2_zero;
    end

    // ========================================================
    // STAGE 4: CỘNG CUỐI & INJECTION ROUNDING
    // ========================================================
    reg [47:0] s4_prod_final;
    reg [8:0] s4_exp; reg s4_sign, s4_nan, s4_inf, s4_zero;

    always @(posedge clk) begin
        s4_prod_final <= (s3_tree_l2[0] + s3_tree_l2[1]) + 48'h000000400000;
        s4_exp <= s3_exp; s4_sign <= s3_sign;
        s4_nan <= s3_nan; s4_inf <= s3_inf; s4_zero <= s3_zero;
    end

    // ========================================================
    // STAGE 5: CHUẨN HÓA & XUẤT KẾT QUẢ
    // ========================================================
    always @(posedge clk) begin
        if (s4_nan) Mul_Out <= 32'h7FC00000;
        else if (s4_inf) Mul_Out <= {s4_sign, 8'hFF, 23'h0};
        else if (s4_zero || s4_exp[8]) Mul_Out <= {s4_sign, 31'h0};
        else if (s4_prod_final[47]) Mul_Out <= {s4_sign, s4_exp[7:0] + 8'd1, s4_prod_final[46:24]};
        else Mul_Out <= {s4_sign, s4_exp[7:0], s4_prod_final[45:23]};
    end
endmodule