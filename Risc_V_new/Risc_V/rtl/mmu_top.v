`timescale 1ns / 1ps

// ============================================================
// mmu_top
//
// Per-core MMU: an instruction-side TLB + a data-side TLB, both
// backed by one shared page-table walker (mmu_ptw), per
// address_mapping:
//   VA(32b) = VPN[1](10b) | VPN[0](10b) | Offset(12b)
//   PA(32b) = PPN(20b)    | Offset(12b)
//   TLB: 16-entry, fully-associative, per core
//
// va_fetch/va_mem are translated combinationally every cycle
// (0-cycle latency on a hit, and permission bits are re-checked
// on every hit, not just at refill time). On a TLB miss, `busy`
// is asserted -- meant to drive the core's Stall_Core_External
// input -- while the shared PTW walks the 2-level page table
// over ptw_mem_req/ptw_mem_addr/ptw_mem_rdata. A hit whose
// cached permission bits don't cover the current access (e.g. a
// store to a read-only page) faults immediately, with no walk
// needed. If both sides need resolving on the same cycle, the
// data side goes first.
//
// mmu_enable=0 makes the whole block a transparent VA=PA
// passthrough: busy stays 0 and fetch_fault/mem_fault never
// pulse, regardless of what va_fetch/va_mem carry.
// ============================================================
module mmu_top (
    input  wire        clk,
    input  wire        rst,

    input  wire        mmu_enable,
    input  wire [19:0] satp_ppn,
    input  wire        flush,

    // Instruction-side translate port
    input  wire [31:0] va_fetch,
    output wire [31:0] pa_fetch,

    // Data-side translate port
    input  wire [31:0] va_mem,
    input  wire        mem_req,
    input  wire        mem_is_store,
    output wire [31:0] pa_mem,

    // Fault pulses (exactly 1 cycle, on the resume/gate cycle)
    output wire        fetch_fault,
    output wire        mem_fault,
    output wire [1:0]  fetch_fault_cause,
    output wire [1:0]  mem_fault_cause,

    // Shared PTW memory port (page-table reads only)
    output wire        ptw_mem_req,
    output wire [31:0] ptw_mem_addr,
    input  wire [31:0] ptw_mem_rdata,

    // Combined stall contribution: OR this into Stall_Core_External
    output wire        busy
);

    localparam [1:0]
        FAULT_NONE     = 2'd0,
        FAULT_NOTPRES  = 2'd1,
        FAULT_PERM     = 2'd2,
        FAULT_RESERVED = 2'd3;

    // ------------------------------------------------------
    // TLB lookups
    // ------------------------------------------------------
    wire [19:0] f_vpn = va_fetch[31:12];
    wire [19:0] d_vpn = va_mem[31:12];

    wire        itlb_hit;
    wire [19:0] itlb_ppn;
    wire        itlb_x;

    wire        dtlb_hit;
    wire [19:0] dtlb_ppn;
    wire        dtlb_r, dtlb_w;

    wire        itlb_refill;
    wire        dtlb_refill;
    wire [19:0] walk_vpn;
    wire [19:0] resp_ppn;
    wire        resp_r, resp_w, resp_x, resp_u, resp_g, resp_a, resp_d;

    mmu_tlb itlb (
        .clk(clk), .rst(rst), .flush(flush),
        .lookup_vpn(f_vpn),
        .hit(itlb_hit), .hit_ppn(itlb_ppn),
        .hit_r(), .hit_w(), .hit_x(itlb_x), .hit_u(), .hit_g(), .hit_a(), .hit_d(),
        .refill_valid(itlb_refill), .refill_vpn(walk_vpn), .refill_ppn(resp_ppn),
        .refill_r(resp_r), .refill_w(resp_w), .refill_x(resp_x),
        .refill_u(resp_u), .refill_g(resp_g), .refill_a(resp_a), .refill_d(resp_d)
    );

    mmu_tlb dtlb (
        .clk(clk), .rst(rst), .flush(flush),
        .lookup_vpn(d_vpn),
        .hit(dtlb_hit), .hit_ppn(dtlb_ppn),
        .hit_r(dtlb_r), .hit_w(dtlb_w), .hit_x(), .hit_u(), .hit_g(), .hit_a(), .hit_d(),
        .refill_valid(dtlb_refill), .refill_vpn(walk_vpn), .refill_ppn(resp_ppn),
        .refill_r(resp_r), .refill_w(resp_w), .refill_x(resp_x),
        .refill_u(resp_u), .refill_g(resp_g), .refill_a(resp_a), .refill_d(resp_d)
    );

    assign pa_fetch = mmu_enable ? {itlb_ppn, va_fetch[11:0]} : va_fetch;
    assign pa_mem   = mmu_enable ? {dtlb_ppn, va_mem[11:0]}   : va_mem;

    // A hit is only good enough if the cached permission bits
    // also cover *this* access -- re-checked every lookup, not
    // just when the entry was first refilled.
    wire f_permok = itlb_x;
    wire d_permok = mem_is_store ? dtlb_w : dtlb_r;

    wire f_problem    = mmu_enable & (~itlb_hit | (itlb_hit & ~f_permok));
    wire f_needs_walk = mmu_enable & ~itlb_hit;

    wire d_problem    = mmu_enable & mem_req & (~dtlb_hit | (dtlb_hit & ~d_permok));
    wire d_needs_walk = mmu_enable & mem_req & ~dtlb_hit;

    // ------------------------------------------------------
    // Walk control FSM
    //
    // T_IDLE: translate combinationally; on a problem, `busy`
    //         goes high THIS cycle (so the core freezes at the
    //         very next edge, holding va_fetch/va_mem steady)
    //         and the request is latched on that same edge.
    // T_WALK: PTW is walking; external bus belongs to the PTW.
    //         Skipped entirely for a hit-but-wrong-permission
    //         access, since no page-table read is needed.
    // T_GATE: one resume cycle. busy is already low here, so the
    //         frozen access is about to be consumed by the core;
    //         fetch_fault/mem_fault pulse here if it faulted, so
    //         the wrapper can force a NOP / block the store /
    //         zero the load on exactly this cycle.
    // ------------------------------------------------------
    localparam [1:0]
        T_IDLE = 2'd0,
        T_WALK = 2'd1,
        T_GATE = 2'd2;

    reg [1:0]  tstate;
    reg        r_walk_is_d;
    reg        r_walk_fault;
    reg [1:0]  r_walk_fault_cause;
    reg [19:0] r_walk_vpn;

    wire sel_d        = d_problem;
    wire sel_f        = !d_problem & f_problem;
    wire miss_now     = sel_d | sel_f;
    wire sel_needs_walk = sel_d ? d_needs_walk : f_needs_walk;

    assign busy = (tstate == T_WALK) || ((tstate == T_IDLE) && miss_now);

    wire        ptw_req_valid = (tstate == T_IDLE) && miss_now && sel_needs_walk;
    wire [19:0] ptw_req_vpn   = sel_d ? d_vpn : f_vpn;
    wire        ptw_req_store = sel_d ? mem_is_store : 1'b0;
    wire        ptw_req_fetch = sel_d ? 1'b0 : 1'b1;

    wire        ptw_resp_valid;
    wire        ptw_resp_fault;
    wire [1:0]  ptw_resp_fault_cause;

    mmu_ptw ptw_inst (
        .clk(clk), .rst(rst),
        .req_valid(ptw_req_valid),
        .req_vpn(ptw_req_vpn),
        .req_is_store(ptw_req_store),
        .req_is_fetch(ptw_req_fetch),
        .satp_ppn(satp_ppn),
        .ready(),
        .resp_valid(ptw_resp_valid),
        .resp_fault(ptw_resp_fault),
        .resp_fault_cause(ptw_resp_fault_cause),
        .resp_ppn(resp_ppn),
        .resp_r(resp_r), .resp_w(resp_w), .resp_x(resp_x),
        .resp_u(resp_u), .resp_g(resp_g), .resp_a(resp_a), .resp_d(resp_d),
        .mem_req(ptw_mem_req),
        .mem_addr(ptw_mem_addr),
        .mem_rdata(ptw_mem_rdata),
        .mem_valid(1'b1)
    );

    assign walk_vpn = r_walk_vpn;

    assign itlb_refill = (tstate == T_WALK) && ptw_resp_valid && !ptw_resp_fault && !r_walk_is_d;
    assign dtlb_refill = (tstate == T_WALK) && ptw_resp_valid && !ptw_resp_fault &&  r_walk_is_d;

    assign fetch_fault       = (tstate == T_GATE) && r_walk_fault && !r_walk_is_d;
    assign mem_fault         = (tstate == T_GATE) && r_walk_fault &&  r_walk_is_d;
    assign fetch_fault_cause = fetch_fault ? r_walk_fault_cause : 2'b00;
    assign mem_fault_cause   = mem_fault   ? r_walk_fault_cause : 2'b00;

    always @(posedge clk) begin
        if (rst) begin
            tstate             <= T_IDLE;
            r_walk_is_d        <= 1'b0;
            r_walk_fault       <= 1'b0;
            r_walk_fault_cause <= FAULT_NONE;
            r_walk_vpn         <= 20'b0;
        end
        else begin
            case (tstate)
                T_IDLE: begin
                    if (miss_now) begin
                        r_walk_is_d <= sel_d;
                        r_walk_vpn  <= sel_d ? d_vpn : f_vpn;

                        if (sel_needs_walk) begin
                            tstate <= T_WALK;
                        end
                        else begin
                            // Hit, but the cached permissions
                            // don't cover this access: no PTW
                            // walk needed, fault immediately.
                            r_walk_fault       <= 1'b1;
                            r_walk_fault_cause <= FAULT_PERM;
                            tstate             <= T_GATE;
                        end
                    end
                end

                T_WALK: begin
                    if (ptw_resp_valid) begin
                        r_walk_fault       <= ptw_resp_fault;
                        r_walk_fault_cause <= ptw_resp_fault_cause;
                        tstate             <= T_GATE;
                    end
                end

                T_GATE: begin
                    tstate <= T_IDLE;
                end

                default: begin
                    tstate <= T_IDLE;
                end
            endcase
        end
    end

endmodule
