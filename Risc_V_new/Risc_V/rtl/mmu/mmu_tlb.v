`timescale 1ns / 1ps

// ============================================================
// mmu_tlb
//
// 16-entry, 4-set x 4-way TLB.  The old implementation was a
// 16-entry fully-associative CAM made entirely from registers.  A
// lookup therefore compared all 16 VPNs in parallel and reset the
// complete entry arrays.  This version follows the implementation
// structure intended for the final MMU:
//
//   VPN[19:2] : tag
//   VPN[1:0]  : set index
//   4 ways/set, tree-PLRU replacement within each set
//
// Only the four tags in the indexed set are compared.  Valid bits
// stay in flops because reset/SFENCE.VMA must clear them in one
// cycle.  Each way is a separate memory bank, and each bank further
// separates tag, permission metadata, and PPN data.  Those arrays are
// deliberately not reset; an invalid entry's contents are don't-care.
// On FPGA the asynchronous lookup normally maps these very small
// banks to distributed RAM/LUTRAM.  In an ASIC flow the same banks are
// natural boundaries for small SRAM macros.
//
// Refill policy:
//   1. update an existing matching VPN (prevents duplicates),
//   2. otherwise use the first invalid way,
//   3. otherwise use per-set tree-PLRU.
//
// lookup_valid prevents an idle D-side address from perturbing the
// replacement state.  The I-side drives it whenever translation is
// enabled; the D-side drives it only for a real load/store request.
// ============================================================
module mmu_tlb (
    input  wire        clk,
    input  wire        rst,
    input  wire        flush,

    // Lookup (combinational)
    input  wire        lookup_valid,
    input  wire [19:0] lookup_vpn,
    output wire        hit,
    output wire [19:0] hit_ppn,
    output wire        hit_r,
    output wire        hit_w,
    output wire        hit_x,
    output wire        hit_u,
    output wire        hit_g,
    output wire        hit_a,
    output wire        hit_d,

    // Refill (synchronous)
    input  wire        refill_valid,
    input  wire [19:0] refill_vpn,
    input  wire [19:0] refill_ppn,
    input  wire        refill_r,
    input  wire        refill_w,
    input  wire        refill_x,
    input  wire        refill_u,
    input  wire        refill_g,
    input  wire        refill_a,
    input  wire        refill_d
);

    localparam integer SETS = 4;

    wire [1:0]  lookup_set = lookup_vpn[1:0];
    wire [17:0] lookup_tag = lookup_vpn[19:2];
    wire [1:0]  refill_set = refill_vpn[1:0];
    wire [17:0] refill_tag = refill_vpn[19:2];

    // One resettable 4-bit valid vector per set.  The tag/flags/PPN
    // banks below have no reset so synthesis can infer memories.
    reg [3:0] valid_r [0:SETS-1];

    (* ram_style = "distributed" *) reg [17:0] tag_way0 [0:SETS-1];
    (* ram_style = "distributed" *) reg [17:0] tag_way1 [0:SETS-1];
    (* ram_style = "distributed" *) reg [17:0] tag_way2 [0:SETS-1];
    (* ram_style = "distributed" *) reg [17:0] tag_way3 [0:SETS-1];

    (* ram_style = "distributed" *) reg [6:0] flags_way0 [0:SETS-1];
    (* ram_style = "distributed" *) reg [6:0] flags_way1 [0:SETS-1];
    (* ram_style = "distributed" *) reg [6:0] flags_way2 [0:SETS-1];
    (* ram_style = "distributed" *) reg [6:0] flags_way3 [0:SETS-1];

    (* ram_style = "distributed" *) reg [19:0] ppn_way0 [0:SETS-1];
    (* ram_style = "distributed" *) reg [19:0] ppn_way1 [0:SETS-1];
    (* ram_style = "distributed" *) reg [19:0] ppn_way2 [0:SETS-1];
    (* ram_style = "distributed" *) reg [19:0] ppn_way3 [0:SETS-1];

    // Per-set 4-way tree-PLRU bits.  A bit names the subtree/way to
    // replace next: [0]=root, [1]=left pair, [2]=right pair.
    reg [2:0] plru_r [0:SETS-1];

    // ------------------------------------------------------
    // Four-way lookup in one indexed set
    // ------------------------------------------------------
    wire way0_hit = lookup_valid && valid_r[lookup_set][0] &&
                    (tag_way0[lookup_set] == lookup_tag);
    wire way1_hit = lookup_valid && valid_r[lookup_set][1] &&
                    (tag_way1[lookup_set] == lookup_tag);
    wire way2_hit = lookup_valid && valid_r[lookup_set][2] &&
                    (tag_way2[lookup_set] == lookup_tag);
    wire way3_hit = lookup_valid && valid_r[lookup_set][3] &&
                    (tag_way3[lookup_set] == lookup_tag);

    reg [1:0]  hit_way_v;
    reg [19:0] hit_ppn_v;
    reg [6:0]  hit_flags_v;

    always @(*) begin
        hit_way_v   = 2'd0;
        hit_ppn_v   = 20'b0;
        hit_flags_v = 7'b0;

        if (way0_hit) begin
            hit_way_v   = 2'd0;
            hit_ppn_v   = ppn_way0[lookup_set];
            hit_flags_v = flags_way0[lookup_set];
        end
        else if (way1_hit) begin
            hit_way_v   = 2'd1;
            hit_ppn_v   = ppn_way1[lookup_set];
            hit_flags_v = flags_way1[lookup_set];
        end
        else if (way2_hit) begin
            hit_way_v   = 2'd2;
            hit_ppn_v   = ppn_way2[lookup_set];
            hit_flags_v = flags_way2[lookup_set];
        end
        else if (way3_hit) begin
            hit_way_v   = 2'd3;
            hit_ppn_v   = ppn_way3[lookup_set];
            hit_flags_v = flags_way3[lookup_set];
        end
    end

    assign hit     = way0_hit | way1_hit | way2_hit | way3_hit;
    assign hit_ppn = hit_ppn_v;
    assign hit_r   = hit_flags_v[0];
    assign hit_w   = hit_flags_v[1];
    assign hit_x   = hit_flags_v[2];
    assign hit_u   = hit_flags_v[3];
    assign hit_g   = hit_flags_v[4];
    assign hit_a   = hit_flags_v[5];
    assign hit_d   = hit_flags_v[6];

    // ------------------------------------------------------
    // Refill target: existing match -> invalid -> PLRU victim
    // ------------------------------------------------------
    wire refill_match0 = valid_r[refill_set][0] &&
                         (tag_way0[refill_set] == refill_tag);
    wire refill_match1 = valid_r[refill_set][1] &&
                         (tag_way1[refill_set] == refill_tag);
    wire refill_match2 = valid_r[refill_set][2] &&
                         (tag_way2[refill_set] == refill_tag);
    wire refill_match3 = valid_r[refill_set][3] &&
                         (tag_way3[refill_set] == refill_tag);

    reg [1:0] refill_way_v;
    reg [1:0] plru_victim_v;

    always @(*) begin
        if (plru_r[refill_set][0] == 1'b0)
            plru_victim_v = plru_r[refill_set][1] ? 2'd1 : 2'd0;
        else
            plru_victim_v = plru_r[refill_set][2] ? 2'd3 : 2'd2;

        if (refill_match0)
            refill_way_v = 2'd0;
        else if (refill_match1)
            refill_way_v = 2'd1;
        else if (refill_match2)
            refill_way_v = 2'd2;
        else if (refill_match3)
            refill_way_v = 2'd3;
        else if (!valid_r[refill_set][0])
            refill_way_v = 2'd0;
        else if (!valid_r[refill_set][1])
            refill_way_v = 2'd1;
        else if (!valid_r[refill_set][2])
            refill_way_v = 2'd2;
        else if (!valid_r[refill_set][3])
            refill_way_v = 2'd3;
        else
            refill_way_v = plru_victim_v;
    end

    function [2:0] plru_after_access;
        input [2:0] old_plru;
        input [1:0] accessed_way;
        begin
            plru_after_access = old_plru;
            case (accessed_way)
                2'd0: begin
                    plru_after_access[0] = 1'b1; // right pair is older
                    plru_after_access[1] = 1'b1; // way 1 is older
                end
                2'd1: begin
                    plru_after_access[0] = 1'b1;
                    plru_after_access[1] = 1'b0; // way 0 is older
                end
                2'd2: begin
                    plru_after_access[0] = 1'b0; // left pair is older
                    plru_after_access[2] = 1'b1; // way 3 is older
                end
                default: begin // way 3
                    plru_after_access[0] = 1'b0;
                    plru_after_access[2] = 1'b0; // way 2 is older
                end
            endcase
        end
    endfunction

    // ------------------------------------------------------
    // Storage and replacement-state update
    // ------------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < SETS; i = i + 1) begin
                valid_r[i] <= 4'b0000;
                plru_r[i]  <= 3'b000;
            end
        end
        else if (flush) begin
            for (i = 0; i < SETS; i = i + 1) begin
                valid_r[i] <= 4'b0000;
                plru_r[i]  <= 3'b000;
            end
        end
        else if (refill_valid) begin
            valid_r[refill_set][refill_way_v] <= 1'b1;
            case (refill_way_v)
                2'd0: begin
                    tag_way0[refill_set]   <= refill_tag;
                    ppn_way0[refill_set]   <= refill_ppn;
                    flags_way0[refill_set] <= {
                        refill_d, refill_a, refill_g, refill_u,
                        refill_x, refill_w, refill_r
                    };
                end
                2'd1: begin
                    tag_way1[refill_set]   <= refill_tag;
                    ppn_way1[refill_set]   <= refill_ppn;
                    flags_way1[refill_set] <= {
                        refill_d, refill_a, refill_g, refill_u,
                        refill_x, refill_w, refill_r
                    };
                end
                2'd2: begin
                    tag_way2[refill_set]   <= refill_tag;
                    ppn_way2[refill_set]   <= refill_ppn;
                    flags_way2[refill_set] <= {
                        refill_d, refill_a, refill_g, refill_u,
                        refill_x, refill_w, refill_r
                    };
                end
                default: begin
                    tag_way3[refill_set]   <= refill_tag;
                    ppn_way3[refill_set]   <= refill_ppn;
                    flags_way3[refill_set] <= {
                        refill_d, refill_a, refill_g, refill_u,
                        refill_x, refill_w, refill_r
                    };
                end
            endcase
            plru_r[refill_set] <= plru_after_access(
                plru_r[refill_set], refill_way_v
            );
        end
        else if (hit) begin
            plru_r[lookup_set] <= plru_after_access(
                plru_r[lookup_set], hit_way_v
            );
        end
    end

endmodule
