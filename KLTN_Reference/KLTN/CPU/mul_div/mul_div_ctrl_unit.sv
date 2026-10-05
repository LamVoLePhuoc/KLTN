module mul_div_ctrl_unit (
    input  logic [1:0]  opcode,
    input  logic [1:0]  mode,
    input  logic        W_suffix,
    input  logic [63:0] inp_a, inp_b,

    output logic        res_sel,
    output logic [63:0] op_a, op_b
);
    
    timeunit 1ns; timeprecision 1ps;

    localparam MUL = 2'b01;
    localparam DIV = 2'b10;

    localparam mode_DIV      = 2'b00;
    localparam mode_DIVU     = 2'b01;
    localparam mode_REM      = 2'b10;
    localparam mode_REMU     = 2'b11;

    always_comb begin: result_mux_selection
        case (opcode)
            MUL: begin
                res_sel = 1'b0;
            end 
            DIV: begin
                res_sel = 1'b1;
            end
            default: begin
                res_sel = 1'bx;
            end
        endcase
    end

    always_comb begin: W_command_process
        if (W_suffix) begin
            case (opcode)
                MUL: begin
                    op_a = {{32{inp_a[31]}}, inp_a[31:0]};
                    op_b = {{32{inp_b[31]}}, inp_b[31:0]};
                end 
                DIV: begin
                    case (mode)
                        mode_DIV, mode_REM: begin
                            op_a = {{32{inp_a[31]}}, inp_a[31:0]};
                            op_b = {{32{inp_b[31]}}, inp_b[31:0]};
                        end
                        mode_DIVU, mode_REMU: begin
                            op_a = {{32{1'b0}}, inp_a[31:0]};
                            op_b = {{32{1'b0}}, inp_b[31:0]};
                        end
                        default: begin
                            op_a = inp_a;
                            op_b = inp_b;
                        end 
                    endcase
                end
                default: begin
                    op_a = inp_a;
                    op_b = inp_b;
                end
            endcase
        end
        else begin
            op_a = inp_a;
            op_b = inp_b;
        end
    end
    
endmodule