module forward2mux (
	input  [63:0] rs2_dataE, alu_dataM, wb_data, wb_dataC, bridge_wr_dataM, bridge_wr_dataW, bridge_wr_dataC,
	input   [2:0] forward2sel,
	output [63:0] forward2out
);
    timeunit 1ns; timeprecision 1ps;
	
	assign forward2out = (forward2sel == 3'b000) ? rs2_dataE :
	                     (forward2sel == 3'b001) ? alu_dataM : 
						 (forward2sel == 3'b010) ? wb_data : 
						 (forward2sel == 3'b011) ? wb_dataC :
						 (forward2sel == 3'b100) ? bridge_wr_dataM :
						 (forward2sel == 3'b101) ? bridge_wr_dataW : bridge_wr_dataC;

endmodule