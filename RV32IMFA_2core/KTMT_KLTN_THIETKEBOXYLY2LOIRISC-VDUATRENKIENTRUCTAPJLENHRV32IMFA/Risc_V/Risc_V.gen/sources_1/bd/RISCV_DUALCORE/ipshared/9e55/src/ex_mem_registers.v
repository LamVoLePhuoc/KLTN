module ex_mem_registers(
    input wire clk, rst, stall, flush,
    
    // --- Control Signals ---
    input wire       RegWriteE, 
    input wire       MemWriteE, 
    input wire       MemReadE,    
    input wire [1:0] ResultSrcE,  
    input wire       AtomicE,
    input wire       FPRegWriteE, 
    
    // --- Data Signals ---
    input wire [4:0]  RD_E,
    input wire [31:0] PCPlus4E, 
    input wire [31:0] ALU_ResultE, 
    input wire [31:0] WriteDataE, 
    
    // --- Outputs ---
    output reg       RegWriteM, 
    output reg       MemWriteM, 
    output reg       MemReadM,    
    output reg [1:0] ResultSrcM, 
    output reg       AtomicM,
    output reg       FPRegWriteM, 
    
    output reg [4:0]  RD_M,
    output reg [31:0] PCPlus4M, 
    output reg [31:0] ALU_ResultM, 
    output reg [31:0] WriteDataM
);

    always @(posedge clk or negedge rst) begin
        if(!rst) begin
            {RegWriteM, MemWriteM, MemReadM, AtomicM, FPRegWriteM} <= 0;
            ResultSrcM <= 2'b0;
            {RD_M, PCPlus4M, ALU_ResultM, WriteDataM} <= 0;
        end 
        else if(flush) begin
          
            {RegWriteM, MemWriteM, MemReadM, AtomicM, FPRegWriteM} <= 0;
            ResultSrcM <= 2'b0;
         
        end 
        else if(!stall) begin
            RegWriteM   <= RegWriteE;
            MemWriteM   <= MemWriteE;
            MemReadM    <= MemReadE;
            ResultSrcM  <= ResultSrcE;
            AtomicM     <= AtomicE;
            FPRegWriteM <= FPRegWriteE; 
            
            RD_M        <= RD_E;
            PCPlus4M    <= PCPlus4E;
            ALU_ResultM <= ALU_ResultE;
            WriteDataM  <= WriteDataE;
        end
    end
endmodule