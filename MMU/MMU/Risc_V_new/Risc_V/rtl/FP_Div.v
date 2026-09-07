`timescale 1ns / 1ps

module FP_Div (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_start,
    input  wire [31:0] in_A,
    input  wire [31:0] in_B,
    output reg         out_stall,
    output reg  [31:0] out_res
);

    localparam [31:0] CANONICAL_NAN = 32'h7fc00000;

    localparam S_IDLE = 1'b0;
    localparam S_DONE = 1'b1;

    reg state;

    wire sign_a = in_A[31];
    wire sign_b = in_B[31];

    wire [7:0] exp_a = in_A[30:23];
    wire [7:0] exp_b = in_B[30:23];

    wire [22:0] frac_a = in_A[22:0];
    wire [22:0] frac_b = in_B[22:0];

    wire a_zero = (exp_a == 8'h00) && (frac_a == 23'd0);
    wire b_zero = (exp_b == 8'h00) && (frac_b == 23'd0);

    wire a_inf  = (exp_a == 8'hff) && (frac_a == 23'd0);
    wire b_inf  = (exp_b == 8'hff) && (frac_b == 23'd0);

    wire a_nan  = (exp_a == 8'hff) && (frac_a != 23'd0);
    wire b_nan  = (exp_b == 8'hff) && (frac_b != 23'd0);

    reg        sign_r;
    reg signed [10:0] exp_r;
    reg [23:0] mant_a;
    reg [23:0] mant_b;

    reg [63:0] div_tmp;
    reg [25:0] quot;
    reg signed [10:0] exp_norm;
    reg [25:0] quot_norm;

    integer k;

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

                        sign_r = sign_a ^ sign_b;

                        if (a_nan || b_nan || (a_zero && b_zero) || (a_inf && b_inf)) begin
                            out_res <= CANONICAL_NAN;
                        end
                        else if (b_zero) begin
                            out_res <= {sign_r, 8'hff, 23'd0};
                        end
                        else if (a_zero) begin
                            out_res <= {sign_r, 31'd0};
                        end
                        else if (a_inf) begin
                            out_res <= {sign_r, 8'hff, 23'd0};
                        end
                        else if (b_inf) begin
                            out_res <= {sign_r, 31'd0};
                        end
                        else begin
                            mant_a = (exp_a == 8'd0) ? {1'b0, frac_a} : {1'b1, frac_a};
                            mant_b = (exp_b == 8'd0) ? {1'b0, frac_b} : {1'b1, frac_b};

                            exp_r = $signed({3'b000, exp_a}) -
                                    $signed({3'b000, exp_b}) +
                                    11'sd127;

                            div_tmp = ({40'd0, mant_a} << 23) / mant_b;
                            quot = div_tmp[25:0];

                            exp_norm  = exp_r;
                            quot_norm = quot;

                            if (quot_norm[24]) begin
                                quot_norm = quot_norm >> 1;
                                exp_norm  = exp_norm + 11'sd1;
                            end
                            else begin
                                for (k = 0; k < 24; k = k + 1) begin
                                    if (!quot_norm[23] && (exp_norm > 0)) begin
                                        quot_norm = quot_norm << 1;
                                        exp_norm  = exp_norm - 11'sd1;
                                    end
                                end
                            end

                            if (exp_norm >= 11'sd255)
                                out_res <= {sign_r, 8'hff, 23'd0};
                            else if (exp_norm <= 11'sd0)
                                out_res <= {sign_r, 31'd0};
                            else
                                out_res <= {sign_r, exp_norm[7:0], quot_norm[22:0]};
                        end

                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    out_stall <= 1'b0;
                    state     <= S_IDLE;
                end

            endcase
        end
    end

endmodule