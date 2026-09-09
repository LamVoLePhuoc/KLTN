module FP_Add (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] A,
    input  wire [31:0] B,
    output reg  [31:0] Out
);

    // --- Khai báo dây (wires) cho Stage 1 ---
    wire [7:0]  eA = A[30:23];
    wire [7:0]  eB = B[30:23];
    wire [23:0] mA = (eA == 0) ? {1'b0, A[22:0]} : {1'b1, A[22:0]};
    wire [23:0] mB = (eB == 0) ? {1'b0, B[22:0]} : {1'b1, B[22:0]};

    // --- Stage 1 Registers ---
    reg [26:0] s1_mA, s1_mB;
    reg [7:0]  s1_exp;
    reg        s1_sgnA, s1_sgnB, s1_nan, s1_inf, s1_inf_sub;

    always @(posedge clk) begin
        s1_sgnA <= A[31]; 
        s1_sgnB <= B[31];
        s1_nan  <= ((eA == 8'hFF) && A[22:0] != 0) || ((eB == 8'hFF) && B[22:0] != 0);
        s1_inf  <= (eA == 8'hFF) || (eB == 8'hFF);
        s1_inf_sub <= (eA == 8'hFF && eB == 8'hFF) && (A[31] != B[31]);

        if (eA >= eB) begin
            s1_exp <= eA; 
            s1_mA  <= {mA, 3'b000};
            s1_mB  <= (eA - eB >= 27) ? {26'b0, |mB} : ({mB, 3'b000} >> (eA - eB));
        end else begin
            s1_exp <= eB; 
            s1_mB  <= {mB, 3'b000};
            s1_mA  <= (eB - eA >= 27) ? {26'b0, |mA} : ({mA, 3'b000} >> (eB - eA));
        end
    end

    // --- Stage 2 Registers ---
    reg [27:0] s2_sum;
    reg [7:0]  s2_exp;
    reg        s2_sgn, s2_nan, s2_inf, s2_inf_sub;

    always @(posedge clk) begin
        s2_exp <= s1_exp; s2_nan <= s1_nan; s2_inf <= s1_inf; s2_inf_sub <= s1_inf_sub;
        if (s1_sgnA == s1_sgnB) begin
            s2_sum <= {1'b0, s1_mA} + {1'b0, s1_mB}; 
            s2_sgn <= s1_sgnA;
        end else begin
            if (s1_mA >= s1_mB) begin
                s2_sum <= {1'b0, s1_mA} - {1'b0, s1_mB}; 
                s2_sgn <= s1_sgnA;
            end else begin
                s2_sum <= {1'b0, s1_mB} - {1'b0, s1_mA}; 
                s2_sgn <= s1_sgnB;
            end
        end
    end

    // --- Stage 3 Registers: LZC ---
    reg [27:0] s3_sum;
    reg [4:0]  s3_lzc;
    reg [7:0]  s3_exp;
    reg        s3_sgn, s3_nan, s3_inf, s3_inf_sub;

    always @(posedge clk) begin
        s3_sum <= s2_sum; s3_exp <= s2_exp; s3_sgn <= s2_sgn;
        s3_nan <= s2_nan; s3_inf <= s2_inf; s3_inf_sub <= s2_inf_sub;
        casez (s2_sum[26:0])
            27'b1??????????????????????????: s3_lzc <= 5'd0;
            27'b01?????????????????????????: s3_lzc <= 5'd1;
            27'b001????????????????????????: s3_lzc <= 5'd2;
            27'b0001???????????????????????: s3_lzc <= 5'd3;
            27'b00001??????????????????????: s3_lzc <= 5'd4;
            27'b000001?????????????????????: s3_lzc <= 5'd5;
            27'b0000001????????????????????: s3_lzc <= 5'd6;
            27'b00000001???????????????????: s3_lzc <= 5'd7;
            27'b000000001??????????????????: s3_lzc <= 5'd8;
            27'b0000000001?????????????????: s3_lzc <= 5'd9;
            27'b00000000001????????????????: s3_lzc <= 5'd10;
            27'b000000000001???????????????: s3_lzc <= 5'd11;
            27'b0000000000001??????????????: s3_lzc <= 5'd12;
            27'b00000000000001?????????????: s3_lzc <= 5'd13;
            27'b000000000000001????????????: s3_lzc <= 5'd14;
            27'b0000000000000001???????????: s3_lzc <= 5'd15;
            27'b00000000000000001??????????: s3_lzc <= 5'd16;
            27'b000000000000000001?????????: s3_lzc <= 5'd17;
            27'b0000000000000000001????????: s3_lzc <= 5'd18;
            27'b00000000000000000001???????: s3_lzc <= 5'd19;
            27'b000000000000000000001??????: s3_lzc <= 5'd20;
            27'b0000000000000000000001?????: s3_lzc <= 5'd21;
            27'b00000000000000000000001????: s3_lzc <= 5'd22;
            27'b000000000000000000000001???: s3_lzc <= 5'd23;
            27'b0000000000000000000000001??: s3_lzc <= 5'd24;
            27'b00000000000000000000000001?: s3_lzc <= 5'd25;
            27'b000000000000000000000000001: s3_lzc <= 5'd26;
            default:                         s3_lzc <= 5'd27;
        endcase
    end

    // --- Stage 4 Registers: Normalize ---
    reg [27:0] s4_norm_m;
    reg [8:0]  s4_exp;
    reg        s4_sgn, s4_nan, s4_inf, s4_inf_sub, s4_is_zero;

    always @(posedge clk) begin
        s4_sgn <= s3_sgn; s4_nan <= s3_nan; s4_inf <= s3_inf; s4_inf_sub <= s3_inf_sub;
        s4_is_zero <= (s3_sum == 0);
        if (s3_sum[27]) begin
            s4_norm_m <= s3_sum[27:1]; 
            s4_exp <= s3_exp + 1'b1;
        end else begin
            s4_norm_m <= s3_sum[26:0] << s3_lzc;
            s4_exp <= (s3_exp > s3_lzc) ? (s3_exp - s3_lzc) : 8'd0;
        end
    end

    // --- Stage 5: Rounding ---
    reg [23:0] rounded; 
    always @(posedge clk) begin
        // Tính toán làm tròn
        if (s4_norm_m[2] && (s4_norm_m[1] || s4_norm_m[0] || s4_norm_m[3]))
            rounded = s4_norm_m[26:3] + 1'b1;
        else
            rounded = s4_norm_m[26:3];

        // Xuất kết quả
        if (s4_nan || s4_inf_sub) Out <= 32'h7FC00000;
        else if (s4_inf || s4_exp >= 9'h0FF) Out <= {s4_sgn, 8'hFF, 23'h0};
        else if (s4_is_zero) Out <= {s4_sgn, 31'h0};
        else Out <= {s4_sgn, s4_exp[7:0], rounded[22:0]};
    end

endmodule