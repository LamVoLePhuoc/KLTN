`timescale 1ns / 1ps

// ============================================================
// mmu_tlb
//
// Fully-associative TLB, per address_mapping:
//   16 entries, VPN(20 bit) -> PPN(20 bit) + flags
//   (valid_r is the entry's own valid bit; R,W,X,U,G,A,D are
//   copied from the PTE that filled the entry)
//
// Lookup is combinational (0-cycle hit latency).
// Refill is synchronous, one entry per cycle; the victim entry
// is chosen round-robin (simplification vs. true LRU).
// ============================================================
module mmu_tlb (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,

    // Lookup (combinational)
    input  wire [19:0] lookup_vpn,
    output wire         hit,
    output wire [19:0]  hit_ppn,
    output wire         hit_r,
    output wire         hit_w,
    output wire         hit_x,
    output wire         hit_u,
    output wire         hit_g,
    output wire         hit_a,
    output wire         hit_d,

    // Refill (synchronous)
    input  wire         refill_valid,
    input  wire [19:0]  refill_vpn,
    input  wire [19:0]  refill_ppn,
    input  wire         refill_r,
    input  wire         refill_w,
    input  wire         refill_x,
    input  wire         refill_u,
    input  wire         refill_g,
    input  wire         refill_a,
    input  wire         refill_d
);

    localparam ENTRIES = 16;

    reg              valid_r [0:ENTRIES-1];
    reg [19:0]       vpn_r   [0:ENTRIES-1];
    reg [19:0]       ppn_r   [0:ENTRIES-1];
    reg [6:0]        flags_r [0:ENTRIES-1]; // {d,a,g,u,x,w,r}

    integer i;

    // ------------------------------------------------------
    // CAM lookup
    // ------------------------------------------------------
    reg        hit_v;
    reg [19:0] hit_ppn_v;
    reg [6:0]  hit_flags_v;

    always @(*) begin
        hit_v       = 1'b0;
        hit_ppn_v   = 20'b0;
        hit_flags_v = 7'b0;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (valid_r[i] && (vpn_r[i] == lookup_vpn)) begin
                hit_v       = 1'b1;
                hit_ppn_v   = ppn_r[i];
                hit_flags_v = flags_r[i];
            end
        end
    end

    assign hit     = hit_v;
    assign hit_ppn = hit_ppn_v;
    assign hit_r   = hit_flags_v[0];
    assign hit_w   = hit_flags_v[1];
    assign hit_x   = hit_flags_v[2];
    assign hit_u   = hit_flags_v[3];
    assign hit_g   = hit_flags_v[4];
    assign hit_a   = hit_flags_v[5];
    assign hit_d   = hit_flags_v[6];

    // ------------------------------------------------------
    // Round-robin victim pointer + storage update
    // ------------------------------------------------------
    reg [3:0] victim_ptr;

    always @(posedge clk) begin
        if (rst) begin
            victim_ptr <= 4'b0;
            for (i = 0; i < ENTRIES; i = i + 1) begin
                valid_r[i] <= 1'b0;
            end
        end
        else if (flush) begin
            for (i = 0; i < ENTRIES; i = i + 1) begin
                valid_r[i] <= 1'b0;
            end
        end
        else if (refill_valid) begin
            valid_r[victim_ptr] <= 1'b1;
            vpn_r[victim_ptr]   <= refill_vpn;
            ppn_r[victim_ptr]   <= refill_ppn;
            flags_r[victim_ptr] <= {refill_d, refill_a, refill_g, refill_u, refill_x, refill_w, refill_r};
            victim_ptr          <= victim_ptr + 4'b1;
        end
    end

endmodule
