module add4 (
	input [12:0] pc_in,
	output [12:0] pc_out
);
    timeunit 1ns; timeprecision 1ps;	
	
	assign pc_out = pc_in + 13'd4;

endmodule