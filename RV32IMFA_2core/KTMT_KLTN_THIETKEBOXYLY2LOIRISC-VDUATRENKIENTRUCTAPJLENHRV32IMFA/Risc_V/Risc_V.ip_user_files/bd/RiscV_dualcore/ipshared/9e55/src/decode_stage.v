module decode_stage(
    input  wire clk, rst,

    // --- Từ tầng Fetch (IF) ---
    input  wire [31:0] InstrD,
    input  wire [31:0] PCD,
    input  wire [31:0] PCPlus4D,

    // --- Từ tầng Write-Back (WB) ---
    input  wire        RegWriteW,     // Cho Integer
    input  wire        FPRegWriteW,   // Cho Float
    input  wire [4:0]  RD_W,          // Địa chỉ ghi (Dùng chung cho cả Int/Float)
    input  wire [31:0] ResultW,       // Dữ liệu ghi (Dùng chung)
    
    // --- Tín hiệu điều khiển (Output) ---
    output wire        RegWriteD,
    output wire        FPRegWriteD,
    output wire        ALUSrcD,
    output wire        MemWriteD,
    output wire        MemReadD,       
    output wire [1:0]  ResultSrcD,    
    output wire        BranchD,
    output wire        JumpD,          
    output wire [4:0]  ALUControlD,
    output wire [4:0]  FPUControlD,
    output wire [2:0]  ImmSrcD,
    output wire        AtomicD,
    
    // --- Dữ liệu (Output) ---
    output wire [31:0] RD1_D, RD2_D,     // Dữ liệu Int
    output wire [31:0] RD1_F_D, RD2_F_D, // Dữ liệu Float        
    
    output wire [31:0] Imm_Ext_D,
    output wire [31:0] PCD_Out,        
    output wire [31:0] PCPlus4D_Out,
    
    // --- Địa chỉ (Output cho Hazard Unit & Pipeline Reg) ---
    // INTEGER ADDRESSES
    output wire [4:0]  RD_D, RS1_D, RS2_D, 
    
    // FLOAT ADDRESSES 
    output wire [4:0]  RD_F_D, RS1_F_D, RS2_F_D, RS3_F_D 
);

    // Kết nối PC
    assign PCD_Out = PCD;
    assign PCPlus4D_Out = PCPlus4D;

    // --- 1. KHỐI ĐIỀU KHIỂN ---
    Control_Unit control (
        .Op(InstrD[6:0]),
        .funct3(InstrD[14:12]),
        .funct7(InstrD[31:25]),
        .RegWrite(RegWriteD),
        .FPRegWrite(FPRegWriteD), 
        .ImmSrc(ImmSrcD),
        .ALUSrc(ALUSrcD),
        .MemWrite(MemWriteD),
        .MemRead(MemReadD),       
        .ResultSrc(ResultSrcD),   
        .Branch(BranchD),
        .Jump(JumpD),             
        .ALUControl(ALUControlD),
        .FPUControl(FPUControlD), 
        .Atomic(AtomicD)
    );

    // --- 2. TẬP THANH GHI SỐ NGUYÊN ---
    Register_File rf (
        .clk(clk), .rst(rst),
        .WE3(RegWriteW),
        .WD3(ResultW),
        .A1(InstrD[19:15]),
        .A2(InstrD[24:20]),
        .A3(RD_W),
        .RD1(RD1_D), .RD2(RD2_D)
    );

    // --- 3. TẬP THANH GHI SỐ THỰC ---
    FP_Register_File fprf (
        .clk(clk), .rst(rst),
        .WE3(FPRegWriteW),    
        .WD3(ResultW),        
        .A1(InstrD[19:15]),   // Rs1
        .A2(InstrD[24:20]),   // Rs2
        .A3(InstrD[31:27]),   // Rs3 (Dùng cho FMADD)
        .A_W(RD_W),           
        .RD1(RD1_F_D), 
        .RD2(RD2_F_D)
   
    );

    // --- 4. KHỐI MỞ RỘNG DẤU ---
    Sign_Extend extension (
        .In(InstrD),
        .ImmSrc(ImmSrcD),
        .Imm_Ext(Imm_Ext_D)
    );

    // --- 5. TRÍCH XUẤT ĐỊA CHỈ (QUAN TRỌNG) ---
    // Địa chỉ Int
    assign RD_D      = InstrD[11:7];
    assign RS1_D     = InstrD[19:15];
    assign RS2_D     = InstrD[24:20];

    // Địa chỉ Float (Map giống hệt Int, nhưng xuất ra port riêng)
    assign RD_F_D    = InstrD[11:7];
    assign RS1_F_D   = InstrD[19:15];
    assign RS2_F_D   = InstrD[24:20];
    assign RS3_F_D   = InstrD[31:27]; 

endmodule