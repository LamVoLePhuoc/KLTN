module multiplier(
    input  logic [63:0] op_a, op_b,
    input  logic [1:0]  mode,
    output logic [63:0] res
);

    timeunit 1ns; timeprecision 1ps;

    localparam MUL      = 2'b00;
    localparam MULH     = 2'b01;
    localparam MULHSU   = 2'b10;
    localparam MULHU    = 2'b11;

    // declaring intermediate wires
    logic [63:0] t64bit_out1, t64bit_out2;
    logic [127:0] v1_out, temp_res;
    logic ctr_tc128, ctr_a, ctr_b;

    // instantiating the 2's complement module (input)
    twos_comp_64bit t1(op_a, t64bit_out1, ctr_a);
    twos_comp_64bit t2(op_b, t64bit_out2, ctr_b);

    // instantiating unsigned multiplier
    assign v1_out = $unsigned(t64bit_out1) * $unsigned(t64bit_out2);

    // instantiating the 2's complement module (output)
    twos_comp_128bit t3(v1_out, temp_res, ctr_tc128);

    // selecting mode
    always_comb begin
        case (mode)
            MUL: begin
                ctr_a = op_a[63];
                ctr_b = op_b[63];
                ctr_tc128 = op_a[63] ^ op_b[63];
                res = temp_res[63:0];
            end 
            MULH: begin
                ctr_a = op_a[63];
                ctr_b = op_b[63];
                ctr_tc128 = op_a[63] ^ op_b[63];
                res = temp_res[127:64];
            end
            MULHSU: begin
                ctr_a = op_a[63];
                ctr_b = 1'b0;
                ctr_tc128 = op_a[63];
                res = temp_res[127:64];
            end
            MULHU: begin
                ctr_a = 1'b0;
                ctr_b = 1'b0;
                ctr_tc128 = 1'b0;
                res = temp_res[127:64];
            end
            default: begin
                ctr_a = op_a[63];
                ctr_b = op_b[63];
                ctr_tc128 = op_a[63] ^ op_b[63];
                res = temp_res[63:0];
            end
        endcase
    end

endmodule