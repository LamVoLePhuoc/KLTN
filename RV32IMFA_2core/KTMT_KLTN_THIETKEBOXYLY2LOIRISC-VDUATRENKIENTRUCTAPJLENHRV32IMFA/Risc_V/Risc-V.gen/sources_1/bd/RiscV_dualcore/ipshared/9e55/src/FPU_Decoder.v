module FPU_Decoder (
    input  wire [6:0] funct7,
    input  wire [2:0] funct3,
    input  wire [6:0] opcode,
    output reg  [4:0] FPUControl
);

    // Định nghĩa mã điều khiển 
    localparam [4:0]
        FADD_S    = 5'b00000, FSUB_S    = 5'b00001, FMUL_S    = 5'b00010,
        FDIV_S    = 5'b00011, FSQRT_S   = 5'b00100, FSGNJ_S   = 5'b00101,
        FSGNJN_S  = 5'b00110, FSGNJX_S  = 5'b00111, FMIN_S    = 5'b01011, // MỚI
        FMAX_S    = 5'b01111, // MỚI
        FEQ_S     = 5'b01000, FLT_S     = 5'b01001, FLE_S     = 5'b01010,
        FCVT_W_S  = 5'b01100, FCVT_WU_S = 5'b01101, FCVT_S_W  = 5'b01110,
        FCVT_S_WU = 5'b01111, FMV_X_W   = 5'b10000, FMV_W_X   = 5'b10001,
        FCLASS_S  = 5'b10010;

    always @(*) begin
        FPUControl = FADD_S; // Default
        if (opcode == 7'b1010011) begin
            case (funct7)
                7'b0000000: FPUControl = FADD_S;
                7'b0000100: FPUControl = FSUB_S;
                7'b0001000: FPUControl = FMUL_S;
                7'b0001100: FPUControl = FDIV_S;
                7'b0101100: FPUControl = FSQRT_S;
                
                // Nhóm gán dấu
                7'b0010000: begin
                    case (funct3)
                        3'b000: FPUControl = FSGNJ_S;
                        3'b001: FPUControl = FSGNJN_S;
                        3'b010: FPUControl = FSGNJX_S;
                        default: FPUControl = FADD_S;
                    endcase
                end

                // Nhóm MIN/MAX 
                7'b0010100: begin
                    case (funct3)
                        3'b000: FPUControl = FMIN_S;
                        3'b001: FPUControl = FMAX_S;
                        default: FPUControl = FADD_S;
                    endcase
                end

                // Nhóm so sánh
                7'b1010000: begin
                    case (funct3)
                        3'b010: FPUControl = FEQ_S;
                        3'b001: FPUControl = FLT_S;
                        3'b000: FPUControl = FLE_S;
                        default: FPUControl = FADD_S;
                    endcase
                end

                
                7'b1100000: FPUControl = (funct3[0]) ? FCVT_WU_S : FCVT_W_S;
                7'b1101000: FPUControl = (funct3[0]) ? FCVT_S_WU : FCVT_S_W;
                7'b1110000: FPUControl = (funct3[0]) ? FCLASS_S  : FMV_X_W;
                7'b1111000: FPUControl = FMV_W_X;
                
                default: FPUControl = FADD_S;
            endcase
        end
    end
endmodule