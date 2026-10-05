module divider_64bit(
    input  logic [63:0] op_a, op_b,
    input  logic [1:0]  mode,
    output logic [63:0] res
);
    
    timeunit 1ns; timeprecision 1ps;

    localparam DIV      = 2'b00;
    localparam DIVU     = 2'b01;
    localparam REM      = 2'b10;
    localparam REMU     = 2'b11;

    logic [63:0] v_out1, v_out2, temp_res1, temp_res2, t64bit_out1, t64bit_out2;
    logic ctr_a, ctr_b, ctr_res;

    twos_comp_64bit t1(op_a, t64bit_out1, ctr_a);
    twos_comp_64bit t2(op_b, t64bit_out2, ctr_b);
    twos_comp_64bit t3(v_out1, temp_res1, ctr_res);
    twos_comp_64bit t4(v_out2, temp_res2, ctr_res);

    assign v_out1 = $unsigned(t64bit_out1) / $unsigned(t64bit_out2);
    assign v_out2 = $unsigned(t64bit_out1) % $unsigned(t64bit_out2);

    always_comb begin
        case (mode)
            DIV: begin
                ctr_a   = 1'b0;
                ctr_b   = 1'b0;
                ctr_res = 1'b0;

                if (~(|op_b)) begin    // Dividend = x, Divisor = 0
                    res = 64'hFFFF_FFFF_FFFF_FFFF;
                end
                else if ((op_a[63]) & (~(|op_a[62:0])) & (&op_b)) begin    // Dividend = most negative num, Divisor = -1
                    res = op_a;
                end
                else begin
                    ctr_a   = op_a[63];
                    ctr_b   = op_b[63];
                    ctr_res = op_a[63] ^ op_b[63];
                    res     = temp_res1;
                end
            end 
            DIVU: begin
                ctr_a   = 1'b0;
                ctr_b   = 1'b0;
                ctr_res = 1'b0;

                if (~(|op_b)) begin    // Dividend = x, Divisor = 0
                    res = 64'hFFFF_FFFF_FFFF_FFFF;
                end
                else begin
                    res = temp_res1;
                end
            end
            REM: begin
                ctr_a   = 1'b0;
                ctr_b   = 1'b0;
                ctr_res = 1'b0;
                
                if (~(|op_b)) begin    // Dividend = x, Divisor = 0
                    res = op_a;
                end
                else if ((op_a[63]) & (~(|op_a[62:0])) & (&op_b)) begin    // Dividend = most negative num, Divisor = -1
                    res = 64'd0;
                end
                else begin
                    ctr_a   = op_a[63];
                    ctr_b   = op_b[63];
                    ctr_res = op_a[63] ^ op_b[63];
                    res = temp_res2;
                end
            end
            REMU: begin
                ctr_a   = 1'b0;
                ctr_b   = 1'b0;
                ctr_res = 1'b0;

                if (~(|op_b)) begin    // Dividend = x, Divisor = 0
                    res = op_a;
                end
                else begin
                    res = temp_res2;
                end
            end
            default: begin
                res = 64'd0;
            end 
        endcase
    end
endmodule