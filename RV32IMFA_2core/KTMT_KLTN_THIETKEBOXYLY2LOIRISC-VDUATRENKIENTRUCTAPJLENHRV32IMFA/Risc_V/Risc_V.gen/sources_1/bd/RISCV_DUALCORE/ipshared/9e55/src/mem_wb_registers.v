module mem_wb_registers(
    input clk, rst, stall, flush,
    
    // --- Control Signals ---
    input        RegWriteM, 
    input [1:0]  ResultSrcM,   
    input        FPRegWriteM,
    
    // --- Data Inputs ---
    input [4:0]  RD_M,
    input [31:0] PCPlus4M, 
    input [31:0] ALU_ResultM, 
    input [31:0] ReadDataM,    // Dữ liệu này đến từ Sync RAM (đã được chốt)
    
    // --- Outputs ---
    output reg       RegWriteW, 
    output reg [1:0] ResultSrcW, 
    output reg       FPRegWriteW,
    
    output reg [4:0]  RD_W,
    output reg [31:0] PCPlus4W, 
    output reg [31:0] ALU_ResultW, 
    output     [31:0] ReadDataW  
);

    // 1. Các tín hiệu cần lưu vào thanh ghi pipeline (như bình thường)
    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            {RegWriteW, FPRegWriteW} <= 0;
            ResultSrcW               <= 2'b0; 
            {RD_W, PCPlus4W, ALU_ResultW} <= 0;
        end else if(flush) begin
            {RegWriteW, FPRegWriteW} <= 0;
            ResultSrcW               <= 2'b0;
            {RD_W, PCPlus4W, ALU_ResultW} <= 0;
        end else if(!stall) begin
            RegWriteW   <= RegWriteM;
            ResultSrcW  <= ResultSrcM;
            FPRegWriteW <= FPRegWriteM;
            
            RD_W        <= RD_M;
            PCPlus4W    <= PCPlus4M;
            ALU_ResultW <= ALU_ResultM;
         
        end
    end

    // 2. Kỹ thuật Pass-through cho Sync RAM
    // Vì ReadDataM đã được chốt bên trong module RAM ở cạnh lên clock vừa rồi,
    // nó đã ổn định và sẵn sàng cho tầng WriteBack ngay lập tức.
    assign ReadDataW = ReadDataM;

endmodule