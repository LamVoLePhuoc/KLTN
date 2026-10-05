module brcomp (
	input [63:0] rs1_data, rs2_data,
	input br_unsigned,
	output br_less, br_equal
);
    timeunit 1ns; timeprecision 1ps;
	
	logic [64:0] a, b, c;
	
	assign a = (br_unsigned) ? {1'b0, rs1_data} : {rs1_data[63], rs1_data};
	assign b = (br_unsigned) ? {1'b0, rs2_data} : {rs2_data[63], rs2_data};
	assign c = a + ~b + 1;

	assign br_less  = c[64];
	assign br_equal = ~|c;

endmodule
