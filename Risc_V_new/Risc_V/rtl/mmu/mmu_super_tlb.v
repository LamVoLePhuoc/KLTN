`timescale 1ns / 1ps

// Four-entry fully-associative cache for Sv32 level-1 leaves
// (4 MiB superpages). A match uses VPN[19:10]; the effective PPN
// is {PTE.PPN[19:10], VPN[9:0]}. Keeping these entries separate
// avoids aliasing with mmu_tlb's VPN[1:0]-indexed 4 KiB sets.
module mmu_super_tlb (
    input  wire clk, input wire rst, input wire flush,
    input  wire lookup_valid, input wire [19:0] lookup_vpn,
    output wire hit, output reg [19:0] hit_ppn,
    output reg hit_r, output reg hit_w, output reg hit_x,
    output reg hit_u, output reg hit_g, output reg hit_a, output reg hit_d,
    input  wire refill_valid, input wire [19:0] refill_vpn,
    input  wire [19:0] refill_ppn,
    input  wire refill_r, input wire refill_w, input wire refill_x,
    input  wire refill_u, input wire refill_g, input wire refill_a,
    input  wire refill_d
);
    reg [3:0] valid_r;
    reg [9:0] vpn1_r [0:3];
    reg [9:0] ppn1_r [0:3];
    reg [6:0] flags_r [0:3];
    reg [1:0] rr_victim_r;

    wire hit0 = lookup_valid && valid_r[0] && (vpn1_r[0] == lookup_vpn[19:10]);
    wire hit1 = lookup_valid && valid_r[1] && (vpn1_r[1] == lookup_vpn[19:10]);
    wire hit2 = lookup_valid && valid_r[2] && (vpn1_r[2] == lookup_vpn[19:10]);
    wire hit3 = lookup_valid && valid_r[3] && (vpn1_r[3] == lookup_vpn[19:10]);
    reg [6:0] hit_flags_v;
    reg [9:0] hit_ppn1_v;

    always @(*) begin
        hit_flags_v = 7'b0;
        hit_ppn1_v  = 10'b0;
        if (hit0) begin hit_flags_v = flags_r[0]; hit_ppn1_v = ppn1_r[0]; end
        else if (hit1) begin hit_flags_v = flags_r[1]; hit_ppn1_v = ppn1_r[1]; end
        else if (hit2) begin hit_flags_v = flags_r[2]; hit_ppn1_v = ppn1_r[2]; end
        else if (hit3) begin hit_flags_v = flags_r[3]; hit_ppn1_v = ppn1_r[3]; end
        hit_ppn = {hit_ppn1_v, lookup_vpn[9:0]};
        hit_r = hit_flags_v[0]; hit_w = hit_flags_v[1]; hit_x = hit_flags_v[2];
        hit_u = hit_flags_v[3]; hit_g = hit_flags_v[4]; hit_a = hit_flags_v[5];
        hit_d = hit_flags_v[6];
    end
    assign hit = hit0 | hit1 | hit2 | hit3;

    wire match0 = valid_r[0] && (vpn1_r[0] == refill_vpn[19:10]);
    wire match1 = valid_r[1] && (vpn1_r[1] == refill_vpn[19:10]);
    wire match2 = valid_r[2] && (vpn1_r[2] == refill_vpn[19:10]);
    wire match3 = valid_r[3] && (vpn1_r[3] == refill_vpn[19:10]);
    reg [1:0] refill_way_v;
    always @(*) begin
        if (match0) refill_way_v = 2'd0;
        else if (match1) refill_way_v = 2'd1;
        else if (match2) refill_way_v = 2'd2;
        else if (match3) refill_way_v = 2'd3;
        else if (!valid_r[0]) refill_way_v = 2'd0;
        else if (!valid_r[1]) refill_way_v = 2'd1;
        else if (!valid_r[2]) refill_way_v = 2'd2;
        else if (!valid_r[3]) refill_way_v = 2'd3;
        else refill_way_v = rr_victim_r;
    end

    always @(posedge clk) begin
        if (rst || flush) begin
            valid_r <= 4'b0;
            rr_victim_r <= 2'b0;
        end
        else if (refill_valid) begin
            valid_r[refill_way_v] <= 1'b1;
            vpn1_r[refill_way_v] <= refill_vpn[19:10];
            ppn1_r[refill_way_v] <= refill_ppn[19:10];
            flags_r[refill_way_v] <= {refill_d, refill_a, refill_g,
                                      refill_u, refill_x, refill_w, refill_r};
            rr_victim_r <= refill_way_v + 2'd1;
        end
    end
endmodule
