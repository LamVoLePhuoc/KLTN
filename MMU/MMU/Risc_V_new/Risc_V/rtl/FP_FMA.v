`timescale 1ns / 1ps
`include "FP_Mul.v"
`include "FP_Add.v"

module FP_FMA (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_start,
    input  wire [4:0]  in_opcode,

    input  wire [31:0] in_A,   // rs1
    input  wire [31:0] in_B,   // rs2
    input  wire [31:0] in_C,   // rs3

    output wire        out_stall,
    output reg  [31:0] out_res
);

    // ============================================================
    // FPU CONTROL ENCODING
    // Phải khớp với FPU_Decoder.v và FPU.v
    // ============================================================
    localparam [4:0]
        FMADD_S  = 5'b10100,
        FMSUB_S  = 5'b10101,
        FNMSUB_S = 5'b10110,
        FNMADD_S = 5'b10111;

    // ============================================================
    // FSM STATE
    // ============================================================
    localparam [1:0]
        S_IDLE     = 2'd0,
        S_WAIT_MUL = 2'd1,
        S_WAIT_ADD = 2'd2;

    reg [1:0] state;
    reg [3:0] cnt;

    reg [4:0]  op_r;
    reg [31:0] A_r;
    reg [31:0] B_r;
    reg [31:0] C_r;

    reg [31:0] add_A_r;
    reg [31:0] add_B_r;

    assign out_stall = (state != S_IDLE);

    // ============================================================
    // FP_Mul
    // ============================================================
    wire [31:0] mul_out;

    FP_Mul u_fma_mul (
        .clk     (clk),
        .rst_n   (rst_n),
        .A       (A_r),
        .B       (B_r),
        .Mul_Out (mul_out)
    );

    // ============================================================
    // FP_Add
    // ============================================================
    wire [31:0] add_out;

    FP_Add u_fma_add (
        .clk   (clk),
        .rst_n (rst_n),
        .A     (add_A_r),
        .B     (add_B_r),
        .Out   (add_out)
    );

    // ============================================================
    // Helper: đảo dấu float
    // ============================================================
    function [31:0] neg_float;
        input [31:0] x;
        begin
            neg_float = {~x[31], x[30:0]};
        end
    endfunction

    // ============================================================
    // MAIN FSM
    //
    // Latency xấp xỉ:
    // - chờ FP_Mul khoảng 5 cycle
    // - đưa kết quả mul vào FP_Add
    // - chờ FP_Add khoảng 5 cycle
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            cnt     <= 4'd0;

            op_r    <= 5'd0;
            A_r     <= 32'd0;
            B_r     <= 32'd0;
            C_r     <= 32'd0;

            add_A_r <= 32'd0;
            add_B_r <= 32'd0;

            out_res <= 32'd0;
        end
        else begin
            case (state)

                // ------------------------------------------------
                // IDLE
                // ------------------------------------------------
                S_IDLE: begin
                    cnt <= 4'd0;

                    if (in_start) begin
                        op_r <= in_opcode;
                        A_r  <= in_A;
                        B_r  <= in_B;
                        C_r  <= in_C;

                        state <= S_WAIT_MUL;
                        cnt   <= 4'd0;
                    end
                end

                // ------------------------------------------------
                // WAIT MUL RESULT
                // FP_Mul của bạn đang dùng pipeline khoảng 5 stage.
                // Chờ dư 1 chút để ổn định với register input.
                // ------------------------------------------------
                S_WAIT_MUL: begin
                    cnt <= cnt + 4'd1;

                    if (cnt == 4'd5) begin
                        // Chuẩn bị input cho FP_Add theo loại FMA
                        case (op_r)

                            // FMADD.S = (A * B) + C
                            FMADD_S: begin
                                add_A_r <= mul_out;
                                add_B_r <= C_r;
                            end

                            // FMSUB.S = (A * B) - C
                            FMSUB_S: begin
                                add_A_r <= mul_out;
                                add_B_r <= neg_float(C_r);
                            end

                            // FNMSUB.S = -(A * B) + C
                            FNMSUB_S: begin
                                add_A_r <= neg_float(mul_out);
                                add_B_r <= C_r;
                            end

                            // FNMADD.S = -(A * B) - C
                            FNMADD_S: begin
                                add_A_r <= neg_float(mul_out);
                                add_B_r <= neg_float(C_r);
                            end

                            default: begin
                                add_A_r <= 32'd0;
                                add_B_r <= 32'd0;
                            end

                        endcase

                        state <= S_WAIT_ADD;
                        cnt   <= 4'd0;
                    end
                end

                // ------------------------------------------------
                // WAIT ADD RESULT
                // ------------------------------------------------
                S_WAIT_ADD: begin
                    cnt <= cnt + 4'd1;

                    if (cnt == 4'd5) begin
                        out_res <= add_out;
                        state   <= S_IDLE;
                        cnt     <= 4'd0;
                    end
                end

                default: begin
                    state <= S_IDLE;
                    cnt   <= 4'd0;
                end

            endcase
        end
    end

endmodule