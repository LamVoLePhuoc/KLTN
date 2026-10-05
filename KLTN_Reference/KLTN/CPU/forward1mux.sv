module forward1mux (
	input  [63:0] rs1_dataE, alu_dataM, wb_data, wb_dataC, bridge_wr_dataM, bridge_wr_dataW, bridge_wr_dataC,
	input   [2:0] forward1sel,
	output [63:0] forward1out
);
    timeunit 1ns; timeprecision 1ps;
	
	assign forward1out = (forward1sel == 3'b000) ? rs1_dataE :
	                     (forward1sel == 3'b001) ? alu_dataM : 
						 (forward1sel == 3'b010) ? wb_data : 
						 (forward1sel == 3'b011) ? wb_dataC :
						 (forward1sel == 3'b100) ? bridge_wr_dataM :
						 (forward1sel == 3'b101) ? bridge_wr_dataW : bridge_wr_dataC;

endmodule