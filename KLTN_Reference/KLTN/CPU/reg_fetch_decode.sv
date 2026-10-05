module reg_fetch_decode (
    input  [31:0] instrF,
    input  [12:0] pcF, pc4F,
    input  [4:0]  wr_addr_tagF,
    input         rs1_rf_selF, rs2_rf_selF,
    
    input         clk, sclr, aclr, en,
    
    output logic [31:0] instrD,
    output logic [4:0]  wr_addr_tagD,
    output logic        rs1_rf_selD, rs2_rf_selD,
    output logic [12:0] pcD, pc4D
);
    timeunit 1ns; timeprecision 1ps;
    
    always_ff @ (posedge clk, negedge aclr)
        if (!aclr) begin
            instrD       <= 0;
            wr_addr_tagD <= 0;
            pcD          <= 0;
            pc4D         <= 0;
            rs1_rf_selD  <= 0;
            rs2_rf_selD  <= 0;
        end else if (sclr) begin
            instrD       <= 0;
            wr_addr_tagD <= 0;
            pcD          <= 0;
            pc4D         <= 0;
            rs1_rf_selD  <= 0;
            rs2_rf_selD  <= 0;
        end else if (en) begin
            instrD       <= instrF;
            wr_addr_tagD <= wr_addr_tagF;
            pcD          <= pcF;
            pc4D         <= pc4F;
            rs1_rf_selD  <= rs1_rf_selF;
            rs2_rf_selD  <= rs2_rf_selF;
        end

endmodule