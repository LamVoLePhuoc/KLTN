module RV32IMFA #(
    parameter [31:0] RESET_ADDR = 32'h0000_0000  // Giá trị mặc định
	 )(
    input wire clk, rst,

    // ==========================================================
    // 1. GIAO TIẾP DUAL CORE 
    // ==========================================================
    // Tín hiệu Stall từ Arbiter (Khi bị tranh chấp RAM)
    input wire        Stall_Core_External, 
    
    // Tín hiệu Snoop từ Core kia (Để hủy Atomic Reservation nếu bị ghi đè)a
    input wire [31:0] Snoop_Addr,          
    input wire        Snoop_WE,            

    // ==========================================================
    // 2. GIAO TIẾP VỚI BỘ NHỚ
    // ==========================================================
    // Instruction Memory Interface
    output wire [31:0] PCF,             
    input  wire [31:0] InstrF,          
    
    // Data Memory Interface (Kết nối ra Arbiter)
    output wire [31:0] Mem_AddrM,       
    output wire [31:0] Mem_WriteDataM,  
    output wire        Mem_WriteEnM,    
    output wire        Mem_ReadEnM,     
    input  wire [31:0] Mem_ReadDataM,   

    // ==========================================================
    // 3. DEBUG OUTPUTS
    // ==========================================================
    output wire [31:0] ResultW,         
    output wire [31:0] ALU_ResultE_Debug 
);

    // ==========================================================
    // KHAI BÁO DÂY TÍN HIỆU (WIRES)
    // ==========================================================

    // --- Hazard Control Wires ---
    wire StallF, StallD, StallE;       // Stall do Hazard Unit sinh ra
    wire FlushD, FlushE, FlushM;
    wire [1:0] ForwardAE, ForwardBE;
    wire [1:0] ForwardAE_F, ForwardBE_F;
    wire Stall_FPU_Req;

    // --- [QUAN TRỌNG] LOGIC STALL TỔNG HỢP ---
    // Core phải dừng khi: (Hazard Unit bắt dừng) HOẶC (Arbiter bắt dừng)
    wire StallF_Final = StallF | Stall_Core_External;
    wire StallD_Final = StallD | Stall_Core_External;
    wire StallE_Final = StallE | Stall_Core_External;
    wire StallM_Final =          Stall_Core_External; // Stage Memory cũng phải dừng chờ Bus

    // --- Fetch Stage Wires ---
    wire [31:0] PCPlus4F, PCTargetE, PCSrcE;

    // --- Decode Stage Wires ---
    wire [31:0] InstrD, PCD, PCPlus4D;
    wire [31:0] RD1_D, RD2_D, Imm_Ext_D, RD1_F_D, RD2_F_D;
    wire RegWriteD, FPRegWriteD, MemWriteD, MemReadD;
    wire ALUSrcD, BranchD, JumpD, AtomicD;
    wire [1:0] ResultSrcD;
    wire [4:0] ALUControlD, FPUControlD;
    wire [2:0] ImmSrcD;
    wire [4:0] Rs1_D, Rs2_D, Rd_D, Rs1_F_D, Rs2_F_D, Rd_F_D, Rs3_F_D;

    // --- Execute Stage Wires ---
    wire [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E;
    wire [31:0] RD1_F_E, RD2_F_E;
    wire RegWriteE, FPRegWriteE, MemWriteE, MemReadE;
    wire ALUSrcE, BranchE, JumpE, AtomicE;
    wire [1:0] ResultSrcE;
    wire [4:0] ALUControlE, FPUControlE;
    wire [6:0] OpE;
    wire [4:0] Rs1_E, Rs2_E, Rd_E, Rs1_F_E, Rs2_F_E, Rd_F_E;
    wire [31:0] ALUResultE, WriteDataE;

    // --- Memory Stage Wires ---
    wire [31:0] ALUResultM, WriteDataM, PCPlus4M;
    wire [4:0]  Rd_M, Rd_F_M;
    wire RegWriteM, FPRegWriteM, MemWriteM, MemReadM, AtomicM;
    wire [1:0] ResultSrcM;
    wire [31:0] ReadDataM; // Dữ liệu trả về sau khi xử lý Atomic

    // --- Writeback Stage Wires ---
    wire [31:0] ALUResultW, ReadDataW, PCPlus4W;
    wire [4:0]  Rd_W, Rd_F_W;
    wire RegWriteW, FPRegWriteW;
    wire [1:0] ResultSrcW;

    // --- FPU Forwarding Helpers ---
    wire [31:0] F_ResultM = ALUResultM; 
    wire [31:0] F_ResultW = ResultW;    

    // ==========================================================
    // ASSIGNMENTS
    // ==========================================================
    assign ALU_ResultE_Debug = ALUResultE;

    // Trích xuất địa chỉ thanh ghi (Decode)
    assign Rs1_D   = InstrD[19:15];
    assign Rs2_D   = InstrD[24:20];
    assign Rd_D    = InstrD[11:7];
    assign Rs1_F_D = InstrD[19:15]; 
    assign Rs2_F_D = InstrD[24:20];
    assign Rd_F_D  = InstrD[11:7];
    assign Rs3_F_D = InstrD[31:27];

    // ==========================================================
    // KẾT NỐI CÁC MODULE (PIPELINE STAGES)
    // ==========================================================

    // ----------------------------------------------------------
    // 1. FETCH STAGE
    // ----------------------------------------------------------
    fetch_stage #(
        .RESET_ADDR(RESET_ADDR)  
    ) fetch (                    
        .clk(clk), 
        .rst(rst),
        .stall(StallF_Final),
        .bus_ready(~Stall_Core_External),
        .PCSrcE(PCSrcE),
        .PCTargetE(PCTargetE),
        
        .imem_addr(),          
        .imem_instr(InstrF),   
        .InstrF(),             
        .PCF(PCF),             
        .PCPlus4F(PCPlus4F)
    );

    // ----------------------------------------------------------
    // IF/ID REGISTERS
    // ----------------------------------------------------------
    if_id_registers if_id (
        .clk(clk), .rst(rst),
        .stall(StallD_Final),          // Dừng khi Hazard hoặc Arbiter bảo dừng
        .flush(FlushD),
        .bus_ready(1'b1),     
        
        .InstrF(InstrF), .PCF(PCF), .PCPlus4F(PCPlus4F),
        .InstrD(InstrD), .PCD(PCD), .PCPlus4D(PCPlus4D)
    );

    // ----------------------------------------------------------
    // 2. DECODE STAGE
    // ----------------------------------------------------------
    decode_stage decode (
        .clk(clk), .rst(rst),
        
        // Inputs
        .InstrD(InstrD), .PCD(PCD), .PCPlus4D(PCPlus4D),
        .RegWriteW(RegWriteW), .FPRegWriteW(FPRegWriteW),
        .RD_W(Rd_W), .ResultW(ResultW),
        
        // Control Outputs
        .RegWriteD(RegWriteD), .FPRegWriteD(FPRegWriteD),
        .ALUSrcD(ALUSrcD), .MemWriteD(MemWriteD), .MemReadD(MemReadD),
        .ResultSrcD(ResultSrcD), .BranchD(BranchD), .JumpD(JumpD), .AtomicD(AtomicD),
        .ALUControlD(ALUControlD), .FPUControlD(FPUControlD), .ImmSrcD(ImmSrcD),
        
        // Data Outputs
        .RD1_D(RD1_D), .RD2_D(RD2_D),
        .RD1_F_D(RD1_F_D), .RD2_F_D(RD2_F_D),
        .Imm_Ext_D(Imm_Ext_D),
        
        // Address Outputs (Unused inputs are left unconnected)
        .RD_D(), .RS1_D(), .RS2_D(), 
        .RD_F_D(), .RS1_F_D(), .RS2_F_D(), .RS3_F_D(),
        .PCD_Out(), .PCPlus4D_Out()
    );

    // ----------------------------------------------------------
    // ID/EX REGISTERS
    // ----------------------------------------------------------
    id_ex_registers id_ex (
        .clk(clk), .rst(rst), 
        .stall(StallE_Final),          // Dừng khi Hazard hoặc Arbiter bảo dừng
        .flush(FlushE),
        
        // Inputs
        .RegWriteD(RegWriteD), .ALUSrcD(ALUSrcD), 
        .MemWriteD(MemWriteD), .MemReadD(MemReadD),
        .ResultSrcD(ResultSrcD), .BranchD(BranchD), .JumpD(JumpD),
        .ALUControlD(ALUControlD), .AtomicD(AtomicD),
        .FPRegWriteD(FPRegWriteD), .FPUControlD(FPUControlD),
        .OpD(InstrD[6:0]), 
        .RD1_D(RD1_D), .RD2_D(RD2_D), .Imm_Ext_D(Imm_Ext_D),
        .PCD(PCD), .PCPlus4D(PCPlus4D),
        .RD_D(Rd_D), .RS1_D(Rs1_D), .RS2_D(Rs2_D),
        .RD1_F_D(RD1_F_D), .RD2_F_D(RD2_F_D),
        .RD_F_D(Rd_F_D), .RS1_F_D(Rs1_F_D), .RS2_F_D(Rs2_F_D),
        
        // Outputs
        .RegWriteE(RegWriteE), .ALUSrcE(ALUSrcE),
        .MemWriteE(MemWriteE), .MemReadE(MemReadE),
        .ResultSrcE(ResultSrcE), .BranchE(BranchE), .JumpE(JumpE),
        .ALUControlE(ALUControlE), .AtomicE(AtomicE),
        .FPRegWriteE(FPRegWriteE), .FPUControlE(FPUControlE),
        .OpE(OpE),
        .RD1_E(RD1_E), .RD2_E(RD2_E), .Imm_Ext_E(Imm_Ext_E),
        .PCE(PCE), .PCPlus4E(PCPlus4E),
        .RD_E(Rd_E), .RS1_E(Rs1_E), .RS2_E(Rs2_E),
        .RD1_F_E(RD1_F_E), .RD2_F_E(RD2_F_E),
        .RD_F_E(Rd_F_E), .RS1_F_E(Rs1_F_E), .RS2_F_E(Rs2_F_E)
    );

    // ----------------------------------------------------------
    // 3. EXECUTE STAGE
    // ----------------------------------------------------------
    execute_stage execute (
        .clk(clk), .rst(rst),
        
        // Control Inputs
        .RegWriteE(RegWriteE), .ALUSrcE(ALUSrcE), .MemWriteE(MemWriteE),
        .ResultSrcE(ResultSrcE[0]), 
        .BranchE(BranchE), .ALUControlE(ALUControlE), .AtomicE(AtomicE),
        .FPRegWriteE(FPRegWriteE), .FPUControlE(FPUControlE), .OpE(OpE),
        
        // Data Inputs
        .RD1_E(RD1_E), .RD2_E(RD2_E), .Imm_Ext_E(Imm_Ext_E),
        .PCE(PCE), .PCPlus4E(PCPlus4E), .RD_E(Rd_E),
        .RD1_F_E(RD1_F_E), .RD2_F_E(RD2_F_E),
        
        // Forwarding
        .ResultW(ResultW), .ALU_ResultM(ALUResultM),
        .F_ResultW(F_ResultW), .F_ResultM(F_ResultM),
        .ForwardA_E(ForwardAE), .ForwardB_E(ForwardBE),
        .ForwardA_F_E(ForwardAE_F), .ForwardB_F_E(ForwardBE_F),
        
        // Outputs
        .PCSrcE(PCSrcE),
        .ALU_ResultE(ALUResultE),
        .WriteDataE(WriteDataE),
        .PCTargetE(PCTargetE),
        .Stall_FPU(Stall_FPU_Req) 
    );

    // ----------------------------------------------------------
    // EX/MEM REGISTERS
    // ----------------------------------------------------------
    ex_mem_registers ex_mem (
        .clk(clk), .rst(rst), 
        .stall(StallM_Final),          // Dừng khi Arbiter bảo dừng 
        .flush(FlushM),
        
        // Inputs
        .RegWriteE(RegWriteE), .MemWriteE(MemWriteE), .MemReadE(MemReadE),
        .ResultSrcE(ResultSrcE), .AtomicE(AtomicE), .FPRegWriteE(FPRegWriteE),
        .RD_E(Rd_E), .PCPlus4E(PCPlus4E), 
        .ALU_ResultE(ALUResultE), .WriteDataE(WriteDataE),
        
        // Outputs
        .RegWriteM(RegWriteM), .MemWriteM(MemWriteM), .MemReadM(MemReadM),
        .ResultSrcM(ResultSrcM), .AtomicM(AtomicM), .FPRegWriteM(FPRegWriteM),
        .RD_M(Rd_M), .PCPlus4M(PCPlus4M), 
        .ALU_ResultM(ALUResultM), .WriteDataM(WriteDataM)
    );
    assign Rd_F_M = Rd_M; 

    // ----------------------------------------------------------
    // 4. MEMORY STAGE (ĐÃ TÍCH HỢP SNOOPING)
    // ----------------------------------------------------------
    memory_stage memory (
        .clk(clk), .rst(rst),
        .MemWriteM(MemWriteM), .MemReadM(MemReadM), .AtomicM(AtomicM),
        .ALU_ResultM(ALUResultM), .WriteDataM(WriteDataM),
        
        // --- [MỚI] SNOOP INPUTS ---
        .Snoop_Addr(Snoop_Addr),
        .Snoop_WE(Snoop_WE),

        // --- BUS INTERFACE ---
        .bus_addr(Mem_AddrM),
        .bus_write_data(Mem_WriteDataM),
        .bus_mem_write(Mem_WriteEnM),
        .bus_mem_read(Mem_ReadEnM),
        .bus_read_data(Mem_ReadDataM),
        
        // Output
        .ReadDataM(ReadDataM)
    );

    // ----------------------------------------------------------
    // MEM/WB REGISTERS
    // ----------------------------------------------------------
    mem_wb_registers mem_wb (
        .clk(clk), .rst(rst), 
        .stall(StallM_Final),          // Dừng khi Arbiter bảo dừng
        .flush(1'b0),
        
        // Inputs
        .RegWriteM(RegWriteM), .ResultSrcM(ResultSrcM), .FPRegWriteM(FPRegWriteM),
        .RD_M(Rd_M), .PCPlus4M(PCPlus4M), 
        .ALU_ResultM(ALUResultM), .ReadDataM(ReadDataM),
        
        // Outputs
        .RegWriteW(RegWriteW), .ResultSrcW(ResultSrcW), .FPRegWriteW(FPRegWriteW),
        .RD_W(Rd_W), .PCPlus4W(PCPlus4W), 
        .ALU_ResultW(ALUResultW), .ReadDataW(ReadDataW)
    );
    assign Rd_F_W = Rd_W;

    // ----------------------------------------------------------
    // 5. WRITEBACK STAGE
    // ----------------------------------------------------------
    writeback_stage writeback (
        .ResultSrcW(ResultSrcW),
        .ALU_ResultW(ALUResultW),
        .ReadDataW(ReadDataW),
        .PCPlus4W(PCPlus4W),
        .ResultW(ResultW)
    );

    // ----------------------------------------------------------
    // HAZARD UNIT (CONTROLLER)
    // ----------------------------------------------------------
    hazard_unit hazard (
        .rst(rst),
        // Decode Inputs
        .Rs1_D(Rs1_D), .Rs2_D(Rs2_D),
        .Rs1_F_D(Rs1_F_D), .Rs2_F_D(Rs2_F_D),
        // Execute Inputs
        .Rs1_E(Rs1_E), .Rs2_E(Rs2_E),
        .Rs1_F_E(Rs1_F_E), .Rs2_F_E(Rs2_F_E),
        .RD_E(Rd_E), .RD_F_E(Rd_F_E),
        .ResultSrcE0(ResultSrcE[0]), 
        .Stall_FPU_Req(Stall_FPU_Req),
        // Memory Inputs
        .RegWriteM(RegWriteM), .FPRegWriteM(FPRegWriteM),
        .RD_M(Rd_M), .RD_F_M(Rd_F_M),
        // Writeback Inputs
        .RegWriteW(RegWriteW), .FPRegWriteW(FPRegWriteW),
        .RD_W(Rd_W), .RD_F_W(Rd_F_W),
        
        // Outputs
        .ForwardAE(ForwardAE), .ForwardBE(ForwardBE),
        .ForwardAE_F(ForwardAE_F), .ForwardBE_F(ForwardBE_F),
        .StallF(StallF), .StallD(StallD), .StallE(StallE),
        .FlushD(FlushD), .FlushE(FlushE), .FlushM(FlushM)
    );

endmodule