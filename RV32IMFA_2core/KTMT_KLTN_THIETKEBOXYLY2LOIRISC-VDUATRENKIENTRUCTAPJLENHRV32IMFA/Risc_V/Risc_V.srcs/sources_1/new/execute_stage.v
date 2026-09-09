`timescale 1ns / 1ps

module execute_stage(
    input  wire        clk,
    input  wire        rst,

    // ==========================================
    // INTEGER PATH
    // ==========================================
    input  wire [31:0] RD1_E,
    input  wire [31:0] RD2_E,
    input  wire [31:0] PCE,
    input  wire [31:0] PCPlus4E,
    input  wire [31:0] Imm_Ext_E,

    input  wire [4:0]  ALUControlE,
    input  wire        ALUSrcE,
    input  wire [1:0]  ALUSrcA_E,
    input  wire        AtomicE,
    input  wire [1:0]  ResultSrcE,
    input  wire        MemWriteE,

    input  wire        BranchE,
    input  wire        JumpE,
    input  wire [2:0]  BranchTypeE,
    input  wire [6:0]  OpE,

    // Forwarding int
    input  wire [1:0]  ForwardA_E,
    input  wire [1:0]  ForwardB_E,
    input  wire [31:0] ResultW,
    input  wire [31:0] ALUResultM,

    // ==========================================
    // FLOAT PATH
    // ==========================================
    input  wire        FPU_StartE,
    input  wire [4:0]  FPU_Opcode_E,

    input  wire [31:0] RD1_F_E,
    input  wire [31:0] RD2_F_E,
    input  wire [31:0] RD3_F_E,

    input  wire [1:0]  ForwardA_F_E,
    input  wire [1:0]  ForwardB_F_E,
    input  wire [1:0]  ForwardC_F_E,

    input  wire [31:0] FP_ResultW,
    input  wire [31:0] FP_ResultM,

    output wire        Stall_FPU_Req,
    output wire        Stall_MDU_Req,

    // ==========================================
    // OUTPUTS
    // ==========================================
    output wire [31:0] ALUResultE,
    output wire [31:0] WriteDataE,
    output wire [31:0] PCTargetE,
    output wire        PCSrcE,

    output wire        ZeroE,
    output wire        NegativeE,
    output wire        CarryE,
    output wire        OverFlowE
);

    localparam [6:0] OP_JALR = 7'b1100111;
    localparam [6:0] OP_FSW  = 7'b0100111;

    // ==========================================
    // ALU CONTROL ENCODING FOR MDU DETECT
    // ==========================================
    localparam ALU_MUL    = 5'b10000;
    localparam ALU_MULH   = 5'b10001;
    localparam ALU_MULHSU = 5'b10010;
    localparam ALU_MULHU  = 5'b10011;
    localparam ALU_DIV    = 5'b10100;
    localparam ALU_DIVU   = 5'b10101;
    localparam ALU_REM    = 5'b10110;
    localparam ALU_REMU   = 5'b10111;

    // ==========================================
    // FPU CONTROL ENCODING FOR SOURCE SELECT
    // ==========================================
    localparam FCVT_S_W  = 5'b01111;
    localparam FCVT_S_WU = 5'b10000;
    localparam FMV_W_X   = 5'b10010;

    // ==========================================
    // INTERNAL WIRES
    // ==========================================
    wire [31:0] SrcA_Forwarded;
    wire [31:0] SrcB_Forwarded;
    wire [31:0] ALU_In_A;
    wire [31:0] ALU_In_B;
    wire [31:0] Int_ALUResultE;

    wire [31:0] SrcA_F_Forwarded;
    wire [31:0] SrcB_F_Forwarded;
    wire [31:0] SrcC_F_Forwarded;
    wire [31:0] FPU_ResultE;
    wire        FPU_ValidE;

    wire        is_FSW_E;
    wire        fpu_rs1_from_int;
    wire [31:0] FPU_RS1_Input;

    wire        IsFPUResultE;
    reg         fpu_issued;
    wire        fpu_start_pulse;

    wire        IsMResultE;
    wire [31:0] MDU_ResultE;
    wire        MDU_BusyE;
    wire        MDU_DoneE;
    reg         mdu_issued;
    wire        mdu_start_pulse;

    wire        signed_lt;
    wire        unsigned_lt;
    reg         TakeBranchE;

    wire [31:0] PCBranchTarget;
    wire [31:0] JalrSum;

    // ==========================================
    // FPU / MDU DETECT
    // ==========================================
    assign IsFPUResultE = (ResultSrcE == 2'b11);

    assign IsMResultE =
        (ALUControlE == ALU_MUL)    ||
        (ALUControlE == ALU_MULH)   ||
        (ALUControlE == ALU_MULHSU) ||
        (ALUControlE == ALU_MULHU)  ||
        (ALUControlE == ALU_DIV)    ||
        (ALUControlE == ALU_DIVU)   ||
        (ALUControlE == ALU_REM)    ||
        (ALUControlE == ALU_REMU);

    assign fpu_start_pulse = IsFPUResultE && FPU_StartE && !fpu_issued;

    // Stall toàn pipeline cho tới khi FPU xong
    assign Stall_FPU_Req = IsFPUResultE && FPU_StartE && !FPU_ValidE;

    // Start MDU đúng 1 lần khi lệnh M đứng ở EX
    assign mdu_start_pulse = IsMResultE && !mdu_issued && !MDU_BusyE && !MDU_DoneE;

    // Stall toàn pipeline cho tới khi MDU xong
    assign Stall_MDU_Req = IsMResultE && !MDU_DoneE;

    // ==========================================
    // INTEGER FORWARDING
    // ==========================================
    Mux_3_by_1 forward_a_mux (
        .a(RD1_E),
        .b(ResultW),
        .c(ALUResultM),
        .s(ForwardA_E),
        .d(SrcA_Forwarded)
    );

    Mux_3_by_1 forward_b_mux (
        .a(RD2_E),
        .b(ResultW),
        .c(ALUResultM),
        .s(ForwardB_E),
        .d(SrcB_Forwarded)
    );

    // ==========================================
    // FLOAT FORWARDING
    // ==========================================
    Mux_3_by_1 forward_fa_mux (
        .a(RD1_F_E),
        .b(FP_ResultW),
        .c(FP_ResultM),
        .s(ForwardA_F_E),
        .d(SrcA_F_Forwarded)
    );

    Mux_3_by_1 forward_fb_mux (
        .a(RD2_F_E),
        .b(FP_ResultW),
        .c(FP_ResultM),
        .s(ForwardB_F_E),
        .d(SrcB_F_Forwarded)
    );

    Mux_3_by_1 forward_fc_mux (
        .a(RD3_F_E),
        .b(FP_ResultW),
        .c(FP_ResultM),
        .s(ForwardC_F_E),
        .d(SrcC_F_Forwarded)
    );

    // ==========================================
    // STORE DATA SELECT
    //
    // SW/SB/SH dùng integer rs2.
    // FSW dùng floating fs2.
    // ==========================================
    assign is_FSW_E   = (OpE == OP_FSW);
    assign WriteDataE = is_FSW_E ? SrcB_F_Forwarded : SrcB_Forwarded;

    // ==========================================
    // INTEGER ALU INPUT SELECT
    // ==========================================
    Mux_3_by_1 alu_src_a_mux (
        .a(SrcA_Forwarded),
        .b(PCE),
        .c(32'd0),
        .s(ALUSrcA_E),
        .d(ALU_In_A)
    );

    mux alu_src_b_mux (
        .a(SrcB_Forwarded),
        .b(Imm_Ext_E),
        .s(ALUSrcE),
        .c(ALU_In_B)
    );

    // ==========================================
    // INTEGER ALU
    // ALU bây giờ chỉ xử lý RV32I/RV32A nhẹ.
    // Lệnh M sẽ lấy kết quả từ MDU.
    // ==========================================
    ALU alu_unit (
        .A(ALU_In_A),
        .B(ALU_In_B),
        .ALUControl(ALUControlE),
        .Carry(CarryE),
        .OverFlow(OverFlowE),
        .Zero(ZeroE),
        .Negative(NegativeE),
        .Result(Int_ALUResultE)
    );

    // ==========================================
    // MDU ISSUE CONTROL
    // Chống start lại nhiều lần khi pipeline đang stall chờ MDU.
    // ==========================================
    always @(posedge clk) begin
        if (rst) begin
            mdu_issued <= 1'b0;
        end
        else if (!IsMResultE) begin
            mdu_issued <= 1'b0;
        end
        else if (MDU_DoneE) begin
            mdu_issued <= 1'b0;
        end
        else if (mdu_start_pulse) begin
            mdu_issued <= 1'b1;
        end
    end

    // ==========================================
    // MDU
    // Xử lý MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU
    // ==========================================
    MDU mdu_unit (
        .clk    (clk),
        .rst    (rst),
        .start  (mdu_start_pulse),
        .op     (ALUControlE),
        .A      (ALU_In_A),
        .B      (ALU_In_B),
        .busy   (MDU_BusyE),
        .done   (MDU_DoneE),
        .result (MDU_ResultE)
    );

    // ==========================================
    // FPU ISSUE CONTROL
    // Chống re-trigger khi pipeline đang stall chờ FPU.
    // ==========================================
    always @(posedge clk) begin
        if (rst) begin
            fpu_issued <= 1'b0;
        end
        else if (!IsFPUResultE || !FPU_StartE) begin
            fpu_issued <= 1'b0;
        end
        else if (FPU_ValidE) begin
            fpu_issued <= 1'b0;
        end
        else if (fpu_start_pulse) begin
            fpu_issued <= 1'b1;
        end
    end

    // ==========================================
    // FPU SOURCE SELECT
    //
    // Những lệnh này lấy rs1 từ integer RF:
    // - FCVT.S.W
    // - FCVT.S.WU
    // - FMV.W.X
    //
    // Các lệnh F khác lấy rs1 từ FP RF.
    // ==========================================
    assign fpu_rs1_from_int =
        (FPU_Opcode_E == FCVT_S_W)  ||
        (FPU_Opcode_E == FCVT_S_WU) ||
        (FPU_Opcode_E == FMV_W_X);

    assign FPU_RS1_Input = fpu_rs1_from_int ? SrcA_Forwarded : SrcA_F_Forwarded;

    // ==========================================
    // FPU
    // ==========================================
    FPU u_fpu (
        .clk       (clk),
        .rst_n     (~rst),
        .in_start  (fpu_start_pulse),
        .in_opcode (FPU_Opcode_E),
        .in_rs1    (FPU_RS1_Input),
        .in_rs2    (SrcB_F_Forwarded),
        .in_rs3    (SrcC_F_Forwarded),
        .out_data  (FPU_ResultE),
        .out_valid (FPU_ValidE),
        .out_stall ()
    );

    // ==========================================
    // RESULT SELECT
    // Ưu tiên:
    // FPU result nếu là lệnh FPU
    // MDU result nếu là lệnh M
    // ALU result nếu là lệnh integer thường
    // ==========================================
    assign ALUResultE = IsFPUResultE ? FPU_ResultE  :
                        IsMResultE   ? MDU_ResultE  :
                                       Int_ALUResultE;

    // ==========================================
    // BRANCH/JUMP LOGIC
    // ==========================================
    assign signed_lt   = NegativeE ^ OverFlowE;
    assign unsigned_lt = ~CarryE;

    always @(*) begin
        case (BranchTypeE)
            3'b000: TakeBranchE =  ZeroE;        // BEQ
            3'b001: TakeBranchE = ~ZeroE;        // BNE
            3'b100: TakeBranchE =  signed_lt;    // BLT
            3'b101: TakeBranchE = ~signed_lt;    // BGE
            3'b110: TakeBranchE =  unsigned_lt;  // BLTU
            3'b111: TakeBranchE = ~unsigned_lt;  // BGEU
            default: TakeBranchE = 1'b0;
        endcase
    end

    assign PCBranchTarget = PCE + Imm_Ext_E;
    assign JalrSum        = SrcA_Forwarded + Imm_Ext_E;

    assign PCTargetE = (JumpE && (OpE == OP_JALR))
                     ? {JalrSum[31:1], 1'b0}
                     : PCBranchTarget;

    assign PCSrcE = JumpE | (BranchE & TakeBranchE);

endmodule


module MDU(
    input  wire        clk,
    input  wire        rst,

    input  wire        start,
    input  wire [4:0]  op,
    input  wire [31:0] A,
    input  wire [31:0] B,

    output reg         busy,
    output reg         done,
    output reg  [31:0] result
);

    // ============================================================
    // ALU CONTROL ENCODING FOR RV32M
    // ============================================================
    localparam ALU_MUL    = 5'b10000;
    localparam ALU_MULH   = 5'b10001;
    localparam ALU_MULHSU = 5'b10010;
    localparam ALU_MULHU  = 5'b10011;
    localparam ALU_DIV    = 5'b10100;
    localparam ALU_DIVU   = 5'b10101;
    localparam ALU_REM    = 5'b10110;
    localparam ALU_REMU   = 5'b10111;

    localparam [31:0] MIN_INT = 32'h80000000;

    // ============================================================
    // INTERNAL REGISTERS
    // ============================================================
    reg [5:0]  cnt;

    reg [31:0] dividend;
    reg [31:0] divisor;
    reg [31:0] quotient;
    reg [32:0] remainder;

    reg sign_q;
    reg sign_r;
    reg is_rem;

    // ============================================================
    // OP DECODE
    // ============================================================
    wire is_mul =
        (op == ALU_MUL)    ||
        (op == ALU_MULH)   ||
        (op == ALU_MULHSU) ||
        (op == ALU_MULHU);

    wire is_divrem =
        (op == ALU_DIV)  ||
        (op == ALU_DIVU) ||
        (op == ALU_REM)  ||
        (op == ALU_REMU);

    // ============================================================
    // MULTIPLICATION
    // MUL/MULH/MULHU/MULHSU xử lý trong MDU.
    // MULHSU dùng ép kiểu rõ ràng để tránh lỗi mixed signed/unsigned.
    // ============================================================
    wire signed [63:0] prod_ss;
    wire        [63:0] prod_uu;
    wire signed [64:0] prod_su;

    assign prod_ss = $signed(A) * $signed(B);
    assign prod_uu = $unsigned(A) * $unsigned(B);
    assign prod_su = $signed({A[31], A}) * $signed({1'b0, B});

    // ============================================================
    // ABS FUNCTION FOR SIGNED DIV/REM
    // ============================================================
    function [31:0] abs32;
        input [31:0] x;
        begin
            abs32 = x[31] ? (~x + 32'd1) : x;
        end
    endfunction

    // ============================================================
    // RESTORING DIVISION STEP
    // Mỗi cycle xử lý 1 bit.
    // ============================================================
    wire [32:0] rem_shift;
    wire [31:0] div_shift;
    wire        can_sub;
    wire [32:0] rem_next;
    wire [31:0] quo_next;

    assign rem_shift = {remainder[31:0], dividend[31]};
    assign div_shift = {dividend[30:0], 1'b0};

    assign can_sub   = (rem_shift >= {1'b0, divisor});
    assign rem_next  = can_sub ? (rem_shift - {1'b0, divisor}) : rem_shift;
    assign quo_next  = {quotient[30:0], can_sub};

    // ============================================================
    // MAIN FSM
    // ============================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy      <= 1'b0;
            done      <= 1'b0;
            result    <= 32'd0;

            cnt       <= 6'd0;
            dividend  <= 32'd0;
            divisor   <= 32'd0;
            quotient  <= 32'd0;
            remainder <= 33'd0;

            sign_q    <= 1'b0;
            sign_r    <= 1'b0;
            is_rem    <= 1'b0;
        end
        else begin
            done <= 1'b0;

            // ====================================================
            // START NEW OPERATION
            // ====================================================
            if (start && !busy) begin

                // ------------------------------
                // MUL group: 1-cycle latency
                // ------------------------------
                if (is_mul) begin
                    busy <= 1'b1;
                    cnt  <= 6'd1;

                    case (op)
                        ALU_MUL: begin
                            result <= prod_ss[31:0];
                        end

                        ALU_MULH: begin
                            result <= prod_ss[63:32];
                        end

                        ALU_MULHSU: begin
                            result <= prod_su[63:32];
                        end

                        ALU_MULHU: begin
                            result <= prod_uu[63:32];
                        end

                        default: begin
                            result <= 32'd0;
                        end
                    endcase
                end

                // ------------------------------
                // DIV/REM group
                // ------------------------------
                else if (is_divrem) begin

                    // Case 1: divide by zero
                    if (B == 32'd0) begin
                        busy <= 1'b1;
                        cnt  <= 6'd1;

                        case (op)
                            ALU_DIV: begin
                                result <= 32'hffffffff;
                            end

                            ALU_DIVU: begin
                                result <= 32'hffffffff;
                            end

                            ALU_REM: begin
                                result <= A;
                            end

                            ALU_REMU: begin
                                result <= A;
                            end

                            default: begin
                                result <= 32'd0;
                            end
                        endcase
                    end

                    // Case 2: signed overflow
                    // 0x80000000 / -1 = 0x80000000
                    // 0x80000000 % -1 = 0
                    else if (
                        ((op == ALU_DIV) || (op == ALU_REM)) &&
                        (A == MIN_INT) &&
                        (B == 32'hffffffff)
                    ) begin
                        busy <= 1'b1;
                        cnt  <= 6'd1;

                        if (op == ALU_DIV)
                            result <= MIN_INT;
                        else
                            result <= 32'd0;
                    end

                    // Case 3: normal division
                    else begin
                        busy <= 1'b1;
                        cnt  <= 6'd33;

                        is_rem <= (op == ALU_REM) || (op == ALU_REMU);

                        sign_q <= ((op == ALU_DIV) || (op == ALU_REM)) &&
                                  (A[31] ^ B[31]);

                        sign_r <= ((op == ALU_DIV) || (op == ALU_REM)) &&
                                  A[31];

                        dividend  <= ((op == ALU_DIV) || (op == ALU_REM)) ? abs32(A) : A;
                        divisor   <= ((op == ALU_DIV) || (op == ALU_REM)) ? abs32(B) : B;
                        quotient  <= 32'd0;
                        remainder <= 33'd0;
                    end
                end

                // Unknown op
                else begin
                    busy   <= 1'b0;
                    done   <= 1'b0;
                    result <= 32'd0;
                    cnt    <= 6'd0;
                end
            end

            // ====================================================
            // OPERATION RUNNING
            // ====================================================
            else if (busy) begin

                // Last cycle: operation done
                if (cnt == 6'd1) begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    cnt  <= 6'd0;
                end

                // Division iteration
                else begin
                    dividend  <= div_shift;
                    remainder <= rem_next;
                    quotient  <= quo_next;
                    cnt       <= cnt - 6'd1;

                    // cnt == 2 means rem_next/quo_next is final result
                    if (cnt == 6'd2) begin
                        if (is_rem) begin
                            result <= sign_r ? (~rem_next[31:0] + 32'd1)
                                             : rem_next[31:0];
                        end
                        else begin
                            result <= sign_q ? (~quo_next + 32'd1)
                                             : quo_next;
                        end
                    end
                end
            end
        end
    end

endmodule