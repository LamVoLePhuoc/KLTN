`timescale 1ns / 1ps

module FP_CVT (
    input  wire [4:0]  op,
    input  wire [31:0] in_data,
    output reg  [31:0] out_data
);

    localparam [4:0]
        FCVT_W_S  = 5'b01101,
        FCVT_WU_S = 5'b01110,
        FCVT_S_W  = 5'b01111,
        FCVT_S_WU = 5'b10000;

    wire        f_sign = in_data[31];
    wire [7:0]  f_exp  = in_data[30:23];
    wire [22:0] f_frac = in_data[22:0];

    wire f_is_zero      = (f_exp == 8'h00) && (f_frac == 23'd0);
    wire f_is_subnormal = (f_exp == 8'h00) && (f_frac != 23'd0);
    wire f_is_inf       = (f_exp == 8'hff) && (f_frac == 23'd0);
    wire f_is_nan       = (f_exp == 8'hff) && (f_frac != 23'd0);

    wire [23:0] f_mant = (f_exp == 8'h00) ? {1'b0, f_frac} : {1'b1, f_frac};
    wire signed [9:0] f_unbias_exp = $signed({2'b00, f_exp}) - 10'sd127;

    reg [63:0] abs_val_64;
    reg [31:0] int_result;

    reg [31:0] int_abs_32;
    reg [31:0] shifted_int;

    reg [7:0]  out_exp;
    reg [22:0] out_frac;
    reg        out_sign;

    integer i;
    integer msb_index;
    integer shift;
    reg found;

    always @(*) begin
        out_data = 32'd0;

        abs_val_64 = 64'd0;
        int_result = 32'd0;
        int_abs_32 = 32'd0;
        shifted_int = 32'd0;

        out_exp  = 8'd0;
        out_frac = 23'd0;
        out_sign = 1'b0;

        msb_index = 0;
        shift = 0;
        found = 1'b0;

        case (op)

            // ====================================================
            // FCVT.W.S: float -> signed int
            // truncate toward zero
            // ====================================================
            FCVT_W_S: begin
                if (f_is_nan) begin
                    out_data = 32'h80000000;
                end
                else if (f_is_inf) begin
                    out_data = f_sign ? 32'h80000000 : 32'h7fffffff;
                end
                else if (f_is_zero || f_is_subnormal || (f_unbias_exp < 0)) begin
                    out_data = 32'd0;
                end
                else if (f_unbias_exp > 30) begin
                    out_data = f_sign ? 32'h80000000 : 32'h7fffffff;
                end
                else begin
                    if (f_unbias_exp >= 23)
                        abs_val_64 = {40'd0, f_mant} << (f_unbias_exp - 23);
                    else
                        abs_val_64 = {40'd0, f_mant} >> (23 - f_unbias_exp);

                    if (f_sign)
                        out_data = ~abs_val_64[31:0] + 32'd1;
                    else
                        out_data = abs_val_64[31:0];
                end
            end

            // ====================================================
            // FCVT.WU.S: float -> unsigned int
            // truncate toward zero
            // ====================================================
            FCVT_WU_S: begin
                if (f_is_nan) begin
                    out_data = 32'hffffffff;
                end
                else if (f_is_inf) begin
                    out_data = f_sign ? 32'd0 : 32'hffffffff;
                end
                else if (f_sign) begin
                    out_data = 32'd0;
                end
                else if (f_is_zero || f_is_subnormal || (f_unbias_exp < 0)) begin
                    out_data = 32'd0;
                end
                else if (f_unbias_exp > 31) begin
                    out_data = 32'hffffffff;
                end
                else begin
                    if (f_unbias_exp >= 23)
                        abs_val_64 = {40'd0, f_mant} << (f_unbias_exp - 23);
                    else
                        abs_val_64 = {40'd0, f_mant} >> (23 - f_unbias_exp);

                    out_data = abs_val_64[31:0];
                end
            end

            // ====================================================
            // FCVT.S.W: signed int -> float
            // simple rounding: truncate mantissa
            // ====================================================
            FCVT_S_W: begin
                if (in_data == 32'd0) begin
                    out_data = 32'd0;
                end
                else begin
                    out_sign = in_data[31];

                    if (in_data[31])
                        int_abs_32 = ~in_data + 32'd1;
                    else
                        int_abs_32 = in_data;

                    found = 1'b0;
                    msb_index = 0;

                    for (i = 31; i >= 0; i = i - 1) begin
                        if (!found && int_abs_32[i]) begin
                            found = 1'b1;
                            msb_index = i;
                        end
                    end

                    out_exp = msb_index + 127;

                    if (msb_index >= 23) begin
                        shift = msb_index - 23;
                        shifted_int = int_abs_32 >> shift;
                    end
                    else begin
                        shift = 23 - msb_index;
                        shifted_int = int_abs_32 << shift;
                    end

                    out_frac = shifted_int[22:0];
                    out_data = {out_sign, out_exp, out_frac};
                end
            end

            // ====================================================
            // FCVT.S.WU: unsigned int -> float
            // simple rounding: truncate mantissa
            // ====================================================
            FCVT_S_WU: begin
                if (in_data == 32'd0) begin
                    out_data = 32'd0;
                end
                else begin
                    out_sign = 1'b0;

                    found = 1'b0;
                    msb_index = 0;

                    for (i = 31; i >= 0; i = i - 1) begin
                        if (!found && in_data[i]) begin
                            found = 1'b1;
                            msb_index = i;
                        end
                    end

                    out_exp = msb_index + 127;

                    if (msb_index >= 23) begin
                        shift = msb_index - 23;
                        shifted_int = in_data >> shift;
                    end
                    else begin
                        shift = 23 - msb_index;
                        shifted_int = in_data << shift;
                    end

                    out_frac = shifted_int[22:0];
                    out_data = {out_sign, out_exp, out_frac};
                end
            end

            default: begin
                out_data = 32'd0;
            end

        endcase
    end

endmodule