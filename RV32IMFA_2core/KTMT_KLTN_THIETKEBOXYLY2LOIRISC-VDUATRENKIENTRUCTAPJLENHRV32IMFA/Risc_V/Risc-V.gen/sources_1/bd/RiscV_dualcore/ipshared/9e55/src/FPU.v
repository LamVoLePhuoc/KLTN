module FPU (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_start,      // Kích hoạt FPU
    input  wire [4:0]  in_opcode,     // Mã lệnh (Opcode)
    input  wire [31:0] in_rs1,        // Toán hạng A
    input  wire [31:0] in_rs2,        // Toán hạng B
    output reg  [31:0] out_data,      // Kết quả
    output reg         out_valid,     // Báo hiệu kết quả đã xong (1 tick)
    output wire        out_stall      // Báo hiệu FPU đang bận (cho lệnh DIV)
);

    // --- 1. ĐỊNH NGHĨA OPCODE (RISC-V Standard) ---
    localparam FADD_S    = 5'b00000;
    localparam FSUB_S    = 5'b00001;
    localparam FMUL_S    = 5'b00010;
    localparam FDIV_S    = 5'b00011;
    localparam FSQRT_S   = 5'b00100; 
    localparam FSGNJ_S   = 5'b00101;
    localparam FSGNJN_S  = 5'b00110;
    localparam FSGNJX_S  = 5'b00111;
    localparam FEQ_S     = 5'b01000;
    localparam FLT_S     = 5'b01001;
    localparam FLE_S     = 5'b01010;
    localparam FCVT_W_S  = 5'b01100; // Float -> Int
    localparam FCVT_WU_S = 5'b01101; // Float -> UInt
    localparam FCVT_S_W  = 5'b01110; // Int -> Float
    localparam FCVT_S_WU = 5'b01111; // UInt -> Float
    localparam FMV_X_W   = 5'b10000; // Move Float to Int Reg
    localparam FMV_W_X   = 5'b10001; // Move Int to Float Reg
    localparam FMIN_S    = 5'b10100;
    localparam FMAX_S    = 5'b10101;

    // --- 2. XỬ LÝ ĐẦU VÀO CHO ADD/SUB ---

    reg [31:0] operand_b_adder;
    always @(*) begin
        if (in_opcode == FSUB_S) 
            operand_b_adder = {~in_rs2[31], in_rs2[30:0]};
        else 
            operand_b_adder = in_rs2;
    end

    // --- 3. INSTANTIATE CÁC MODULE TÍNH TOÁN ---

    // -- 3.1 Bộ Cộng/Trừ (5 Stages) --
    wire [31:0] w_add_out;
    FP_Add u_adder (
        .clk(clk),
        .rst_n(rst_n),      
        .A(in_rs1),
        .B(operand_b_adder),
        .Out(w_add_out)
    );

    // -- 3.2 Bộ Nhân (5 Stages) --
    wire [31:0] w_mul_out;
    FP_Mul u_multiplier (
        .clk(clk),
        .rst_n(rst_n),
        .A(in_rs1),
        .B(in_rs2),
        .Mul_Out(w_mul_out)
    );

    // -- 3.3 Bộ Chia (Multi-cycle) --
    wire [31:0] w_div_out;
    wire        w_div_stall;
    wire        w_div_start = in_start && (in_opcode == FDIV_S);
    
    FP_Div u_divider (
        .clk(clk),
        .rst_n(rst_n),
        .in_start(w_div_start),
        .in_A(in_rs1),
        .in_B(in_rs2),
        .out_stall(w_div_stall),
        .out_res(w_div_out)
    );

	     // --- 6. LOGIC TỔ HỢP PHỤ TRỢ (HELPER LOGIC) ---
    
    // 6.1 Logic so sánh (Compare)
    reg w_cmp_res;
    wire cmp_eq = (in_rs1 == in_rs2);
    wire cmp_lt = (in_rs1[31] != in_rs2[31]) ? in_rs1[31] : (in_rs1[31] ? (in_rs1 > in_rs2) : (in_rs1 < in_rs2));
    // Lưu ý: Logic so sánh float trên chưa xử lý NaN và -0/+0 triệt để, nhưng đủ cho cơ bản.
    
    always @(*) begin
        case (in_opcode)
            FEQ_S: w_cmp_res = cmp_eq;
            FLT_S: w_cmp_res = cmp_lt;
            FLE_S: w_cmp_res = cmp_lt || cmp_eq;
            default: w_cmp_res = 0;
        endcase
    end

    // 6.2 Logic Min/Max
    reg [31:0] w_minmax_res;
    always @(*) begin
        if (in_opcode == FMIN_S)
            w_minmax_res = cmp_lt ? in_rs1 : in_rs2; // Nếu rs1 < rs2 thì lấy rs1
        else // FMAX
            w_minmax_res = cmp_lt ? in_rs2 : in_rs1; // Nếu rs1 < rs2 thì lấy rs2
    end
    
    assign out_stall = w_div_stall;
    // --- 4. PIPELINE MANAGEMENT (QUẢN LÝ ĐỘ TRỄ) ---
    
    // Shift Register để theo dõi lệnh đang đi trong ống 5 chu kỳ
    reg [4:0] pipe_valid;       // 1 = Có lệnh hợp lệ
    reg [4:0] pipe_is_adder;    // 1 = Lệnh đó là ADD/SUB, 0 = MUL
    
    // Register cho Fast Path (1 chu kỳ)
    reg [31:0] r_fast_res;
    reg        r_fast_valid;

    // Detect Div Done (Khi stall chuyển từ 1 xuống 0)
reg prev_div_stall;
    wire w_div_done = (prev_div_stall == 1'b1) && (w_div_stall == 1'b0);

    // --- 5. LOGIC CHÍNH (SEQUENTIAL) ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data       <= 0;
            out_valid      <= 0;
            pipe_valid     <= 0;
            pipe_is_adder  <= 0;
            r_fast_valid   <= 0;
            r_fast_res     <= 0;
            prev_div_stall <= 0;
        end else begin
            // 5.1 Cập nhật trạng thái bộ chia
            prev_div_stall <= w_div_stall;

            // 5.2 Quản lý Pipeline 5-Stage (Add/Sub/Mul)
            // Chỉ đẩy vào pipeline nếu là lệnh Add/Sub/Mul và có tín hiệu start
            if (in_start && (in_opcode == FADD_S || in_opcode == FSUB_S || in_opcode == FMUL_S)) begin
                pipe_valid    <= {pipe_valid[3:0], 1'b1};
                pipe_is_adder <= {pipe_is_adder[3:0], (in_opcode != FMUL_S)}; 
            end else begin
                pipe_valid    <= {pipe_valid[3:0], 1'b0}; // Shift 0 vào (Bubble)
                pipe_is_adder <= {pipe_is_adder[3:0], 1'b0};
            end

            // 5.3 Xử lý các lệnh "Fast Path" (1 Cycle Latency)
            r_fast_valid <= 0; // Mặc định reset
            
            if (in_start && !w_div_stall) begin
                case (in_opcode)
                    // --- Nhóm Sign Injection ---
                    FSGNJ_S:  begin r_fast_res <= {in_rs2[31], in_rs1[30:0]}; r_fast_valid <= 1; end
                    FSGNJN_S: begin r_fast_res <= {~in_rs2[31], in_rs1[30:0]}; r_fast_valid <= 1; end
                    FSGNJX_S: begin r_fast_res <= {in_rs1[31] ^ in_rs2[31], in_rs1[30:0]}; r_fast_valid <= 1; end

                    // --- Nhóm Move ---
                    FMV_X_W:  begin r_fast_res <= in_rs1; r_fast_valid <= 1; end // Move Float -> Int Reg
                    FMV_W_X:  begin r_fast_res <= in_rs1; r_fast_valid <= 1; end // Move Int Reg -> Float

                    // --- Nhóm Compare & Min/Max (Logic ở dưới) ---
                    FEQ_S, FLT_S, FLE_S: begin 
                        r_fast_res <= {31'b0, w_cmp_res}; 
                        r_fast_valid <= 1; 
                    end
                    FMIN_S, FMAX_S: begin
                        r_fast_res <= w_minmax_res;
                        r_fast_valid <= 1;
                    end
                    
                    // --- Nhóm Convert (Làm đơn giản hoặc placeholder) ---
                    FCVT_W_S: begin /* Placeholder logic */ r_fast_res <= 0; r_fast_valid <= 1; end 
                    
                    default: ; 
                endcase
            end

            // 5.4 MUX OUTPUT (Chọn kết quả đầu ra)
            out_valid <= 0; // Mặc định

            // Ưu tiên 1: Bộ Chia vừa làm xong
            if (w_div_done) begin
                out_data  <= w_div_out;
                out_valid <= 1;
end
            // Ưu tiên 2: Pipeline 5 chu kỳ (Add/Mul) trả kết quả
            else if (pipe_valid[4]) begin
                if (pipe_is_adder[4]) 
                    out_data <= w_add_out; // Kết quả từ Add
                else 
                    out_data <= w_mul_out; // Kết quả từ Mul
                out_valid <= 1;
            end
            // Ưu tiên 3: Fast Path trả kết quả
            else if (r_fast_valid) begin
                out_data  <= r_fast_res;
                out_valid <= 1;
            end
        end
    end



endmodule