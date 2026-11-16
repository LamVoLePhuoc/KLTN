`timescale 1ns / 1ps

module execute_stage(
    input  wire        clk,
    input  wire        rst,
    input  wire        Stall_Core_External,

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

    // NEW: MemOpE doubles as funct3 for CSR ops too (Control_Unit.v
    // already sets MemOp=funct3 unconditionally, for every
    // instruction, not just loads/stores) -- reused here instead of
    // adding a separate CsrFunct3E field.
    input  wire [2:0]  MemOpE,

    // Forwarding int
    input  wire [1:0]  ForwardA_E,
    input  wire [1:0]  ForwardB_E,
    input  wire [31:0] ResultW,
    input  wire [31:0] ALUResultM,

    output wire        Stall_MDU_Req,

    // ==========================================
    // OUTPUTS
    // ==========================================
    output wire [31:0] ALUResultE,
    output wire [31:0] WriteDataE,
    output wire [31:0] CsrWDataE,    // NEW: see below
    output wire [31:0] PCTargetE,
    output wire        PCSrcE,

    output wire        ZeroE,
    output wire        NegativeE,
    output wire        CarryE,
    output wire        OverFlowE
);

    localparam [6:0] OP_JALR = 7'b1100111;

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
    // INTERNAL WIRES
    // ==========================================
    wire [31:0] SrcA_Forwarded;
    wire [31:0] SrcB_Forwarded;
    wire [31:0] ALU_In_A;
    wire [31:0] ALU_In_B;
    wire [31:0] Int_ALUResultE;

    wire        IsMResultE;
    wire [31:0] MDU_ResultE;
    wire        MDU_BusyE;
    wire        MDU_DoneE;
    reg         mdu_issued;
    wire        mdu_start_pulse;

    // Branch conditions use a dedicated comparator on the already-forwarded
    // register operands.  Deriving them from ALU flags made a taken-branch
    // decision traverse the general ALU/subtractor before reaching FlushE,
    // which was the post-route critical path of every core.
    wire        branch_equal;
    wire        branch_signed_lt;
    wire        branch_unsigned_lt;
    reg         TakeBranchE;

    wire [31:0] PCBranchTarget;
    wire [31:0] JalrSum;

    // ==========================================
    // MDU DETECT
    // ==========================================
    assign IsMResultE =
        (ALUControlE == ALU_MUL)    ||
        (ALUControlE == ALU_MULH)   ||
        (ALUControlE == ALU_MULHSU) ||
        (ALUControlE == ALU_MULHU)  ||
        (ALUControlE == ALU_DIV)    ||
        (ALUControlE == ALU_DIVU)   ||
        (ALUControlE == ALU_REM)    ||
        (ALUControlE == ALU_REMU);

    // Start MDU đúng 1 lần khi lệnh M đứng ở EX
    assign mdu_start_pulse = IsMResultE && !mdu_issued && !MDU_BusyE;

    // Once issued, busy=0 denotes a completed result.  Keep that result valid
    // if an unrelated cache stall still holds this instruction in E, rather
    // than reissuing the same operation after MDU_DoneE's one-cycle pulse.
    assign Stall_MDU_Req = IsMResultE && (!mdu_issued || MDU_BusyE);

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
    // STORE DATA SELECT
    //
    // SW/SB/SH dùng integer rs2.
    // ==========================================
    assign WriteDataE = SrcB_Forwarded;

    // ==========================================
    // CSR WRITE-SOURCE SELECT (NEW)
    //
    // CSRRW/RS/RC read rs1 (needs the SAME forwarding as any other
    // register operand -- reuses SrcA_Forwarded, already computed
    // above for the ALU, rather than re-deriving forwarding logic
    // here). CSRRWI/RSI/RCI instead use a literal 5-bit unsigned
    // immediate carried in the rs1 field position -- already
    // available as Imm_Ext_E via Sign_Extend.v's ImmSrc=110 case
    // (Main_Decoder.v sets that ImmSrc for every CSR op). funct3[2]
    // is exactly the immediate-vs-register bit for CSRxx (000=RW,
    // 010=RS, 011=RC vs 101=RWI, 110=RSI, 111=RCI) -- MemOpE doubles
    // as funct3 here, see the port comment above.
    // ==========================================
    assign CsrWDataE = MemOpE[2] ? Imm_Ext_E : SrcA_Forwarded;

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
        else if (mdu_issued && !MDU_BusyE && !Stall_Core_External) begin
            // The completed instruction advances out of E on this edge.
            // Clearing now also permits a back-to-back M instruction to issue.
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
    // RESULT SELECT
    // Ưu tiên:
    // MDU result nếu là lệnh M
    // ALU result nếu là lệnh integer thường
    // ==========================================
    assign ALUResultE = IsMResultE ? MDU_ResultE
                                   : Int_ALUResultE;

    // ==========================================
    // BRANCH/JUMP LOGIC
    // ==========================================
    assign branch_equal       = (SrcA_Forwarded == SrcB_Forwarded);
    assign branch_signed_lt   = ($signed(SrcA_Forwarded) <
                                 $signed(SrcB_Forwarded));
    assign branch_unsigned_lt = (SrcA_Forwarded < SrcB_Forwarded);

    always @(*) begin
        case (BranchTypeE)
            3'b000: TakeBranchE =  branch_equal;        // BEQ
            3'b001: TakeBranchE = ~branch_equal;        // BNE
            3'b100: TakeBranchE =  branch_signed_lt;    // BLT
            3'b101: TakeBranchE = ~branch_signed_lt;    // BGE
            3'b110: TakeBranchE =  branch_unsigned_lt;  // BLTU
            3'b111: TakeBranchE = ~branch_unsigned_lt;  // BGEU
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
    // PIPELINED MULTIPLICATION
    //
    // The old implementation instantiated three parallel 64-bit products
    // directly from the forwarded EX operands. Post-route timing therefore
    // crossed forwarding muxes, two cascaded DSP48s and a long carry chain in
    // one cycle, while consuming 12 DSP48s per core.
    //
    // One signed 33x33 product covers all four RV32M multiply variants. Each
    // operand is sign- or zero-extended when the request is accepted, then the
    // product and architectural result are registered on separate cycles. The
    // no-reset data registers are intentional: busy/cnt qualify their validity
    // and the coding style lets Vivado absorb the input/output registers into
    // DSP48 AREG/BREG/PREG stages.
    // ============================================================
    reg signed [32:0] mul_a_pipe;
    reg signed [32:0] mul_b_pipe;
    (* use_dsp = "yes" *) reg signed [65:0] mul_product_pipe;
    reg        [4:0]  mul_op_pipe;
    reg               doing_mul;

    always @(posedge clk) begin
        if (start && !busy && is_mul) begin
            mul_a_pipe <= ((op == ALU_MULH) || (op == ALU_MULHSU)) ?
                          $signed({A[31], A}) : $signed({1'b0, A});
            mul_b_pipe <= (op == ALU_MULH) ?
                          $signed({B[31], B}) : $signed({1'b0, B});
            mul_op_pipe <= op;
        end

        // cnt=3 is the dedicated DSP stage. The following cnt=2 cycle
        // selects low/high 32 bits into the architectural result register.
        if (busy && doing_mul && (cnt == 6'd3))
            mul_product_pipe <= mul_a_pipe * mul_b_pipe;
    end

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
            doing_mul <= 1'b0;
        end
        else begin
            done <= 1'b0;

            // ====================================================
            // START NEW OPERATION
            // ====================================================
            if (start && !busy) begin

                // ------------------------------
                // MUL group: registered input -> DSP product -> result.
                // Three busy cycles deliberately break the old single-cycle
                // forwarding-to-product critical path.
                // ------------------------------
                if (is_mul) begin
                    busy      <= 1'b1;
                    cnt       <= 6'd3;
                    doing_mul <= 1'b1;
                end

                // ------------------------------
                // DIV/REM group
                // ------------------------------
                else if (is_divrem) begin
                    doing_mul <= 1'b0;

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
                    doing_mul <= 1'b0;
                end
            end

            // ====================================================
            // OPERATION RUNNING
            // ====================================================
            else if (busy) begin
                if (doing_mul) begin
                    if (cnt == 6'd3) begin
                        // mul_product_pipe captures on this edge.
                        cnt <= 6'd2;
                    end
                    else if (cnt == 6'd2) begin
                        result <= (mul_op_pipe == ALU_MUL) ?
                                  mul_product_pipe[31:0] :
                                  mul_product_pipe[63:32];
                        cnt <= 6'd1;
                    end
                    else begin
                        busy      <= 1'b0;
                        done      <= 1'b1;
                        cnt       <= 6'd0;
                        doing_mul <= 1'b0;
                    end
                end
                else begin
                    // Last division/special-case cycle: operation done.
                    if (cnt == 6'd1) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        cnt  <= 6'd0;
                    end

                    // Restoring division iteration.
                    else begin
                        dividend  <= div_shift;
                        remainder <= rem_next;
                        quotient  <= quo_next;
                        cnt       <= cnt - 6'd1;

                        // cnt == 2 means rem_next/quo_next is final result.
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
    end

endmodule
