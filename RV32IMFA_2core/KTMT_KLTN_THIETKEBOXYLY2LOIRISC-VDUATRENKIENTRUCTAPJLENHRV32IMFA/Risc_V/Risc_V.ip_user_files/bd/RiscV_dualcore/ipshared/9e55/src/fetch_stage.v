module fetch_stage #(
    parameter [31:0] RESET_ADDR = 32'h0000_0000 
) (
    input clk, rst,
    input stall,         
    input bus_ready,     
    input PCSrcE,
    input [31:0] PCTargetE,
    
    output [31:0] imem_addr,
    input  [31:0] imem_instr,
    
    output [31:0] InstrF, PCF, PCPlus4F
);
    wire [31:0] PC_Next;
    wire PC_Write;

    assign PC_Write = ~stall && bus_ready;

    // 2. Mux chọn PC tiếp theo
    mux PC_MUX (
        .a(PCPlus4F), .b(PCTargetE),
        .s(PCSrcE),    .c(PC_Next)
    );

    // 3. Thanh ghi PC - Truyền RESET_ADDR vào parameter RESET_VECTOR của module con
    PC_module #(.RESET_VECTOR(RESET_ADDR)) Program_Counter (
        .clk(clk), .rst(rst),
        .PC_Write(PC_Write),
        .PC(PCF),
        .PC_Next(PC_Next)
    );

    // 4. Adder tính PC+4
    PC_Adder PC_adder (
        .a(PCF), .b(32'h4), .c(PCPlus4F)
    );

    assign imem_addr = PCF; 
    assign InstrF    = imem_instr;

endmodule