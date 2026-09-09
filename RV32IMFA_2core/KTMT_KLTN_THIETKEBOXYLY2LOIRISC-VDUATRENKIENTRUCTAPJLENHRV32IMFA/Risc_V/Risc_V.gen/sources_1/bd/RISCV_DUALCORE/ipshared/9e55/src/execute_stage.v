module execute_stage(
    input clk, rst, 

    // Control Signals
    input RegWriteE, ALUSrcE, MemWriteE, ResultSrcE, BranchE,
    input [4:0] ALUControlE,
    input AtomicE,
    
    // FPU Control
    input FPRegWriteE,
    input [4:0] FPUControlE,
    input [6:0] OpE,

    // Data Inputs
    input [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E,
    input [4:0] RD_E,
    
    // Float Data Inputs
    input [31:0] RD1_F_E, RD2_F_E, 

    // Forwarding Data (Từ tầng Memory và Writeback)
    input [31:0] ResultW,      // Kết quả Int từ WB
    input [31:0] ALU_ResultM,  // Kết quả Int từ Mem
    input [31:0] F_ResultW,    // Kết quả Float từ WB 
    input [31:0] F_ResultM,    // Kết quả Float từ Mem 

    // Forwarding Selectors
    input [1:0] ForwardA_E, ForwardB_E,       // Cho Int
    input [1:0] ForwardA_F_E, ForwardB_F_E,   // Cho Float

    // Outputs
    output PCSrcE,
    output [31:0] ALU_ResultE, WriteDataE, PCTargetE,
    
    // Stall Request Output
    output wire Stall_FPU  
);

    wire [31:0] Src_A, Src_B_interim, Src_B;
    wire [31:0] ALU_Result_Int;
    wire ZeroE;
    
    // FPU Wires
    wire [31:0] FPU_Result;
    wire        fpu_out_valid;
    wire        fpu_internal_stall;
    wire [31:0] Src_A_F, Src_B_F_interim; 

    // --- 1. INTEGER ALU LOGIC ---
    Mux_3_by_1 srca_mux (.a(RD1_E), .b(ResultW), .c(ALU_ResultM), .s(ForwardA_E), .d(Src_A));
    Mux_3_by_1 srcb_mux (.a(RD2_E), .b(ResultW), .c(ALU_ResultM), .s(ForwardB_E), .d(Src_B_interim));
    mux alu_src_mux (.a(Src_B_interim), .b(Imm_Ext_E), .s(ALUSrcE), .c(Src_B));

    ALU alu (
        .A(Src_A), .B(Src_B),
        .ALUControl(ALUControlE),
        .Zero(ZeroE),
        .Result(ALU_Result_Int)
       
    );

    PC_Adder branch_adder (.a(PCE), .b(Imm_Ext_E), .c(PCTargetE));
    assign PCSrcE = ZeroE & BranchE;


    // --- 2. FPU PREPARATION LOGIC ---
    wire is_FPU_Op = (OpE == 7'b1010011); // OP-FP
    wire is_FSW    = (OpE == 7'b0100111); // STORE-FP

    
    // Forwarding cho RS1 (Float)
    Mux_3_by_1 fwd_a_f_mux (
        .a(RD1_F_E), 
        .b(F_ResultW),   // Forward từ WB
        .c(F_ResultM),   // Forward từ Mem
        .s(ForwardA_F_E), 
        .d(Src_A_F)
    );

    // Forwarding cho RS2 (Float) - Dùng cho cả tính toán và STORE (FSW)
    Mux_3_by_1 fwd_b_f_mux (
        .a(RD2_F_E), 
        .b(F_ResultW), 
        .c(F_ResultM), 
        .s(ForwardB_F_E), 
        .d(Src_B_F_interim)
    );


    // --- 3. INPUT SELECTION ---
    reg [31:0] operand_rs1_final;
    always @(*) begin
        case (FPUControlE)
       
            5'b01110, 5'b01111, 5'b10001: operand_rs1_final = Src_A; // Lấy từ Int (đã Forwarding)
            // Các lệnh lấy Float Reg
            default: operand_rs1_final = Src_A_F; // Lấy từ Float (đã Forwarding)
        endcase
    end

    // Start khi là lệnh OP-FP.
    wire fpu_start_signal = is_FPU_Op; 

    // --- 4. FPU INSTANTIATION ---
    FPU fpu_unit (
        .clk(clk),
        .rst_n(~rst),            
        .in_start(fpu_start_signal), 
        .in_opcode(FPUControlE), 
        .in_rs1(operand_rs1_final),
        .in_rs2(Src_B_F_interim),
        .out_data(FPU_Result),
        .out_valid(fpu_out_valid),
        .out_stall(fpu_internal_stall)
    );

    // --- 5. OUTPUT ASSIGNMENTS ---

    // ALU Result chọn giữa Int và Float
    assign ALU_ResultE = is_FPU_Op ? FPU_Result : ALU_Result_Int;

    // WriteDataE (Cho Store): Nếu FSW thì ghi Float (đã forward), ngược lại ghi Int
    assign WriteDataE  = is_FSW ? Src_B_F_interim : Src_B_interim;

    // Stall Request logic
    // Logic: Stall khi FPU đang bận (internal) HOẶC khi đang chạy lệnh FPU mà chưa có kết quả (valid)
    assign Stall_FPU = fpu_internal_stall || (is_FPU_Op && !fpu_out_valid);

endmodule