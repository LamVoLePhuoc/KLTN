`timescale 1ns / 1ps

module FP_Sqrt (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_start,
    input  wire [31:0] in_A,
    output reg         out_stall,
    output reg  [31:0] out_res
);

    localparam [31:0] CANONICAL_NAN = 32'h7fc00000;

    localparam S_IDLE = 1'b0;
    localparam S_DONE = 1'b1;

    reg state;

    wire        sign = in_A[31];
    wire [7:0]  exp  = in_A[30:23];
    wire [22:0] frac = in_A[22:0];

    wire is_zero = (exp == 8'h00) && (frac == 23'd0);
    wire is_inf  = (exp == 8'hff) && (frac == 23'd0);
    wire is_nan  = (exp == 8'hff) && (frac != 23'd0);

    reg [23:0] mant;
    reg signed [10:0] exp_unbias;
    reg signed [10:0] exp_sqrt;
    reg signed [10:0] exp_out;

    reg [47:0] radicand;
    reg [23:0] root;
    reg [23:0] root_shifted;
    reg [22:0] frac_out;

    // ============================================================
    // Integer sqrt for 48-bit radicand -> 24-bit root
    // Restoring square-root algorithm
    // ============================================================
    function [23:0] isqrt48;
        input [47:0] x;
        integer i;
        reg [49:0] rem;
        reg [24:0] root_tmp;
        reg [49:0] trial;
        reg [1:0]  pair_bits;
        begin
            rem      = 50'd0;
            root_tmp = 25'd0;

            for (i = 23; i >= 0; i = i - 1) begin
                pair_bits = (x >> (2*i)) & 2'b11;

                rem      = {rem[47:0], pair_bits};
                root_tmp = root_tmp << 1;
                trial    = (root_tmp << 1) | 50'd1;

                if (rem >= trial) begin
                    rem      = rem - trial;
                    root_tmp = root_tmp | 25'd1;
                end
            end

            isqrt48 = root_tmp[23:0];
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            out_stall <= 1'b0;
            out_res   <= 32'd0;
        end
        else begin
            case (state)

                S_IDLE: begin
                    out_stall <= 1'b0;

                    if (in_start) begin
                        out_stall <= 1'b1;

                        if (is_nan) begin
                            out_res <= CANONICAL_NAN;
                        end
                        else if (sign && !is_zero) begin
                            out_res <= CANONICAL_NAN;
                        end
                        else if (is_inf) begin
                            out_res <= in_A;
                        end
                        else if (is_zero) begin
                            out_res <= in_A;
                        end
                        else begin
                            // Normal only for now. Subnormal treated with hidden bit = 0.
                            mant = (exp == 8'd0) ? {1'b0, frac} : {1'b1, frac};

                            exp_unbias = $signed({3'b000, exp}) - 11'sd127;

                            // If exponent is odd:
                            // sqrt(m * 2^E) = sqrt((2m) * 2^(E-1))
                            if (exp_unbias[0]) begin
                                radicand = ({23'd0, mant, 1'b0}) << 23;
                                exp_sqrt = (exp_unbias - 11'sd1) >>> 1;
                            end
                            else begin
                                radicand = ({24'd0, mant}) << 23;
                                exp_sqrt = exp_unbias >>> 1;
                            end

                            root = isqrt48(radicand);
                            exp_out = exp_sqrt + 11'sd127;

                            // root should normally have bit 23 = 1 for normalized result
                            if (root[23]) begin
                                frac_out = root[22:0];
                            end
                            else begin
                                root_shifted = root << 1;
                                frac_out = root_shifted[22:0];
                                exp_out = exp_out - 11'sd1;
                            end

                            if (exp_out >= 11'sd255) begin
                                out_res <= {1'b0, 8'hff, 23'd0};
                            end
                            else if (exp_out <= 11'sd0) begin
                                out_res <= 32'd0;
                            end
                            else begin
                                out_res <= {1'b0, exp_out[7:0], frac_out};
                            end
                        end

                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    out_stall <= 1'b0;
                    state     <= S_IDLE;
                end

                default: begin
                    state     <= S_IDLE;
                    out_stall <= 1'b0;
                    out_res   <= 32'd0;
                end

            endcase
        end
    end

endmodule