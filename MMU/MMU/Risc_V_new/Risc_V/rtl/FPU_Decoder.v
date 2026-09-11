`timescale 1ns / 1ps

module FPU_Decoder (
    input  wire [6:0] funct7,
    input  wire [2:0] funct3,
    input  wire [6:0] opcode,
    input  wire [4:0] rs2,
    output reg  [4:0] FPUControl
);

    // ============================================================
    // FPU CONTROL ENCODING
    // ============================================================
    localparam [4:0]
        FADD_S      = 5'b00000,
        FSUB_S      = 5'b00001,
        FMUL_S      = 5'b00010,
        FDIV_S      = 5'b00011,
        FSQRT_S     = 5'b00100,

        FSGNJ_S     = 5'b00101,
        FSGNJN_S    = 5'b00110,
        FSGNJX_S    = 5'b00111,

        FEQ_S       = 5'b01000,
        FLT_S       = 5'b01001,
        FLE_S       = 5'b01010,

        FMIN_S      = 5'b01011,
        FMAX_S      = 5'b01100,

        FCVT_W_S    = 5'b01101,
        FCVT_WU_S   = 5'b01110,
        FCVT_S_W    = 5'b01111,
        FCVT_S_WU   = 5'b10000,

        FMV_X_W     = 5'b10001,
        FMV_W_X     = 5'b10010,
        FCLASS_S    = 5'b10011,

        FMADD_S     = 5'b10100,
        FMSUB_S     = 5'b10101,
        FNMSUB_S    = 5'b10110,
        FNMADD_S    = 5'b10111,

        INVALID_FPU = 5'b11111;

    // ============================================================
    // OPCODES
    // ============================================================
    localparam [6:0]
        OP_FP      = 7'b1010011,
        OP_FMADD   = 7'b1000011,
        OP_FMSUB   = 7'b1000111,
        OP_FNMSUB  = 7'b1001011,
        OP_FNMADD  = 7'b1001111;

    // ============================================================
    // DECODE
    // ============================================================
    always @(*) begin
        FPUControl = INVALID_FPU;

        case (opcode)

            // ----------------------------------------------------
            // Fused multiply-add instructions
            // funct2/rm nằm trong các field khác, nhưng với datapath
            // hiện tại ta decode theo opcode là đủ để chọn operation.
            // ----------------------------------------------------
            OP_FMADD: begin
                FPUControl = FMADD_S;
            end

            OP_FMSUB: begin
                FPUControl = FMSUB_S;
            end

            OP_FNMSUB: begin
                FPUControl = FNMSUB_S;
            end

            OP_FNMADD: begin
                FPUControl = FNMADD_S;
            end

            // ----------------------------------------------------
            // Standard OP-FP instructions
            // ----------------------------------------------------
            OP_FP: begin
                case (funct7)

                    // FADD.S
                    7'b0000000: begin
                        FPUControl = FADD_S;
                    end

                    // FSUB.S
                    7'b0000100: begin
                        FPUControl = FSUB_S;
                    end

                    // FMUL.S
                    7'b0001000: begin
                        FPUControl = FMUL_S;
                    end

                    // FDIV.S
                    7'b0001100: begin
                        FPUControl = FDIV_S;
                    end

                    // FSQRT.S, rs2 must be 00000
                    7'b0101100: begin
                        if (rs2 == 5'b00000)
                            FPUControl = FSQRT_S;
                        else
                            FPUControl = INVALID_FPU;
                    end

                    // FSGNJ.S / FSGNJN.S / FSGNJX.S
                    7'b0010000: begin
                        case (funct3)
                            3'b000: FPUControl = FSGNJ_S;
                            3'b001: FPUControl = FSGNJN_S;
                            3'b010: FPUControl = FSGNJX_S;
                            default: FPUControl = INVALID_FPU;
                        endcase
                    end

                    // FMIN.S / FMAX.S
                    7'b0010100: begin
                        case (funct3)
                            3'b000: FPUControl = FMIN_S;
                            3'b001: FPUControl = FMAX_S;
                            default: FPUControl = INVALID_FPU;
                        endcase
                    end

                    // FEQ.S / FLT.S / FLE.S
                    7'b1010000: begin
                        case (funct3)
                            3'b010: FPUControl = FEQ_S;
                            3'b001: FPUControl = FLT_S;
                            3'b000: FPUControl = FLE_S;
                            default: FPUControl = INVALID_FPU;
                        endcase
                    end

                    // FCVT.W.S / FCVT.WU.S
                    // rs2 = 00000 -> signed int
                    // rs2 = 00001 -> unsigned int
                    7'b1100000: begin
                        case (rs2)
                            5'b00000: FPUControl = FCVT_W_S;
                            5'b00001: FPUControl = FCVT_WU_S;
                            default:  FPUControl = INVALID_FPU;
                        endcase
                    end

                    // FCVT.S.W / FCVT.S.WU
                    // rs2 = 00000 -> signed int
                    // rs2 = 00001 -> unsigned int
                    7'b1101000: begin
                        case (rs2)
                            5'b00000: FPUControl = FCVT_S_W;
                            5'b00001: FPUControl = FCVT_S_WU;
                            default:  FPUControl = INVALID_FPU;
                        endcase
                    end

                    // FMV.X.W / FCLASS.S
                    // both require rs2 = 00000
                    7'b1110000: begin
                        if (rs2 == 5'b00000) begin
                            case (funct3)
                                3'b000: FPUControl = FMV_X_W;
                                3'b001: FPUControl = FCLASS_S;
                                default: FPUControl = INVALID_FPU;
                            endcase
                        end
                        else begin
                            FPUControl = INVALID_FPU;
                        end
                    end

                    // FMV.W.X
                    // requires funct3 = 000 and rs2 = 00000
                    7'b1111000: begin
                        if ((funct3 == 3'b000) && (rs2 == 5'b00000))
                            FPUControl = FMV_W_X;
                        else
                            FPUControl = INVALID_FPU;
                    end

                    default: begin
                        FPUControl = INVALID_FPU;
                    end

                endcase
            end

            default: begin
                FPUControl = INVALID_FPU;
            end

        endcase
    end

endmodule