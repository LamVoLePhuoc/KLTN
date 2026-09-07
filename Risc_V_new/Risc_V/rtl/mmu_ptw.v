`timescale 1ns / 1ps

// ============================================================
// mmu_ptw
//
// 2-level Sv32-style page table walker sized for a 32-bit
// physical address space, per address_mapping:
//   VA(32b) = VPN[1](10b) | VPN[0](10b) | Offset(12b)
//   PA(32b) = PPN(20b)    | Offset(12b)
//   2-level page table, 1024 PTE x 4 byte per table (one 4KB page)
//
// PTE layout (one 32-bit word per entry, bit positions match
// real Sv32's flag bits; PPN is 20 bits instead of Sv32's 22,
// because this SoC's PA is 32-bit, not RV32's usual 34-bit):
//   bit0 V, bit1 R, bit2 W, bit3 X, bit4 U, bit5 G, bit6 A, bit7 D
//   bits9:8 RSW (unused), bits31:12 PPN[19:0]
//
// One translation request in flight at a time.
//
// Limitations (see mmu_core_wrapper.v header for the reasoning):
//  - Read-only: never writes A/D back to the page table. A/D are
//    passed through to the TLB exactly as found in the PTE.
//  - No 4MB superpage support (a leaf found at level 1) -- the
//    TLB entry format is a flat VPN(20b)->PPN(20b) mapping with
//    no page-size field, so a level-1 leaf is treated as a fault.
//  - No privilege levels: the U bit is carried into the TLB but
//    not enforced (this core has no S/U-mode CSR).
// ============================================================
module mmu_ptw (
    input  wire        clk,
    input  wire        rst,

    // Translation request (sampled while ready==1)
    input  wire        req_valid,
    input  wire [19:0] req_vpn,          // VA[31:12]
    input  wire        req_is_store,
    input  wire        req_is_fetch,
    input  wire [19:0] satp_ppn,         // root page table's PPN

    output wire        ready,            // 1 when idle

    // Response (1-cycle pulse)
    output reg         resp_valid,
    output reg         resp_fault,
    output reg  [1:0]  resp_fault_cause, // 0 none,1 not-present,2 perm,3 reserved-encoding
    output reg  [19:0] resp_ppn,
    output reg         resp_r,
    output reg         resp_w,
    output reg         resp_x,
    output reg         resp_u,
    output reg         resp_g,
    output reg         resp_a,
    output reg         resp_d,

    // Memory port (read-only page-table access)
    output reg         mem_req,
    output reg  [31:0] mem_addr,
    input  wire [31:0] mem_rdata,
    input  wire        mem_valid
);

    localparam [1:0]
        S_IDLE = 2'd0,
        S_L1   = 2'd1,
        S_L0   = 2'd2;

    localparam [1:0]
        FAULT_NONE     = 2'd0,
        FAULT_NOTPRES  = 2'd1,
        FAULT_PERM     = 2'd2,
        FAULT_RESERVED = 2'd3;

    reg [1:0]  state;

    reg [19:0] r_vpn;
    reg        r_is_store;
    reg        r_is_fetch;
    reg [19:0] r_satp_ppn;
    reg [31:0] pte1;

    wire [31:0] pte1_addr = {r_satp_ppn, r_vpn[19:10], 2'b00};
    wire [31:0] pte0_addr = {pte1[31:12], r_vpn[9:0], 2'b00};

    // ------------------------------------------------------
    // PTE field decode of whatever is currently on mem_rdata
    // ------------------------------------------------------
    wire        pte_v   = mem_rdata[0];
    wire        pte_r   = mem_rdata[1];
    wire        pte_w   = mem_rdata[2];
    wire        pte_x   = mem_rdata[3];
    wire        pte_u   = mem_rdata[4];
    wire        pte_g   = mem_rdata[5];
    wire        pte_a   = mem_rdata[6];
    wire        pte_d   = mem_rdata[7];
    wire [19:0] pte_ppn = mem_rdata[31:12];

    wire pte_reserved = pte_v && !pte_r && pte_w;             // R=0,W=1 is reserved
    wire pte_is_leaf  = pte_v && (pte_r || pte_w || pte_x) && !pte_reserved;
    wire pte_is_ptr   = pte_v && !pte_r && !pte_w && !pte_x;

    wire perm_ok = r_is_fetch ? pte_x : (r_is_store ? pte_w : pte_r);

    assign ready = (state == S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            r_vpn      <= 20'b0;
            r_is_store <= 1'b0;
            r_is_fetch <= 1'b0;
            r_satp_ppn <= 20'b0;
            pte1       <= 32'b0;

            resp_valid       <= 1'b0;
            resp_fault       <= 1'b0;
            resp_fault_cause <= FAULT_NONE;
            resp_ppn         <= 20'b0;
            resp_r <= 1'b0; resp_w <= 1'b0; resp_x <= 1'b0;
            resp_u <= 1'b0; resp_g <= 1'b0; resp_a <= 1'b0; resp_d <= 1'b0;

            mem_req  <= 1'b0;
            mem_addr <= 32'b0;
        end
        else begin
            resp_valid <= 1'b0;
            mem_req    <= 1'b0;

            case (state)
                // --------------------------------------------
                S_IDLE: begin
                    if (req_valid) begin
                        r_vpn      <= req_vpn;
                        r_is_store <= req_is_store;
                        r_is_fetch <= req_is_fetch;
                        r_satp_ppn <= satp_ppn;

                        mem_req  <= 1'b1;
                        mem_addr <= {satp_ppn, req_vpn[19:10], 2'b00};

                        state <= S_L1;
                    end
                end

                // --------------------------------------------
                // Waiting for the level-1 (root) PTE
                // --------------------------------------------
                S_L1: begin
                    if (mem_valid) begin
                        if (!pte_v || pte_reserved) begin
                            resp_valid       <= 1'b1;
                            resp_fault       <= 1'b1;
                            resp_fault_cause <= pte_reserved ? FAULT_RESERVED : FAULT_NOTPRES;
                            state            <= S_IDLE;
                        end
                        else if (pte_is_leaf) begin
                            // 4MB superpage: not supported by this
                            // TLB's flat VPN(20b)->PPN(20b) format.
                            resp_valid       <= 1'b1;
                            resp_fault       <= 1'b1;
                            resp_fault_cause <= FAULT_RESERVED;
                            state            <= S_IDLE;
                        end
                        else begin
                            // Pointer to the level-0 table.
                            pte1     <= mem_rdata;
                            mem_req  <= 1'b1;
                            mem_addr <= {mem_rdata[31:12], r_vpn[9:0], 2'b00};
                            state    <= S_L0;
                        end
                    end
                    else begin
                        mem_req  <= 1'b1;
                        mem_addr <= pte1_addr;
                    end
                end

                // --------------------------------------------
                // Waiting for the level-0 (leaf) PTE
                // --------------------------------------------
                S_L0: begin
                    if (mem_valid) begin
                        resp_valid <= 1'b1;

                        if (!pte_v || pte_reserved || pte_is_ptr) begin
                            resp_fault       <= 1'b1;
                            resp_fault_cause <= pte_reserved ? FAULT_RESERVED : FAULT_NOTPRES;
                        end
                        else if (!perm_ok) begin
                            resp_fault       <= 1'b1;
                            resp_fault_cause <= FAULT_PERM;
                        end
                        else begin
                            resp_fault       <= 1'b0;
                            resp_fault_cause <= FAULT_NONE;
                            resp_ppn         <= pte_ppn;
                            resp_r <= pte_r; resp_w <= pte_w; resp_x <= pte_x;
                            resp_u <= pte_u; resp_g <= pte_g; resp_a <= pte_a; resp_d <= pte_d;
                        end

                        state <= S_IDLE;
                    end
                    else begin
                        mem_req  <= 1'b1;
                        mem_addr <= pte0_addr;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
