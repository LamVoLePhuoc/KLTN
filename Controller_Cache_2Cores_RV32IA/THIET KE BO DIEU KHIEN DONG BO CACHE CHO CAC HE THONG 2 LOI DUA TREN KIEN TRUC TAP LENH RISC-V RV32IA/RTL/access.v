`timescale 1ns/1ps
// from Lee Min Hunz with luv
// ============================================================================
// Address Decoder - Cache Address Field Extraction
// ============================================================================
//
// Extracts tag, index, word offset, and byte offset from addresses.
// Used by both CPU requests and snoop requests.
//
// Address Format (32-bit, 64B cache line, 16 sets):
//
// Fields:
//   TAG      : Identifies unique cache line (address bits [31:10])
//   INDEX    : Selects cache set (address bits [9:6])
//   WORD_OFF : Selects word within cache line (address bits [5:2])
//   BYTE_OFF : Selects byte within word (address bits [1:0])
//
// Note: Field widths depend on cache configuration parameters.
//
// ============================================================================
module access #(
    parameter ADDR_W        = 32,
    parameter DATA_W        = 32,
    parameter NUM_SETS      = 16,
    parameter INDEX_W       = $clog2(NUM_SETS),
    parameter WORD_OFF_W    = 4,  // 16 words/line
    parameter BYTE_OFF_W    = 2,  // 4B/word
    parameter TAG_W         = ADDR_W - INDEX_W - WORD_OFF_W - BYTE_OFF_W
)(
    input   [ADDR_W-1:0]        cpu_addr
// ,   input   [ADDR_W-1:0]        ac_addr

,   output  [TAG_W-1:0]         cpu_tag
,   output  [INDEX_W-1:0]       cpu_index
,   output  [WORD_OFF_W-1:0]    cpu_word_off
,   output  [BYTE_OFF_W-1:0]    cpu_byte_off

// ,   output  [TAG_W-1:0]         ac_tag
// ,   output  [INDEX_W-1:0]       ac_index
);
    // ================================================================
    // LOCAL PARAMETERS - Address Field Boundaries
    // ================================================================
    localparam BO       = BYTE_OFF_W;           // Byte offset width
    localparam WO       = WORD_OFF_W;           // Word offset width
    localparam IX       = INDEX_W;              // Index width
    localparam TAG_LSB  = BO + WO + IX;         // Tag starts after index
    localparam TAG_MSB  = ADDR_W-1;             // Tag ends at MSB
    localparam IDX_MSB  = TAG_LSB-1;            // Index MSB
    localparam IDX_LSB  = BO + WO;              // Index LSB
    localparam WO_MSB   = IDX_LSB-1;            // Word offset MSB

    // ================================================================
    // CPU ADDRESS DECODE
    // ================================================================
    assign cpu_tag                  = cpu_addr  [TAG_MSB:TAG_LSB];
    assign cpu_index                = cpu_addr  [IDX_MSB:IDX_LSB];
    assign cpu_word_off             = cpu_addr  [WO_MSB:BO];
    assign cpu_byte_off             = cpu_addr  [BO-1:0]; 

    // ================================================================
    // SNOOP ADDRESS DECODE
    // ================================================================
    // assign ac_tag                   = ac_addr   [TAG_MSB:TAG_LSB];
    // assign ac_index                 = ac_addr   [IDX_MSB:IDX_LSB];
endmodule