module mul_div_top (
    input  logic [1:0]  opcode,
    input  logic [1:0]  mode,
    input  logic        W_suffix,
    input  logic [63:0] inp_a, inp_b,

    output logic [63:0] res
);
    
    timeunit 1ns; timeprecision 1ps;

    logic [63:0] op_a, op_b;
    logic [63:0] mul_res, div_res, temp_res;
    logic res_sel;

    mul_div_ctrl_unit mul_div_ctrl_unit(
        .opcode(opcode),
        .mode(mode),
        .W_suffix(W_suffix),
        .inp_a(inp_a),
        .inp_b(inp_b),
        .res_sel(res_sel),
        .op_a(op_a),
        .op_b(op_b)
    );

    multiplier multiplier(
        .op_a(op_a),
        .op_b(op_b),
        .mode(mode),
        .res(mul_res)
    );

    // TODO_need_to_find_other_algorithm divider_64bit divider(
    // TODO_need_to_find_other_algorithm     .op_a(op_a),
    // TODO_need_to_find_other_algorithm     .op_b(op_b),
    // TODO_need_to_find_other_algorithm     .mode(mode),
    // TODO_need_to_find_other_algorithm     .res(div_res)
    // TODO_need_to_find_other_algorithm );

    md_res_mux md_res_mux(
        .res_sel(res_sel),
        .mul_res(mul_res),
        .div_res(div_res),
        .res(temp_res)
    );

    always_comb begin: result_process
        if (W_suffix) begin
            res = {{32{temp_res[31]}}, temp_res[31:0]};
        end
        else begin
            res = temp_res;
        end
    end

endmodule