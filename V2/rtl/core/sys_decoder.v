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
    output wire IsIllegalOpD      // OpD doesn't match any opcode Main_Decoder.v knows at all
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

    // Mirrors the opcode set Main_Decoder.v's case statement recognizes
    // (see that file) -- kept here, not there, so Main_Decoder.v's own
    // datapath-control case statement doesn't need touching just to
    // add an "else illegal" arm.
    assign IsIllegalOpD = ~(OpD == OP_LOAD || OpD == OP_MISC_MEM || OpD == OP_OP_IMM ||
                             OpD == OP_AUIPC || OpD == OP_STORE || OpD == OP_AMO ||
                             OpD == OP_OP || OpD == OP_LUI || OpD == OP_BRANCH ||
                             OpD == OP_JALR || OpD == OP_JAL || OpD == OP_SYSTEM);

    wire [2:0]  funct3   = InstrD[14:12];
    wire [11:0] funct12  = InstrD[31:20];
    wire [6:0]  funct7   = InstrD[31:25];
    wire [4:0]  rs2      = InstrD[24:20];

    assign IsSystemD = (OpD == OP_SYSTEM);
    assign IsCsrD    = IsSystemD & (funct3 != 3'b000);
    assign IsPrivD   = IsSystemD & (funct3 == 3'b000);

    assign IsEcallD      = IsPrivD & (funct12 == 12'h000);
    assign IsEbreakD     = IsPrivD & (funct12 == 12'h001);
    assign IsSretD       = IsPrivD & (funct7 == 7'b0001000) & (rs2 == 5'b00010);
    assign IsMretD       = IsPrivD & (funct7 == 7'b0011000) & (rs2 == 5'b00010);
    assign IsWfiD        = IsPrivD & (funct7 == 7'b0001000) & (rs2 == 5'b00101);
    assign IsSfenceVmaD  = IsPrivD & (funct7 == 7'b0001001);

    assign IsPrivIllegalD = IsPrivD & ~(IsEcallD | IsEbreakD | IsSretD | IsMretD | IsWfiD | IsSfenceVmaD);

endmodule
