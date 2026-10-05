module bridgemux (
	input  [63:0] rf_data, alu_dataM, wb_data, wb_dataC,
	input   [1:0] bridge_rddata_sel,
	output [63:0] bridge_rddata_out
);
    timeunit 1ns; timeprecision 1ps;
	
	assign bridge_rddata_out = (bridge_rddata_sel == 2'b00) ? rf_data :
	                           (bridge_rddata_sel == 2'b01) ? alu_dataM : 
							   (bridge_rddata_sel == 2'b10) ? wb_data : wb_dataC;

endmodule