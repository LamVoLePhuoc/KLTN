module ALU (
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [4:0]  ALUControl, // Mã điều khiển 5-bit

    output wire        Carry,      // Carry-out cho các phép toán không dấu
    output wire        OverFlow,   // Tràn số cho các phép toán có dấu
    output wire        Zero,       // Bằng 0
    output wire        Negative,   // Số âm
    output wire [31:0] Result      // Kết quả cuối cùng
);

    // ============================================================
    // 1. ĐỊNH NGHĨA MÃ ĐIỀU KHIỂN (ALU CONTROL ENCODING)
    // ============================================================
    // RV32I
    localparam ALU_ADD    = 5'b00000, ALU_SUB    = 5'b00001;
    localparam ALU_SLL    = 5'b00010, ALU_SLT    = 5'b00011, ALU_SLTU   = 5'b00100;
    localparam ALU_XOR    = 5'b00101, ALU_SRL    = 5'b00110, ALU_SRA    = 5'b00111;
    localparam ALU_OR     = 5'b01000, ALU_AND    = 5'b01001;

    // RV32M (Nhân/Chia)
    localparam ALU_MUL    = 5'b10000, ALU_MULH   = 5'b10001;
    localparam ALU_MULHSU = 5'b10010, ALU_MULHU  = 5'b10011;
    localparam ALU_DIV    = 5'b10100, ALU_DIVU   = 5'b10101;
    localparam ALU_REM    = 5'b10110, ALU_REMU   = 5'b10111;

    // RV32A (Atomic - ALU Operations)
    localparam ALU_MAX    = 5'b11000, ALU_MIN    = 5'b11001;
    localparam ALU_MAXU   = 5'b11010, ALU_MINU   = 5'b11011;

    // ============================================================
    // 2. CÁC BIẾN TRUNG GIAN
    // ============================================================
    wire [32:0] add_w = {1'b0, A} + {1'b0, B};
    wire [32:0] sub_w = {1'b0, A} + {1'b0, (~B)} + 33'd1;
    
    // Multiplication (64-bit)
    wire signed [63:0] prod_ss = $signed(A) * $signed(B);
    wire signed [63:0] prod_su = $signed(A) * $unsigned(B);
    wire        [63:0] prod_uu = A * B;

    // Division constants
    localparam [31:0] MIN_INT = 32'h80000000;

    reg [31:0] res_internal;
    reg        carry_internal;
    reg        ovf_internal;

    // ============================================================
    // 3. LOGIC XỬ LÝ CHÍNH
    // ============================================================
    always @(*) begin
        // Mặc định
        res_internal   = 32'd0;
        carry_internal = 1'b0;
        ovf_internal   = 1'b1; // Sẽ tính toán trong từng case cụ thể

        case (ALUControl)
            // RV32I
            ALU_ADD: begin 
                res_internal = add_w[31:0]; 
                carry_internal = add_w[32];
                ovf_internal = (A[31] == B[31]) && (res_internal[31] != A[31]);
            end
            ALU_SUB: begin 
                res_internal = sub_w[31:0]; 
                carry_internal = sub_w[32];
                ovf_internal = (A[31] != B[31]) && (res_internal[31] != A[31]);
            end
            ALU_SLL:  res_internal = A << B[4:0];
            ALU_SRL:  res_internal = A >> B[4:0];
            ALU_SRA:  res_internal = $signed(A) >>> B[4:0];
            ALU_AND:  res_internal = A & B;
            ALU_OR:   res_internal = A | B;
            ALU_XOR:  res_internal = A ^ B;
            ALU_SLT:  res_internal = {31'b0, ($signed(A) < $signed(B))};
            ALU_SLTU: res_internal = {31'b0, (A < B)};

            // RV32M
            ALU_MUL:    res_internal = prod_ss[31:0];
            ALU_MULH:   res_internal = prod_ss[63:32];
            ALU_MULHSU: res_internal = prod_su[63:32];
            ALU_MULHU:  res_internal = prod_uu[63:32];
            
            ALU_DIV: begin
                if (B == 32'd0) res_internal = 32'hffffffff;
                else if ((A == MIN_INT) && (B == 32'hffffffff)) res_internal = MIN_INT;
                else res_internal = $signed(A) / $signed(B);
            end
            ALU_DIVU: begin
                if (B == 32'd0) res_internal = 32'hffffffff;
                else res_internal = A / B;
            end
            ALU_REM: begin
                if (B == 32'd0) res_internal = A;
                else if ((A == MIN_INT) && (B == 32'hffffffff)) res_internal = 32'd0;
                else res_internal = $signed(A) % $signed(B);
            end
            ALU_REMU: begin
                if (B == 32'd0) res_internal = A;
                else res_internal = A % B;
            end

            // RV32A (Atomic Support)
            ALU_MAX:  res_internal = ($signed(A) > $signed(B)) ? A : B;
            ALU_MIN:  res_internal = ($signed(A) < $signed(B)) ? A : B;
            ALU_MAXU: res_internal = (A > B) ? A : B;
            ALU_MINU: res_internal = (A < B) ? A : B;

            default: res_internal = 32'd0;
        endcase
    end

    // ============================================================
    // 4. ĐẦU RA (OUTPUT ASSIGNMENTS)
    // ============================================================
    assign Result   = res_internal;
    assign Zero     = (res_internal == 32'd0);
    assign Negative = res_internal[31];
    assign Carry    = carry_internal;
    assign OverFlow = ovf_internal;

endmodule