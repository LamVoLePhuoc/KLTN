module writeback_stage(
    // --- Control Signals ---
    input  wire [1:0]  ResultSrcW,   // 2 bit: 00=ALU, 01=Mem, 10=PC+4
    
    // --- Data Inputs ---
    input  wire [31:0] ALU_ResultW,  // Kết quả tính toán (Int hoặc Float)
    input  wire [31:0] ReadDataW,    // Kết quả đọc từ RAM
    input  wire [31:0] PCPlus4W,    
    
    // --- Output ---
    output wire [31:0] ResultW       // Dữ liệu sẽ ghi vào Register File
);

    // MUX 3-to-1 Logic
    assign ResultW = (ResultSrcW == 2'b00) ? ALU_ResultW :
                     (ResultSrcW == 2'b01) ? ReadDataW :
                     (ResultSrcW == 2'b10) ? PCPlus4W : 
                     32'b0; // Default case

endmodule