module id_ex_registers(
    input  wire         clk, rst, stall, flush,
    
    // --- Inputs từ tầng Decode (D) ---
    // Control Signals
    input  wire         RegWriteD, 
    input  wire         ALUSrcD, 
    input  wire         MemWriteD, 
    input  wire         MemReadD,      
    input  wire [1:0]   ResultSrcD,    
    input  wire         BranchD, 
    input  wire         JumpD, 
    input  wire [4:0]   ALUControlD, 
    input  wire         AtomicD,
    input  wire         FPRegWriteD,  
    input  wire [4:0]   FPUControlD, 
    input  wire [6:0]   OpD,
    
    // Data Signals
    input  wire [31:0] RD1_D, RD2_D, 
    input  wire [31:0] Imm_Ext_D, 
    input  wire [31:0] PCD, 
    input  wire [31:0] PCPlus4D,
    
    // Register Addresses (Integer)
    input  wire [4:0]  RD_D, RS1_D, RS2_D,

    // Register Addresses (FLOAT) 
    input  wire [4:0]  RD_F_D, RS1_F_D, RS2_F_D, 

    // Float Data
    input  wire [31:0] RD1_F_D, RD2_F_D,
    
    // --- Outputs cho tầng Execute (E) ---
    // Control Signals
    output reg          RegWriteE, 
    output reg          ALUSrcE, 
    output reg          MemWriteE, 
    output reg          MemReadE,
    output reg  [1:0]   ResultSrcE, 
    output reg          BranchE, 
    output reg          JumpE,
    output reg  [4:0]   ALUControlE, 
    output reg          AtomicE,
    output reg          FPRegWriteE,  
    output reg  [4:0]   FPUControlE, 
    output reg  [6:0]   OpE,
    
    // Data Signals
    output reg  [31:0] RD1_E, RD2_E, 
    output reg  [31:0] Imm_Ext_E, 
    output reg  [31:0] PCE, 
    output reg  [31:0] PCPlus4E,
    
    // Register Addresses (Integer)
    output reg  [4:0]  RD_E, RS1_E, RS2_E,

    // Register Addresses (FLOAT)
    output reg  [4:0]  RD_F_E, RS1_F_E, RS2_F_E,

    // Float Data
    output reg  [31:0] RD1_F_E, RD2_F_E
);

    always @(posedge clk or negedge rst) begin 
        if(!rst) begin
             {RegWriteE, ALUSrcE, MemWriteE, MemReadE, ResultSrcE, BranchE, JumpE, AtomicE, FPRegWriteE} <= 0;
             {ALUControlE, FPUControlE} <= 0; OpE <= 0;
             {RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E, RD1_F_E, RD2_F_E} <= 0;
             {RD_E, RS1_E, RS2_E} <= 0;
             // Reset cho Float Addresses
             {RD_F_E, RS1_F_E, RS2_F_E} <= 0; 
        end 
        else if(flush) begin
             // Khi flush chỉ cần xóa tín hiệu điều khiển (Control signals)
             {RegWriteE, ALUSrcE, MemWriteE, MemReadE, ResultSrcE, BranchE, JumpE, AtomicE, FPRegWriteE} <= 0;
             {ALUControlE, FPUControlE} <= 0; OpE <= 0;
             
        end 
        else if(!stall) begin
             RegWriteE    <= RegWriteD; 
             FPRegWriteE  <= FPRegWriteD; 
             ALUSrcE      <= ALUSrcD; 
             MemWriteE    <= MemWriteD;
             MemReadE     <= MemReadD;
             ResultSrcE   <= ResultSrcD;
             BranchE      <= BranchD; 
             JumpE        <= JumpD;
             AtomicE      <= AtomicD;
             ALUControlE  <= ALUControlD; 
             FPUControlE  <= FPUControlD; 
             OpE          <= OpD;
             
             RD1_E        <= RD1_D; 
             RD2_E        <= RD2_D; 
             Imm_Ext_E    <= Imm_Ext_D;
             RD1_F_E      <= RD1_F_D; 
             RD2_F_E      <= RD2_F_D;
             PCE          <= PCD; 
             PCPlus4E     <= PCPlus4D;
             
             RD_E         <= RD_D; 
             RS1_E        <= RS1_D; 
             RS2_E        <= RS2_D;
             
             // Truyền địa chỉ Float
             RD_F_E       <= RD_F_D;
             RS1_F_E      <= RS1_F_D;
             RS2_F_E      <= RS2_F_D;
        end
    end
endmodule