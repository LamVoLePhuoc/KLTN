module op_b_mux (
	input [63:0] imm, rs2_data,
	input op_b_sel,
	output [63:0] operand_b
);
    timeunit 1ns; timeprecision 1ps;
	
	assign operand_b = (op_b_sel) ? imm : rs2_data;

endmodule