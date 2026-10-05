module op_a_mux (
	input [12:0] pc,
	input [63:0] rs1_data,
	input op_a_sel,
	output [63:0] operand_a
);
    timeunit 1ns; timeprecision 1ps;
	
	assign operand_a = (op_a_sel) ? {51'h0,pc} : rs1_data;

endmodule