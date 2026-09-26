`timescale 1ns / 1ps

// ============================================================
// mmu_region_decode
//
// Architectural virtual-address regions agreed for the 32-bit SoC.
// Page-table permissions remain the final authority; these region
// attributes add a coarse, easy-to-debug guard when
// mmu_top.REGION_POLICY_ENABLE is set.
//
//   0x0000_0000..0x000F_FFFF  boot/init (1 MiB, RX)
//   0x0010_0000..0x3FFF_FFFF  system/OS (RWX)
//   0x4000_0000..0x7FFF_FFFF  user text (RX)
//   0x8000_0000..0xBFFF_FFFF  user data/heap/stack (RW)
//   0xC000_0000..0xFFFF_FFFF  MMIO/reserved (RW, never fetch)
//
// Keeping this decoder independent from the PTW makes the boundary
// visible in waveforms and lets software change VA->PA mappings
// without changing the high-level memory contract.
// ============================================================
module mmu_region_decode (
    input  wire [31:0] va,
    output reg  [2:0]  region,
    output reg         allow_fetch,
    output reg         allow_load,
    output reg         allow_store
);

    localparam [2:0]
        REGION_BOOT      = 3'd0,
        REGION_SYSTEM    = 3'd1,
        REGION_USER_TEXT = 3'd2,
        REGION_USER_DATA = 3'd3,
        REGION_MMIO      = 3'd4;

    always @(*) begin
        // Default to the most restrictive class.  Every 32-bit VA is
        // covered by one explicit branch below.
        region      = REGION_MMIO;
        allow_fetch = 1'b0;
        allow_load  = 1'b1;
        allow_store = 1'b1;

        if (va < 32'h0010_0000) begin
            region      = REGION_BOOT;
            allow_fetch = 1'b1;
            allow_load  = 1'b1;
            allow_store = 1'b0;
        end
        else if (va < 32'h4000_0000) begin
            region      = REGION_SYSTEM;
            allow_fetch = 1'b1;
            allow_load  = 1'b1;
            allow_store = 1'b1;
        end
        else if (va < 32'h8000_0000) begin
            region      = REGION_USER_TEXT;
            allow_fetch = 1'b1;
            allow_load  = 1'b1;
            allow_store = 1'b0;
        end
        else if (va < 32'hC000_0000) begin
            region      = REGION_USER_DATA;
            allow_fetch = 1'b0;
            allow_load  = 1'b1;
            allow_store = 1'b1;
        end
    end

endmodule
