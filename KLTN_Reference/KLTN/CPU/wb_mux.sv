module wb_mux (
	input  [12:0] pc_four,
	input  [63:0] alu_data, ld_data,
	input   [1:0] wb_sel,
	output [63:0] wb_data
);
    timeunit 1ns; timeprecision 1ps;
	
	assign wb_data = (wb_sel == 2'h0) ? alu_data :
	                 (wb_sel == 2'h1) ? ld_data  : pc_four;

endmodule