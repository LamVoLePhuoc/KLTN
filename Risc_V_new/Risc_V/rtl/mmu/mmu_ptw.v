`timescale 1ns / 1ps

// Two-level Sv32-style walker for the SoC's 32-bit PA convention.
// Supports 4 KiB pages, aligned 4 MiB level-1 leaves, U/S access
// checks with SUM/MXR, and hardware Accessed/Dirty PTE updates.
module mmu_ptw (
    input wire clk, input wire rst,
    input wire req_valid, input wire [19:0] req_vpn,
    input wire req_is_store, input wire req_is_fetch,
    input wire [1:0] req_priv, input wire req_sum, input wire req_mxr,
    input wire [19:0] satp_ppn,
    output wire ready,
    output reg resp_valid, output reg resp_fault,
    output reg resp_access_fault,
    output reg [1:0] resp_fault_cause, output reg [19:0] resp_ppn,
    output reg resp_superpage,
    output reg resp_r, output reg resp_w, output reg resp_x,
    output reg resp_u, output reg resp_g, output reg resp_a, output reg resp_d,
    output reg mem_req, output reg mem_we, output reg [31:0] mem_addr,
    output reg [31:0] mem_wdata,
    input wire [31:0] mem_rdata, input wire mem_valid,
    input wire mem_error
);
    localparam [1:0] S_IDLE=2'd0, S_L1_READ=2'd1,
                     S_L0_READ=2'd2, S_AD_WRITE=2'd3;
    localparam [1:0] FAULT_NONE=2'd0, FAULT_NOTPRES=2'd1,
                     FAULT_PERM=2'd2, FAULT_RESERVED=2'd3;
    localparam [1:0] PRIV_U=2'b00, PRIV_S=2'b01, PRIV_M=2'b11;

    reg [1:0] state;
    reg [19:0] r_vpn, r_satp_ppn;
    reg r_is_store, r_is_fetch, r_sum, r_mxr;
    reg [1:0] r_priv;
    reg [31:0] pte1;
    reg [19:0] pending_ppn;
    reg pending_superpage;
    reg [6:0] pending_flags;

    wire [31:0] pte1_addr = {r_satp_ppn, r_vpn[19:10], 2'b00};
    wire [31:0] pte0_addr = {pte1[31:12], r_vpn[9:0], 2'b00};
    wire pte_v=mem_rdata[0], pte_r=mem_rdata[1], pte_w=mem_rdata[2];
    wire pte_x=mem_rdata[3], pte_u=mem_rdata[4], pte_g=mem_rdata[5];
    wire pte_a=mem_rdata[6], pte_d=mem_rdata[7];
    wire [19:0] pte_ppn=mem_rdata[31:12];
    // This core keeps the complete 20-bit physical page number in
    // PTE[31:12]. PTE[9:8] remain software-reserved (RSW), while
    // PTE[11:10] have no implemented meaning and must be zero.  Do
    // not silently accept them: doing so would make a malformed PTE
    // translate differently on another Sv32 implementation.
    wire pte_reserved_bits = |mem_rdata[11:10];
    wire pte_reserved = pte_v && ((!pte_r && pte_w) || pte_reserved_bits);
    wire pte_is_leaf = pte_v && (pte_r || pte_w || pte_x) && !pte_reserved;
    wire pte_is_ptr = pte_v && !pte_r && !pte_w && !pte_x;
    // Sv32 reserves U/A/D in a non-leaf PTE. G is intentionally
    // allowed on a pointer because it propagates global mapping intent.
    wire pte_ptr_reserved = pte_is_ptr && (pte_u || pte_a || pte_d);

    // S-mode may never execute a U page. For data, SUM admits U pages.
    wire page_priv_ok = (r_priv == PRIV_M) ? 1'b1 :
                        (r_priv == PRIV_U) ? pte_u :
                        r_is_fetch ? !pte_u : (!pte_u | r_sum);
    wire access_perm_ok = r_is_fetch ? pte_x :
                          r_is_store ? pte_w : (pte_r | (r_mxr & pte_x));
    wire leaf_perm_ok = page_priv_ok & access_perm_ok;
    wire ad_update_needed = !pte_a | (r_is_store & !pte_d);
    wire [19:0] leaf_ppn = (state == S_L1_READ) ?
                            {pte_ppn[19:10], r_vpn[9:0]} : pte_ppn;
    wire leaf_g = (state == S_L0_READ) ? (pte_g | pte1[5]) : pte_g;
    wire [6:0] updated_flags = {(pte_d | r_is_store), 1'b1, leaf_g,
                                pte_u, pte_x, pte_w, pte_r};

    assign ready = (state == S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; r_vpn <= 0; r_satp_ppn <= 0;
            r_is_store <= 0; r_is_fetch <= 0; r_priv <= PRIV_S;
            r_sum <= 0; r_mxr <= 0; pte1 <= 0;
            pending_ppn <= 0; pending_superpage <= 0; pending_flags <= 0;
            resp_valid <= 0; resp_fault <= 0; resp_access_fault <= 0;
            resp_fault_cause <= FAULT_NONE;
            resp_ppn <= 0; resp_superpage <= 0;
            resp_r <= 0; resp_w <= 0; resp_x <= 0; resp_u <= 0;
            resp_g <= 0; resp_a <= 0; resp_d <= 0;
            mem_req <= 0; mem_we <= 0; mem_addr <= 0; mem_wdata <= 0;
        end else begin
            resp_valid <= 1'b0;
            resp_access_fault <= 1'b0;
            mem_req <= 1'b0;
            mem_we <= 1'b0;
            case (state)
                S_IDLE: if (req_valid) begin
                    r_vpn <= req_vpn; r_is_store <= req_is_store;
                    r_is_fetch <= req_is_fetch; r_priv <= req_priv;
                    r_sum <= req_sum; r_mxr <= req_mxr; r_satp_ppn <= satp_ppn;
                    mem_req <= 1'b1;
                    mem_addr <= {satp_ppn, req_vpn[19:10], 2'b00};
                    state <= S_L1_READ;
                end

                S_L1_READ: begin
                    if (!mem_valid) begin mem_req <= 1'b1; mem_addr <= pte1_addr; end
                    else if (mem_error) begin
                        resp_valid <= 1'b1; resp_fault <= 1'b1;
                        resp_access_fault <= 1'b1;
                        resp_fault_cause <= FAULT_NONE; state <= S_IDLE;
                    end
                    else if (!pte_v || pte_reserved) begin
                        resp_valid <= 1'b1; resp_fault <= 1'b1;
                        resp_fault_cause <= pte_reserved ? FAULT_RESERVED : FAULT_NOTPRES;
                        state <= S_IDLE;
                    end else if (pte_is_leaf) begin
                        if (pte_ppn[9:0] != 10'b0) begin
                            resp_valid <= 1'b1; resp_fault <= 1'b1;
                            resp_fault_cause <= FAULT_RESERVED; state <= S_IDLE;
                        end else if (!leaf_perm_ok) begin
                            resp_valid <= 1'b1; resp_fault <= 1'b1;
                            resp_fault_cause <= FAULT_PERM; state <= S_IDLE;
                        end else if (ad_update_needed) begin
                            pending_ppn <= leaf_ppn; pending_superpage <= 1'b1;
                            pending_flags <= updated_flags;
                            mem_req <= 1'b1; mem_we <= 1'b1; mem_addr <= pte1_addr;
                            mem_wdata <= mem_rdata | 32'h40 |
                                         (r_is_store ? 32'h80 : 32'b0);
                            state <= S_AD_WRITE;
                        end else begin
                            resp_valid <= 1'b1; resp_fault <= 1'b0;
                            resp_fault_cause <= FAULT_NONE; resp_ppn <= leaf_ppn;
                            resp_superpage <= 1'b1;
                            resp_r<=pte_r; resp_w<=pte_w; resp_x<=pte_x; resp_u<=pte_u;
                            resp_g<=leaf_g; resp_a<=pte_a; resp_d<=pte_d; state<=S_IDLE;
                        end
                    end else if (pte_is_ptr && !pte_ptr_reserved) begin
                        pte1 <= mem_rdata; mem_req <= 1'b1;
                        mem_addr <= {mem_rdata[31:12], r_vpn[9:0], 2'b00};
                        state <= S_L0_READ;
                    end else begin
                        resp_valid <= 1'b1; resp_fault <= 1'b1;
                        resp_fault_cause <= pte_ptr_reserved ?
                                            FAULT_RESERVED : FAULT_NOTPRES;
                        state <= S_IDLE;
                    end
                end

                S_L0_READ: begin
                    if (!mem_valid) begin mem_req <= 1'b1; mem_addr <= pte0_addr; end
                    else if (mem_error) begin
                        resp_valid <= 1'b1; resp_fault <= 1'b1;
                        resp_access_fault <= 1'b1;
                        resp_fault_cause <= FAULT_NONE; state <= S_IDLE;
                    end
                    else if (!pte_v || pte_reserved || pte_is_ptr) begin
                        resp_valid <= 1'b1; resp_fault <= 1'b1;
                        resp_fault_cause <= (pte_reserved || pte_ptr_reserved) ?
                                            FAULT_RESERVED : FAULT_NOTPRES;
                        state <= S_IDLE;
                    end else if (!leaf_perm_ok) begin
                        resp_valid <= 1'b1; resp_fault <= 1'b1;
                        resp_fault_cause <= FAULT_PERM; state <= S_IDLE;
                    end else if (ad_update_needed) begin
                        pending_ppn <= pte_ppn; pending_superpage <= 1'b0;
                        pending_flags <= updated_flags;
                        mem_req <= 1'b1; mem_we <= 1'b1; mem_addr <= pte0_addr;
                        mem_wdata <= mem_rdata | 32'h40 |
                                     (r_is_store ? 32'h80 : 32'b0);
                        state <= S_AD_WRITE;
                    end else begin
                        resp_valid <= 1'b1; resp_fault <= 1'b0;
                        resp_fault_cause <= FAULT_NONE; resp_ppn <= pte_ppn;
                        resp_superpage <= 1'b0;
                        resp_r<=pte_r; resp_w<=pte_w; resp_x<=pte_x; resp_u<=pte_u;
                        resp_g<=leaf_g; resp_a<=pte_a; resp_d<=pte_d; state<=S_IDLE;
                    end
                end

                S_AD_WRITE: begin
                    if (!mem_valid) begin mem_req <= 1'b1; mem_we <= 1'b1; end
                    else if (mem_error) begin
                        resp_valid <= 1'b1; resp_fault <= 1'b1;
                        resp_access_fault <= 1'b1;
                        resp_fault_cause <= FAULT_NONE; state <= S_IDLE;
                    end
                    else begin
                        resp_valid <= 1'b1; resp_fault <= 1'b0;
                        resp_fault_cause <= FAULT_NONE; resp_ppn <= pending_ppn;
                        resp_superpage <= pending_superpage;
                        resp_r<=pending_flags[0]; resp_w<=pending_flags[1];
                        resp_x<=pending_flags[2]; resp_u<=pending_flags[3];
                        resp_g<=pending_flags[4]; resp_a<=pending_flags[5];
                        resp_d<=pending_flags[6]; state<=S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
