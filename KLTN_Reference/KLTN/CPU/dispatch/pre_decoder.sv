module pre_decoder (
    input  logic [31:0] instr_f,

    // Control signals
    output logic        CPU_reserv_busy,
    output logic        FPU_reserv_busy,

    // Common bus
    output logic [31:0] instr_o,
    output logic [4:0]  rd_addr_o,
    output logic        rd_long_cmd_o,
    output logic        rd_exist_CPU_o,
    output logic        rd_exist_FPU_o,
    output logic [4:0]  rs1_addr_o,
    output logic        rs1_exist_CPU_o,
    output logic        rs1_exist_FPU_o,
    output logic [4:0]  rs2_addr_o,
    output logic        rs2_exist_o,
    output logic [4:0]  rs3_addr_o,
    output logic        rs3_exist_o,
    output logic        CPU2FPU_o,
    output logic        FPU2CPU_o
);
    timeunit 1ns; timeprecision 1ps;
    
    // Extract opcode field (RISC-V opcode = bits [6:0])
    logic [6:0] opcode;
    wire rd_exist_CPU, rd_exist_FPU;
    wire rs1_exist_CPU, rs1_exist_FPU;

    assign opcode = instr_f[6:0];

    assign CPU_reserv_busy = 
            (opcode == 7'b0110011) | // R-type integer (ADD, SUB, etc.)
            (opcode == 7'b0010011) | // I-type integer (ADDI, ANDI, etc.)
            (opcode == 7'b0000011) | // Load integer
            (opcode == 7'b0100011) | // Store integer
            (opcode == 7'b1100011) | // Branch
            (opcode == 7'b1101111) | // JAL
            (opcode == 7'b1100111) | // JALR
            (opcode == 7'b0110111) | // LUI
            (opcode == 7'b0010111) | // AUIPC
            (opcode == 7'b0011011) | // RV64 *W I-type command
            (opcode == 7'b0111011) | // RV64 *W R-type command
            (opcode == 7'b1110011) | // CSR commands
            (opcode == 7'b0001111) | // FENCE commands
            (opcode == 7'b1111111);  // NOP command

    assign FPU_reserv_busy =
            (opcode == 7'b1010011) | // FPU compute (ADD.S, MUL.S, etc.)
            (opcode == 7'b0000111) | // Load floating-point (FLW, FLD)
            (opcode == 7'b0100111) | // Store floating-point (FSW, FSD)
            (opcode == 7'b1000011) | // FMADD.S
            (opcode == 7'b1000111) | // FMSUB.S
            (opcode == 7'b1001011) | // FNMSUB.S
            (opcode == 7'b1001111);  // FNMADD.S

    // Instruction field
    assign instr_o = instr_f;

    // Destination field
    assign rd_exist_CPU = (opcode == 7'b0110111) |
                          (opcode == 7'b0110111) |
                          (opcode == 7'b1101111) |
                          (opcode == 7'b1100111) |
                          (opcode == 7'b0000011) |
                          (opcode == 7'b0010011) |
                          (opcode == 7'b0110011) |
                          (opcode == 7'b0011011) |
                          (opcode == 7'b0111011) |
                          ((opcode == 7'b1010011) & ({instr_f[31], instr_f[28]} == 2'b10));
    assign rd_exist_CPU_o = rd_exist_CPU;
    assign rd_exist_FPU = (opcode == 7'b0000111) |
                          (opcode == 7'b1000011) |
                          (opcode == 7'b1000111) |
                          (opcode == 7'b1001011) |
                          (opcode == 7'b1001111) |
                          ((opcode == 7'b1010011) & (~({instr_f[31], instr_f[28]} == 2'b10)));
    assign rd_exist_FPU_o = rd_exist_FPU;
    assign rd_addr_o = instr_f[11:7];
    assign rd_long_cmd_o = (opcode == 7'b1000011) |
                           (opcode == 7'b1000111) |
                           (opcode == 7'b1001011) |
                           (opcode == 7'b1001111) |
                           ((opcode == 7'b1010011) & ~instr_f[31] & ~instr_f[29] & instr_f[25] & (instr_f != 7'b0100001));

    // Register 1 field
    assign rs1_exist_CPU = (opcode == 7'b1100111) |
                           (opcode == 7'b1100011) |
                           (opcode == 7'b0000011) |
                           (opcode == 7'b0100011) |
                           (opcode == 7'b0010011) |
                           (opcode == 7'b0110011) |
                           (opcode == 7'b0011011) |
                           (opcode == 7'b0111011) |
                           (opcode == 7'b0000111) |
                           (opcode == 7'b0100111) |
                           ((opcode == 7'b1010011) & ({instr_f[31], instr_f[28]} == 2'b11));
    assign rs1_exist_CPU_o = rs1_exist_CPU;
    assign rs1_exist_FPU = (opcode == 7'b1000011) |
                           (opcode == 7'b1000111) |
                           (opcode == 7'b1001011) |
                           (opcode == 7'b1001111) |
                           ((opcode == 7'b1010011) & (~({instr_f[31], instr_f[28]} == 2'b11)));
    assign rs1_exist_FPU_o = rs1_exist_FPU;
    assign rs1_addr_o = instr_f[19:15];

    // Register 2 field
    assign rs2_exist_o = (opcode == 7'b1100011) |
                         (opcode == 7'b0100011) |
                         (opcode == 7'b0110011) |
                         (opcode == 7'b0111011) |
                         (opcode == 7'b0100111) |
                         (opcode == 7'b1000011) |
                         (opcode == 7'b1000111) |
                         (opcode == 7'b1001011) |
                         (opcode == 7'b1001111) |
                         ((opcode == 7'b1010011) & (~instr_f[30]));
    assign rs2_addr_o = instr_f[24:20];

    // Register 3 field
    assign rs3_exist_o = (opcode == 7'b1000011) |
                         (opcode == 7'b1000111) |
                         (opcode == 7'b1001011) |
                         (opcode == 7'b1001111);
    assign rs3_addr_o = instr_f[31:27];

    // Communication signal
    assign CPU2FPU_o = rd_exist_CPU & rs1_exist_FPU;
    assign FPU2CPU_o = rd_exist_FPU & rs1_exist_CPU;
                         
endmodule: pre_decoder