module fp_regfile #(
    parameter DataWidth  = 64,	// Double precision
    parameter NumRegs    = 32,	// 32 registers
    parameter IndexWidth = 5  	// logarit base 2 of NumRegs
) (
    input  logic                  clk,
    input  logic				  reset,
    input  logic                  writeEn,
    input  logic                  writeCommit,
    input  logic [IndexWidth-1:0] writeAddr,
    input  logic [DataWidth-1:0]  writeData,
    input  logic [IndexWidth-1:0] readAddr1,
    input  logic [IndexWidth-1:0] readAddr2,
    input  logic [IndexWidth-1:0] readAddr3,
    input  logic                  rs1_rf_sel,
    input  logic                  rs2_rf_sel,
    input  logic                  rs3_rf_sel,
    output logic [DataWidth-1:0]  readData1,
    output logic [DataWidth-1:0]  readData2,
    output logic [DataWidth-1:0]  readData3
);
    timeunit 1ns; timeprecision 1ps;
    
    // Declare the register array
    logic [DataWidth-1:0] regs[2][NumRegs];     // <data> regfile <main rf> <temp rf>

    // Write logic	
    always_ff @(negedge clk or negedge reset) begin
        if (reset == 1'b0) begin
            for (int i = 0; i < 2; i = i + 1) begin
                for (int j = 0; j < NumRegs; j = j + 1) begin
                    regs[i][j] <= '0;
                end
            end
        end
        else if ((writeEn == 1'b1) & (writeAddr != '0)) begin
            if (writeCommit) begin
                regs[0][writeAddr] <= writeData;
                regs[1][writeAddr] <= writeData;
            end
            else begin
                regs[0][writeAddr] <= regs[0][writeAddr];
                regs[1][writeAddr] <= writeData;
            end
        end
    end
    
    assign readData1 = (rs1_rf_sel) ? regs[1][readAddr1] : regs[0][readAddr1];
    assign readData2 = (rs2_rf_sel) ? regs[1][readAddr2] : regs[0][readAddr2];
    assign readData3 = (rs3_rf_sel) ? regs[1][readAddr3] : regs[0][readAddr3];
endmodule
  