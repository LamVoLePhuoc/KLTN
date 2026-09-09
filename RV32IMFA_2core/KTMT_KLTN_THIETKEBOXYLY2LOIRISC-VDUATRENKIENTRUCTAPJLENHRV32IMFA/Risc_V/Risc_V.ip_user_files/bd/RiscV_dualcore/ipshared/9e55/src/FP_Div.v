module FP_Div (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_start,
    input  wire [31:0] in_A,
    input  wire [31:0] in_B,
    output reg         out_stall,
    output reg  [31:0] out_res
);

    // Các trạng thái của FSM
    localparam IDLE      = 4'd0,
               INIT_F0   = 4'd1, // Ước lượng ban đầu F0
               MULT_0    = 4'd2, // A0 = A*F0, B0 = B*F0
               SUB_F1    = 4'd3, // F1 = 2 - B0
               MULT_1    = 4'd4, // A1 = A0*F1, B1 = B0*F1
               SUB_F2    = 4'd5, // F2 = 2 - B1
               MULT_2    = 4'd6, // A2 = A1*F2 (Kết quả cuối)
               DONE      = 4'd7;

    reg [3:0] state;
    reg [2:0] pipe_cnt; // Bộ đếm đợi 5 chu kỳ của Pipeline

    // Các biến lưu trữ trung gian
    reg [31:0] reg_A, reg_B, reg_F;
    wire [31:0] mul_out1, mul_out2, add_out;
    reg  [31:0] op_mul1_A, op_mul1_B, op_mul2_A, op_mul2_B, op_add_A, op_add_B;

    // --- INSTANTIATE CÁC MODULE 5-STAGE ---
    // Sử dụng 2 bộ nhân để chạy song song tử số và mẫu số
    FP_Mul mul_inst1 ( .clk(clk), .rst_n(rst_n), .A(op_mul1_A), .B(op_mul1_B), .Mul_Out(mul_out1) );
    FP_Mul mul_inst2 ( .clk(clk), .rst_n(rst_n), .A(op_mul2_A), .B(op_mul2_B), .Mul_Out(mul_out2) );
    
    // Sử dụng module Add để thực hiện phép trừ (A + (-B))
    FP_Add add_inst ( .clk(clk), .rst_n(rst_n), .A(op_add_A), .B(op_add_B), .Out(add_out) );

    // --- FSM LOGIC ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            out_stall <= 0;
            pipe_cnt <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (in_start) begin
                        out_stall <= 1;
                        state <= INIT_F0;
                    end
                end

                // ... (bên trong case state) ...

					INIT_F0: begin
						 // --- BỔ SUNG: CHECK DIVIDE BY ZERO ---
						 // Nếu mũ của B = 0 (tức là B = 0.0 hoặc subnormal cực nhỏ)
						 if (in_B[30:23] == 8'd0) begin
							  // Kết quả là Infinity với dấu = dấu A XOR dấu B
							  out_res <= {in_A[31] ^ in_B[31], 8'hFF, 23'd0}; 
							  state   <= DONE; // Nhảy thẳng đến DONE, bỏ qua tính toán
						 end 
						 else begin
							  // --- LOGIC CŨ GIỮ NGUYÊN ---zzzz
							  reg_A <= in_A;
							  reg_B <= in_B;
							  // Ước lượng F0 ≈ 1/B
							  reg_F <= {1'b0, (8'd253 - in_B[30:23]), in_B[22:0]};
							  state <= MULT_0;
							  pipe_cnt <= 0;
						 end
					end

// ... (các state khác giữ nguyên) ...

                MULT_0: begin
                    // Tính song song: A0 = A * F0 và B0 = B * F0
                    op_mul1_A <= reg_A; op_mul1_B <= reg_F;
                    op_mul2_A <= reg_B; op_mul2_B <= reg_F;
                    
                    if (pipe_cnt == 3'd5) begin
                        reg_A <= mul_out1; // Đây là A0
                        reg_B <= mul_out2; // Đây là B0
state <= SUB_F1;
                        pipe_cnt <= 0;
                    end else pipe_cnt <= pipe_cnt + 1;
                end

                SUB_F1: begin
                    // F1 = 2.0 - B0 
                    // Nhắc nhở: 32'h40000000 là số 2.0f
                    op_add_A <= 32'h40000000;
                    op_add_B <= {~reg_B[31], reg_B[30:0]}; // Đảo dấu của B0 để thành phép trừ
                    
                    if (pipe_cnt == 3'd5) begin
                        reg_F <= add_out; // Đây là F1
                        state <= MULT_1;
                        pipe_cnt <= 0;
                    end else pipe_cnt <= pipe_cnt + 1;
                end

                MULT_1: begin
                    // Tính song song: A1 = A0 * F1 và B1 = B0 * F1
                    op_mul1_A <= reg_A; op_mul1_B <= reg_F;
                    op_mul2_A <= reg_B; op_mul2_B <= reg_F;
                    
                    if (pipe_cnt == 3'd5) begin
                        reg_A <= mul_out1; // A1
                        reg_B <= mul_out2; // B1
                        state <= SUB_F2;
                        pipe_cnt <= 0;
                    end else pipe_cnt <= pipe_cnt + 1;
                end

                SUB_F2: begin
                    // F2 = 2.0 - B1
                    op_add_A <= 32'h40000000;
                    op_add_B <= {~reg_B[31], reg_B[30:0]};
                    
                    if (pipe_cnt == 3'd5) begin
                        reg_F <= add_out; // F2
                        state <= MULT_2;
                        pipe_cnt <= 0;
                    end else pipe_cnt <= pipe_cnt + 1;
                end

                MULT_2: begin
                    // Kết quả cuối cùng: Res = A1 * F2
                    op_mul1_A <= reg_A; op_mul1_B <= reg_F;
                    
                    if (pipe_cnt == 3'd5) begin
                        out_res <= mul_out1;
                        state <= DONE;
                    end else pipe_cnt <= pipe_cnt + 1;
                end

                DONE: begin
                    out_stall <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule