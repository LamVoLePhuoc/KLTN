module fp_control_unit(
    input  logic [6:0]  opcode,
    input  logic [4:0]  funct,
    input  logic [4:0]  fcvt_op,
    input  logic [2:0]  rm,
    output logic [19:0] fp_opcode,
    output logic        en,
    output logic        reg_write,
    output logic        fmt_sel,
    output logic        rm_sel,
    output logic        ld_sel,
    output logic        wb_sel,
    output logic        wren,
    output logic [4:0]  shift_reg_addr,
    output logic        bridge_wren,
    output logic        bridge_rden
);
    timeunit 1ns; timeprecision 1ps;
    
    // ============= OPCODE field =============
    localparam FLD      = 7'b0000111;
    localparam FSD      = 7'b0100111;
    localparam FMADD_D  = 7'b1000011;
    localparam FMSUB_D  = 7'b1000111;
    localparam FNMSUB_D = 7'b1001011;
    localparam FNMADD_D = 7'b1001111;
    localparam R_type   = 7'b1010011;
    // ========================================

    // ============= FUNCT5 field =============
    localparam FADD_D    = 5'b00000;
    localparam FSUB_D    = 5'b00001;
    localparam FMUL_D    = 5'b00010;
    localparam FDIV_D    = 5'b00011;
    localparam FSQRT_D   = 5'b01011;
    localparam FSGNJ_D   = 5'b00100;
    localparam FMINMAX_D = 5'b00101;
    localparam FCMP_D    = 5'b10100;
    localparam FCLASS_D  = 3'b001;
    localparam FCVT_f2f  = 5'b01000;
    localparam FCVT_f2i  = 5'b11000;
    localparam FCVT_i2f  = 5'b11010;
    localparam FMV_X_D   = 3'b000;
    localparam FMV_D_X   = 5'b11110;
    // ========================================

    always_comb begin
        case (opcode)
            FLD: begin
                fp_opcode = 20'd0;
                en = 1'b1;
                reg_write = 1'b1;
                fmt_sel = 1'b0;
                rm_sel = 1'b1;
                ld_sel = 1'b1;
                wb_sel = 1'b1;
                wren = 1'b0;
                shift_reg_addr = 5'd0;
                bridge_wren = 1'b0;
                bridge_rden = 1'b1;
            end 

            FSD: begin
                fp_opcode = 20'd0;
                en = 1'b1;
                reg_write = 1'b0;
                fmt_sel = 1'b0;
                rm_sel = 1'b1;
                ld_sel = 1'b0;
                wb_sel = 1'b0;
                wren = 1'b1;
                shift_reg_addr = 5'd0;
                bridge_wren = 1'b0;
                bridge_rden = 1'b1;
            end

            FMADD_D: begin
                fp_opcode = 20'b1000_0000_0000_0000_0000;
                en = 1'b1;
                reg_write = 1'b1;
                fmt_sel = 1'b1;
                ld_sel = 1'b0;
                wb_sel = 1'b0;
                wren = 1'b0;
                shift_reg_addr = 5'd2;
                bridge_wren = 1'b0;
                bridge_rden = 1'b0;

                if (rm == 3'b111) begin
                    rm_sel = 1'b1;
                end
                else begin
                    rm_sel = 1'b0;
                end
            end

            FMSUB_D: begin
                fp_opcode = 20'b0100_0000_0000_0000_0000;
                en = 1'b1;
                reg_write = 1'b1;
                fmt_sel = 1'b1;
                ld_sel = 1'b0;
                wb_sel = 1'b0;
                wren = 1'b0;
                shift_reg_addr = 5'd2;
                bridge_wren = 1'b0;
                bridge_rden = 1'b0;

                if (rm == 3'b111) begin
                    rm_sel = 1'b1;
                end
                else begin
                    rm_sel = 1'b0;
                end
            end

            FNMSUB_D: begin
                fp_opcode = 20'b0001_0000_0000_0000_0000;
                en = 1'b1;
                reg_write = 1'b1;
                fmt_sel = 1'b1;
                ld_sel = 1'b0;
                wb_sel = 1'b0;
                wren = 1'b0;
                shift_reg_addr = 5'd2;
                bridge_wren = 1'b0;
                bridge_rden = 1'b0;

                if (rm == 3'b111) begin
                    rm_sel = 1'b1;
                end
                else begin
                    rm_sel = 1'b0;
                end
            end

            FNMADD_D: begin
                fp_opcode = 20'b0010_0000_0000_0000_0000;
                en = 1'b1;
                reg_write = 1'b1;
                fmt_sel = 1'b1;
                ld_sel = 1'b0;
                wb_sel = 1'b0;
                wren = 1'b0;
                shift_reg_addr = 5'd2;
                bridge_wren = 1'b0;
                bridge_rden = 1'b0;

                if (rm == 3'b111) begin
                    rm_sel = 1'b1;
                end
                else begin
                    rm_sel = 1'b0;
                end
            end

            R_type: begin
                case (funct)
                    FADD_D: begin
                        fp_opcode = 20'b0000_1000_0000_0000_0000;
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd2;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b0;

                        if (rm == 3'b111) begin
                            rm_sel = 1'b1;
                        end
                        else begin
                            rm_sel = 1'b0;
                        end
                    end 

                    FSUB_D: begin
                        fp_opcode = 20'b0000_0100_0000_0000_0000;
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd2;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b0;

                        if (rm == 3'b111) begin
                            rm_sel = 1'b1;
                        end
                        else begin
                            rm_sel = 1'b0;
                        end
                    end

                    FMUL_D: begin
                        fp_opcode = 20'b0000_0010_0000_0000_0000;
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd2;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b0;

                        if (rm == 3'b111) begin
                            rm_sel = 1'b1;
                        end
                        else begin
                            rm_sel = 1'b0;
                        end
                    end

                    FDIV_D: begin
                        fp_opcode = 20'b0000_0001_0000_0000_0000;
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd13;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b0;

                        if (rm == 3'b111) begin
                            rm_sel = 1'b1;
                        end
                        else begin
                            rm_sel = 1'b0;
                        end
                    end

                    FSQRT_D: begin
                        fp_opcode = 20'b0000_0000_1000_0000_0000;
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd16;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b0;

                        if (rm == 3'b111) begin
                            rm_sel = 1'b1;
                        end
                        else begin
                            rm_sel = 1'b0;
                        end
                    end

                    FSGNJ_D: begin
                        fp_opcode = 20'b0000_0000_0100_0000_0000;
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        rm_sel = 1'b0;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd0;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b0;
                    end

                    FMINMAX_D: begin
                        fp_opcode = 20'b0000_0000_0001_0000_0000;
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        rm_sel = 1'b0;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd0;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b0;
                    end

                    FCVT_f2f: begin
                        fp_opcode = {18'b00_0000_0000_0000_0100, fcvt_op[1:0]};
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd0;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b0;

                        if (rm == 3'b111) begin
                            rm_sel = 1'b1;
                        end
                        else begin
                            rm_sel = 1'b0;
                        end
                    end

                    FCMP_D: begin
                        fp_opcode = 20'b0000_0000_0010_0000_0000;
                        en = 1'b1;
                        reg_write = 1'b0;
                        fmt_sel = 1'b1;
                        rm_sel = 1'b0;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd0;
                        bridge_wren = 1'b1;
                        bridge_rden = 1'b0;
                    end

                    5'b11100: begin
                        if (rm == FCLASS_D) begin
                            fp_opcode = 20'b0000_0000_0000_1000_0000;
                            en = 1'b1;
                            reg_write = 1'b0;
                            fmt_sel = 1'b1;
                            rm_sel = 1'b0;
                            ld_sel = 1'b0;
                            wb_sel = 1'b0;
                            wren = 1'b0;
                            shift_reg_addr = 5'd0;
                            bridge_wren = 1'b1;
                            bridge_rden = 1'b0;
                        end
                        else if (rm == FMV_X_D) begin
                            fp_opcode = 20'b0000_0000_0000_0010_0000;
                            en = 1'b1;
                            reg_write = 1'b0;
                            fmt_sel = 1'b1;
                            rm_sel = 1'b0;
                            ld_sel = 1'b0;
                            wb_sel = 1'b0;
                            wren = 1'b0;
                            shift_reg_addr = 5'd0;
                            bridge_wren = 1'b1;
                            bridge_rden = 1'b0;
                        end
                        else begin
                            fp_opcode = 20'b0000_0000_0000_0000_0000;
                            en = 1'b0;
                            reg_write = 1'b0;
                            fmt_sel = 1'b0;
                            rm_sel = 1'b0;
                            ld_sel = 1'b0;
                            wb_sel = 1'b0;
                            wren = 1'b0;
                            shift_reg_addr = 5'd0;
                            bridge_wren = 1'b0;
                            bridge_rden = 1'b0;
                        end
                    end

                    FCVT_f2i: begin
                        fp_opcode = {18'b00_0000_0000_0000_0001, fcvt_op[1:0]};
                        en = 1'b1;
                        reg_write = 1'b0;
                        fmt_sel = 1'b1;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd0;
                        bridge_wren = 1'b1;
                        bridge_rden = 1'b0;

                        if (rm == 3'b111) begin
                            rm_sel = 1'b1;
                        end
                        else begin
                            rm_sel = 1'b0;
                        end
                    end

                    FCVT_i2f: begin
                        fp_opcode = {18'b00_0000_0000_0000_0010, fcvt_op[1:0]};
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd0;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b1;

                        if (rm == 3'b111) begin
                            rm_sel = 1'b1;
                        end
                        else begin
                            rm_sel = 1'b0;
                        end
                    end

                    FMV_D_X: begin
                        fp_opcode = 20'b0000_0000_0000_0100_0000;
                        en = 1'b1;
                        reg_write = 1'b1;
                        fmt_sel = 1'b1;
                        rm_sel = 1'b0;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd0;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b1;
                    end

                    default: begin
                        fp_opcode = 20'b0;
                        en = 1'b0;
                        reg_write = 1'b0;
                        fmt_sel = 1'b0;
                        rm_sel = 1'b0;
                        ld_sel = 1'b0;
                        wb_sel = 1'b0;
                        wren = 1'b0;
                        shift_reg_addr = 5'd0;
                        bridge_wren = 1'b0;
                        bridge_rden = 1'b0;
                    end 
                endcase
            end

            default: begin
                fp_opcode = 20'b0;
                en = 1'b0;
                reg_write = 1'b0;
                fmt_sel = 1'b0;
                rm_sel = 1'b0;
                ld_sel = 1'b0;
                wb_sel = 1'b0;
                wren = 1'b0;
                shift_reg_addr = 5'd0;
                bridge_wren = 1'b0;
                bridge_rden = 1'b0;
            end 
        endcase
    end

endmodule: fp_control_unit