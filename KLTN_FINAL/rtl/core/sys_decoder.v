`timescale 1ns / 1ps

// ============================================================
// sys_decoder
//
// Fine-grain decode of the SYSTEM opcode (0x73), funct3=000 sub-
// space: ECALL / EBREAK / MRET / SRET / WFI / SFENCE.VMA. This is
// deliberately SEPARATE from Main_Decoder.v: Main_Decoder only needs
// to know "SYSTEM, funct3==0 -> no register/memory side effect"
// (already correct, unchanged) or "SYSTEM, funct3!=0 -> CSR op,
// writes rd" (new, see Main_Decoder.v's OP_SYSTEM case) -- it does
// NOT need to know WHICH funct3==0 instruction this is. Only
// csr_trap_unit.v cares about that distinction, so it lives here
// instead of growing Main_Decoder.v's own interface.
//
// Encoding reference (funct3=000, distinguished by instr[31:20] as
// a 12-bit immediate/funct12 field, sometimes further split into
// funct7[31:25]+rs2[24:20]):
//   0x000                        ECALL
//   0x001                        EBREAK
//   funct7=0001000, rs2=00010    SRET
//   funct7=0011000, rs2=00010    MRET
//   funct7=0001000, rs2=00101    WFI
//   funct7=0001001, rs2=xxxxx    SFENCE.VMA (rs2 selects an ASID to
//                                flush, ignored here -- Mmu_Flush is
//                                whole-TLB, see csr_trap_unit.v)
//   anything else                reserved -- illegal instruction
// ============================================================
module sys_decoder (
    input  wire [31:0] InstrD,
    input  wire [6:0]  OpD,

    output wire IsSystemD,       // OpD == SYSTEM (0x73), any funct3
    output wire IsCsrD,          // SYSTEM, funct3 != 0 (a real CSRxx instruction)
    output wire IsPrivD,         // SYSTEM, funct3 == 0 (ECALL/EBREAK/xRET/WFI/SFENCE.VMA space)
    output wire IsEcallD,
    output wire IsEbreakD,
    output wire IsMretD,
    output wire IsSretD,
    output wire IsWfiD,
    output wire IsSfenceVmaD,
    output wire IsPrivIllegalD,   // funct3==0 but none of the above matched
    output wire IsIllegalOpD      // unknown opcode or reserved RV32IMA encoding
);

    localparam [6:0] OP_SYSTEM   = 7'b1110011;
    localparam [6:0] OP_LOAD     = 7'b0000011;
    localparam [6:0] OP_MISC_MEM = 7'b0001111;
    localparam [6:0] OP_OP_IMM   = 7'b0010011;
    localparam [6:0] OP_AUIPC    = 7'b0010111;
    localparam [6:0] OP_STORE    = 7'b0100011;
    localparam [6:0] OP_AMO      = 7'b0101111;
    localparam [6:0] OP_OP       = 7'b0110011;
    localparam [6:0] OP_LUI      = 7'b0110111;
    localparam [6:0] OP_BRANCH   = 7'b1100011;
    localparam [6:0] OP_JALR     = 7'b1100111;
    localparam [6:0] OP_JAL      = 7'b1101111;

    wire [2:0]  funct3   = InstrD[14:12];
    wire [11:0] funct12  = InstrD[31:20];
    wire [6:0]  funct7   = InstrD[31:25];
    wire [4:0]  funct5   = InstrD[31:27];
    wire [4:0]  rs2      = InstrD[24:20];
    wire [4:0]  rs1      = InstrD[19:15];
    wire [4:0]  rd       = InstrD[11:7];

    wire load_legal = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                      (funct3 == 3'b010) || (funct3 == 3'b100) ||
                      (funct3 == 3'b101);
    wire store_legal = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                       (funct3 == 3'b010);
    wire branch_legal = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                        (funct3 == 3'b100) || (funct3 == 3'b101) ||
                        (funct3 == 3'b110) || (funct3 == 3'b111);

    // RV32 shift-immediate instructions reserve every upper-immediate value
    // except 0000000 (logical) and, for right shifts, 0100000 (arithmetic).
    wire op_imm_legal =
        (funct3 == 3'b001) ? (funct7 == 7'b0000000) :
        (funct3 == 3'b101) ? ((funct7 == 7'b0000000) ||
                              (funct7 == 7'b0100000)) : 1'b1;

    wire op_legal = (funct7 == 7'b0000000) ||
                    (funct7 == 7'b0000001) ||
                    ((funct7 == 7'b0100000) &&
                     ((funct3 == 3'b000) || (funct3 == 3'b101)));

    wire amo_funct5_legal =
        (funct5 == 5'b00000) || (funct5 == 5'b00001) ||
        (funct5 == 5'b00010) || (funct5 == 5'b00011) ||
        (funct5 == 5'b00100) || (funct5 == 5'b01000) ||
        (funct5 == 5'b01100) || (funct5 == 5'b10000) ||
        (funct5 == 5'b10100) || (funct5 == 5'b11000) ||
        (funct5 == 5'b11100);
    wire amo_legal = (funct3 == 3'b010) && amo_funct5_legal &&
                     ((funct5 != 5'b00010) || (rs2 == 5'd0));

    wire csr_funct3_legal = (funct3 == 3'b001) || (funct3 == 3'b010) ||
                            (funct3 == 3'b011) || (funct3 == 3'b101) ||
                            (funct3 == 3'b110) || (funct3 == 3'b111);

    // The funct3=000 privileged SYSTEM subspace is checked below by
    // IsPrivIllegalD.  Keeping that check separate preserves the precise
    // ECALL/EBREAK/xRET/SFENCE decode while this expression validates all
    // other RV32IMA instruction encodings before they can cause side effects.
    wire encoding_legal =
        ((OpD == OP_LOAD)     && load_legal) ||
        ((OpD == OP_MISC_MEM) && ((funct3 == 3'b000) || (funct3 == 3'b001))) ||
        ((OpD == OP_OP_IMM)   && op_imm_legal) ||
        (OpD == OP_AUIPC) ||
        ((OpD == OP_STORE)    && store_legal) ||
        ((OpD == OP_AMO)      && amo_legal) ||
        ((OpD == OP_OP)       && op_legal) ||
        (OpD == OP_LUI) ||
        ((OpD == OP_BRANCH)   && branch_legal) ||
        ((OpD == OP_JALR)     && (funct3 == 3'b000)) ||
        (OpD == OP_JAL) ||
        ((OpD == OP_SYSTEM)   && ((funct3 == 3'b000) || csr_funct3_legal));

    assign IsIllegalOpD = ~encoding_legal;

    assign IsSystemD = (OpD == OP_SYSTEM);
    assign IsCsrD    = IsSystemD & (funct3 != 3'b000);
    assign IsPrivD   = IsSystemD & (funct3 == 3'b000);

    assign IsEcallD      = IsPrivD & (funct12 == 12'h000) &
                           (rs1 == 5'd0) & (rd == 5'd0);
    assign IsEbreakD     = IsPrivD & (funct12 == 12'h001) &
                           (rs1 == 5'd0) & (rd == 5'd0);
    assign IsSretD       = IsPrivD & (funct7 == 7'b0001000) &
                           (rs2 == 5'b00010) & (rs1 == 5'd0) &
                           (rd == 5'd0);
    assign IsMretD       = IsPrivD & (funct7 == 7'b0011000) &
                           (rs2 == 5'b00010) & (rs1 == 5'd0) &
                           (rd == 5'd0);
    assign IsWfiD        = IsPrivD & (funct7 == 7'b0001000) &
                           (rs2 == 5'b00101) & (rs1 == 5'd0) &
                           (rd == 5'd0);
    assign IsSfenceVmaD  = IsPrivD & (funct7 == 7'b0001001) &
                           (rd == 5'd0);

    assign IsPrivIllegalD = IsPrivD & ~(IsEcallD | IsEbreakD | IsSretD | IsMretD | IsWfiD | IsSfenceVmaD);

endmodule
