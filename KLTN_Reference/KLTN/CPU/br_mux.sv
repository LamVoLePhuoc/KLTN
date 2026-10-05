module br_mux (
	input br_sel,
	input [12:0] alu_data, pc_four,
	output [12:0] next_pc
);
    timeunit 1ns; timeprecision 1ps;
	
	assign next_pc = (br_sel) ? alu_data : pc_four;

endmodule