`timescale 1ns / 1ps

// ============================================================
// mmu_top
//
// Per-core MMU: an instruction-side TLB + a data-side TLB, both
// backed by one shared page-table walker (mmu_ptw), per
// address_mapping:
//   VA(32b) = VPN[1](10b) | VPN[0](10b) | Offset(12b)
//   PA(32b) = PPN(20b)    | Offset(12b)
//   4 KiB TLB: 16-entry, 4-set x 4-way, per core
//   4 MiB TLB: 4-entry fully-associative, per side
//
// va_fetch/va_mem are translated combinationally every cycle
// (0-cycle latency on a hit, and permission bits are re-checked
// on every hit, not just at refill time). On a TLB miss, `busy`
// is asserted -- meant to drive the core's Stall_Core_External
// input -- while the shared PTW walks the 2-level page table.
// The PTW port also writes Accessed/Dirty bits before refill. A hit whose
// cached permission bits don't cover the current access (e.g. a
// store to a read-only page) faults immediately, with no walk
// needed. If both sides need resolving on the same cycle, the
// data side goes first.
//
// REGION_POLICY_ENABLE=1 additionally enforces the coarse virtual
// regions defined in mmu_region_decode.v before a PTW is started.
// It defaults to 0 so existing firmware/page tables remain binary
// compatible while the new address map is brought up deliberately.
//
// DEBUG_TRACE_ENABLE=1 inserts a 16-entry translation-event buffer
// for simulation/ILA bring-up.  It defaults to 0, so normal board
// builds synthesize no debug buffer at all.
//
// mmu_enable=0 makes the whole block a transparent VA=PA
// passthrough: busy stays 0 and fetch_fault/mem_fault never
// pulse, regardless of what va_fetch/va_mem carry.
//
// Multi-cycle memory: `ptw_mem_valid` completes the current PTW
// operation -- read data when ptw_mem_we=0, write response when
// ptw_mem_we=1. The caller must not equate request assertion with
// same-cycle completion on a delayed/arbitrated bus.
// A flush or address-space configuration change received during T_WALK
// is deferred to the response boundary; that old-context response is
// discarded, all TLBs are invalidated, and an enabled held access is
// walked again without releasing the core. Changes to privilege/SUM/MXR
// also discard a response whose permission decision is no longer valid.
// ============================================================
module mmu_top #(
    parameter REGION_POLICY_ENABLE = 0,
    parameter DEBUG_TRACE_ENABLE   = 0,
    // Diagnostic only: after this many T_WALK cycles without a PTW
    // memory completion, ptw_timeout_error latches high until reset.
    // Zero removes the counter. It deliberately does not abort the
    // request because the current memory interface has no cancel/drain
    // handshake with which to reject a late cache/bus response safely.
    parameter integer PTW_WATCHDOG_CYCLES = 0
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        mmu_enable,
    input  wire [19:0] satp_ppn,
    input  wire        flush,
    input  wire [1:0]  current_priv,
    input  wire        mstatus_sum,
    input  wire        mstatus_mxr,

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
    output wire        fetch_access_fault,
    output wire        mem_access_fault,
    output wire [1:0]  fetch_fault_cause,
    output wire [1:0]  mem_fault_cause,

    // Shared PTW memory port (PTE reads plus A/D writeback)
    output wire        ptw_mem_req,
    output wire        ptw_mem_we,
    output wire [31:0] ptw_mem_addr,
    output wire [31:0] ptw_mem_wdata,
    input  wire [31:0] ptw_mem_rdata,
    input  wire        ptw_mem_valid,  // 1 exactly when ptw_mem_rdata is valid for ptw_mem_addr
    input  wire        ptw_mem_error,  // asserted with ptw_mem_valid on a failed PTE read/write

    // Combined stall contribution: OR this into Stall_Core_External
    output wire        busy,

    // Optional debug trace readout.  Record layout:
    // {event[2:0], is_data, fault, cause[1:0], VA[31:0], PA[31:0],
    //  controller_state[1:0], 7'b0}.  event: 1=start/problem,
    // 2=PTW response, 3=gate/resume, 4=flush/discard/retry. All outputs are zero when the
    // buffer is disabled, and debug_trace_rd_index is then unused.
    input  wire [3:0]  debug_trace_rd_index,
    output wire [79:0] debug_trace_rd_data,
    output wire [4:0]  debug_trace_count,
    output wire [3:0]  debug_trace_write_index,
    output wire [1:0]  debug_controller_state,
    output wire [2:0]  debug_fetch_region,
    output wire [2:0]  debug_mem_region,
    output wire        ptw_timeout_error
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

    wire        itlb_4k_hit, itlb_super_hit, itlb_hit;
    wire [19:0] itlb_4k_ppn, itlb_super_ppn, itlb_ppn;
    wire        itlb_4k_r, itlb_4k_w, itlb_4k_x, itlb_4k_u;
    wire        itlb_4k_g, itlb_4k_a, itlb_4k_d;
    wire        itlb_super_r, itlb_super_w, itlb_super_x, itlb_super_u;
    wire        itlb_super_g, itlb_super_a, itlb_super_d;
    wire        itlb_r, itlb_w, itlb_x, itlb_u, itlb_g, itlb_a, itlb_d;

    wire        dtlb_4k_hit, dtlb_super_hit, dtlb_hit;
    wire [19:0] dtlb_4k_ppn, dtlb_super_ppn, dtlb_ppn;
    wire        dtlb_4k_r, dtlb_4k_w, dtlb_4k_x, dtlb_4k_u;
    wire        dtlb_4k_g, dtlb_4k_a, dtlb_4k_d;
    wire        dtlb_super_r, dtlb_super_w, dtlb_super_x, dtlb_super_u;
    wire        dtlb_super_g, dtlb_super_a, dtlb_super_d;
    wire        dtlb_r, dtlb_w, dtlb_x, dtlb_u, dtlb_g, dtlb_a, dtlb_d;

    wire        itlb_refill, itlb_super_refill;
    wire        dtlb_refill, dtlb_super_refill;
    wire        tlb_flush;
    wire        lookup_context_valid;
    wire [19:0] walk_vpn;
    wire [19:0] resp_ppn;
    wire        resp_superpage;
    wire        resp_r, resp_w, resp_x, resp_u, resp_g, resp_a, resp_d;

    mmu_tlb itlb (
        .clk(clk), .rst(rst), .flush(tlb_flush),
        .lookup_valid(lookup_context_valid),
        .lookup_vpn(f_vpn),
        .hit(itlb_4k_hit), .hit_ppn(itlb_4k_ppn),
        .hit_r(itlb_4k_r), .hit_w(itlb_4k_w), .hit_x(itlb_4k_x),
        .hit_u(itlb_4k_u), .hit_g(itlb_4k_g), .hit_a(itlb_4k_a), .hit_d(itlb_4k_d),
        .refill_valid(itlb_refill), .refill_vpn(walk_vpn), .refill_ppn(resp_ppn),
        .refill_r(resp_r), .refill_w(resp_w), .refill_x(resp_x),
        .refill_u(resp_u), .refill_g(resp_g), .refill_a(resp_a), .refill_d(resp_d)
    );

    mmu_tlb dtlb (
        .clk(clk), .rst(rst), .flush(tlb_flush),
        .lookup_valid(lookup_context_valid & mem_req),
        .lookup_vpn(d_vpn),
        .hit(dtlb_4k_hit), .hit_ppn(dtlb_4k_ppn),
        .hit_r(dtlb_4k_r), .hit_w(dtlb_4k_w), .hit_x(dtlb_4k_x),
        .hit_u(dtlb_4k_u), .hit_g(dtlb_4k_g), .hit_a(dtlb_4k_a), .hit_d(dtlb_4k_d),
        .refill_valid(dtlb_refill), .refill_vpn(walk_vpn), .refill_ppn(resp_ppn),
        .refill_r(resp_r), .refill_w(resp_w), .refill_x(resp_x),
        .refill_u(resp_u), .refill_g(resp_g), .refill_a(resp_a), .refill_d(resp_d)
    );

    mmu_super_tlb itlb_super (
        .clk(clk), .rst(rst), .flush(tlb_flush),
        .lookup_valid(lookup_context_valid), .lookup_vpn(f_vpn),
        .hit(itlb_super_hit), .hit_ppn(itlb_super_ppn),
        .hit_r(itlb_super_r), .hit_w(itlb_super_w), .hit_x(itlb_super_x),
        .hit_u(itlb_super_u), .hit_g(itlb_super_g),
        .hit_a(itlb_super_a), .hit_d(itlb_super_d),
        .refill_valid(itlb_super_refill), .refill_vpn(walk_vpn),
        .refill_ppn(resp_ppn), .refill_r(resp_r), .refill_w(resp_w),
        .refill_x(resp_x), .refill_u(resp_u), .refill_g(resp_g),
        .refill_a(resp_a), .refill_d(resp_d)
    );

    mmu_super_tlb dtlb_super (
        .clk(clk), .rst(rst), .flush(tlb_flush),
        .lookup_valid(lookup_context_valid & mem_req), .lookup_vpn(d_vpn),
        .hit(dtlb_super_hit), .hit_ppn(dtlb_super_ppn),
        .hit_r(dtlb_super_r), .hit_w(dtlb_super_w), .hit_x(dtlb_super_x),
        .hit_u(dtlb_super_u), .hit_g(dtlb_super_g),
        .hit_a(dtlb_super_a), .hit_d(dtlb_super_d),
        .refill_valid(dtlb_super_refill), .refill_vpn(walk_vpn),
        .refill_ppn(resp_ppn), .refill_r(resp_r), .refill_w(resp_w),
        .refill_x(resp_x), .refill_u(resp_u), .refill_g(resp_g),
        .refill_a(resp_a), .refill_d(resp_d)
    );

    // A 4 KiB entry wins if stale mappings coexist; software must
    // still issue SFENCE.VMA after changing page-table leaf sizes.
    assign itlb_hit = itlb_4k_hit | itlb_super_hit;
    assign itlb_ppn = itlb_4k_hit ? itlb_4k_ppn : itlb_super_ppn;
    assign itlb_r = itlb_4k_hit ? itlb_4k_r : itlb_super_r;
    assign itlb_w = itlb_4k_hit ? itlb_4k_w : itlb_super_w;
    assign itlb_x = itlb_4k_hit ? itlb_4k_x : itlb_super_x;
    assign itlb_u = itlb_4k_hit ? itlb_4k_u : itlb_super_u;
    assign itlb_g = itlb_4k_hit ? itlb_4k_g : itlb_super_g;
    assign itlb_a = itlb_4k_hit ? itlb_4k_a : itlb_super_a;
    assign itlb_d = itlb_4k_hit ? itlb_4k_d : itlb_super_d;

    assign dtlb_hit = dtlb_4k_hit | dtlb_super_hit;
    assign dtlb_ppn = dtlb_4k_hit ? dtlb_4k_ppn : dtlb_super_ppn;
    assign dtlb_r = dtlb_4k_hit ? dtlb_4k_r : dtlb_super_r;
    assign dtlb_w = dtlb_4k_hit ? dtlb_4k_w : dtlb_super_w;
    assign dtlb_x = dtlb_4k_hit ? dtlb_4k_x : dtlb_super_x;
    assign dtlb_u = dtlb_4k_hit ? dtlb_4k_u : dtlb_super_u;
    assign dtlb_g = dtlb_4k_hit ? dtlb_4k_g : dtlb_super_g;
    assign dtlb_a = dtlb_4k_hit ? dtlb_4k_a : dtlb_super_a;
    assign dtlb_d = dtlb_4k_hit ? dtlb_4k_d : dtlb_super_d;

    assign pa_fetch = mmu_enable ? {itlb_ppn, va_fetch[11:0]} : va_fetch;
    assign pa_mem   = mmu_enable ? {dtlb_ppn, va_mem[11:0]}   : va_mem;

    // ------------------------------------------------------
    // Coarse virtual-address region decode
    // ------------------------------------------------------
    wire [2:0] f_region;
    wire [2:0] d_region;
    wire f_region_fetch_ok, f_region_load_ok, f_region_store_ok;
    wire d_region_fetch_ok, d_region_load_ok, d_region_store_ok;

    mmu_region_decode fetch_region_decode (
        .va(va_fetch),
        .region(f_region),
        .allow_fetch(f_region_fetch_ok),
        .allow_load(f_region_load_ok),
        .allow_store(f_region_store_ok)
    );

    mmu_region_decode data_region_decode (
        .va(va_mem),
        .region(d_region),
        .allow_fetch(d_region_fetch_ok),
        .allow_load(d_region_load_ok),
        .allow_store(d_region_store_ok)
    );

    assign debug_fetch_region = f_region;
    assign debug_mem_region   = d_region;

    wire f_region_bad = REGION_POLICY_ENABLE && !f_region_fetch_ok;
    wire d_region_bad = REGION_POLICY_ENABLE &&
                        (mem_is_store ? !d_region_store_ok : !d_region_load_ok);

    localparam [1:0] PRIV_U = 2'b00, PRIV_S = 2'b01, PRIV_M = 2'b11;

    // Permission metadata is re-checked on every hit. S-mode may
    // execute only supervisor pages; SUM affects S-mode data access
    // to U pages, and MXR lets loads read executable pages.
    wire f_privok = (current_priv == PRIV_M) ? 1'b1 :
                    (current_priv == PRIV_U) ? itlb_u : !itlb_u;
    wire d_privok = (current_priv == PRIV_M) ? 1'b1 :
                    (current_priv == PRIV_U) ? dtlb_u :
                    (!dtlb_u | mstatus_sum);
    wire f_permok = itlb_x & f_privok;
    wire d_access_permok = mem_is_store ? dtlb_w :
                           (dtlb_r | (mstatus_mxr & dtlb_x));
    wire d_permok = d_access_permok & d_privok;
    wire f_ad_ok = itlb_a;
    wire d_ad_ok = dtlb_a & (!mem_is_store | dtlb_d);

    wire f_problem = mmu_enable &
                     (f_region_bad | ~itlb_hit |
                      (itlb_hit & (~f_permok | ~f_ad_ok)));
    // A/D-only failures are repaired by walking and writing the PTE;
    // true permission failures fault immediately without a redundant walk.
    wire f_needs_walk = mmu_enable & ~f_region_bad &
                        (~itlb_hit | (itlb_hit & f_permok & ~f_ad_ok));

    wire d_problem = mmu_enable & mem_req &
                     (d_region_bad | ~dtlb_hit |
                      (dtlb_hit & (~d_permok | ~d_ad_ok)));
    wire d_needs_walk = mmu_enable & mem_req & ~d_region_bad &
                        (~dtlb_hit | (dtlb_hit & d_permok & ~d_ad_ok));

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
    reg        r_walk_access_fault;
    reg [1:0]  r_walk_fault_cause;
    reg [19:0] r_walk_vpn;
    reg [31:0] r_walk_va;
    reg [31:0] r_walk_pa;
    reg        flush_pending;
    reg        configured_mmu_enable;
    reg [19:0] configured_satp_ppn;
    reg [1:0]  r_walk_priv;
    reg        r_walk_sum;
    reg        r_walk_mxr;

    // A root/mode change invalidates every cached translation.  Track
    // it locally as well as honoring the explicit SFENCE/flush input so
    // the external-control mode cannot accidentally reuse a TLB entry
    // after Satp_PPN changes without a separate pulse.
    wire address_space_changed = (mmu_enable != configured_mmu_enable) ||
                                 (satp_ppn != configured_satp_ppn);
    wire invalidate_now = flush | address_space_changed;
    assign lookup_context_valid = mmu_enable & ~invalidate_now;

    wire sel_d        = d_problem;
    wire sel_f        = !d_problem & f_problem;
    wire miss_now     = sel_d | sel_f;
    wire sel_needs_walk = sel_d ? d_needs_walk : f_needs_walk;

    wire access_context_changed = (current_priv != r_walk_priv) ||
                                  (mstatus_sum != r_walk_sum) ||
                                  (mstatus_mxr != r_walk_mxr);
    wire gate_discard = invalidate_now | access_context_changed;

    assign busy = (tstate == T_WALK) ||
                  ((tstate == T_IDLE) && miss_now) ||
                  ((tstate == T_GATE) && gate_discard && mmu_enable);

    wire        ptw_req_valid = (tstate == T_IDLE) && miss_now && sel_needs_walk;
    wire [19:0] ptw_req_vpn   = sel_d ? d_vpn : f_vpn;
    wire        ptw_req_store = sel_d ? mem_is_store : 1'b0;
    wire        ptw_req_fetch = sel_d ? 1'b0 : 1'b1;

    wire        ptw_resp_valid;
    wire        ptw_resp_fault;
    wire        ptw_resp_access_fault;
    wire [1:0]  ptw_resp_fault_cause;

    // An invalidate that arrives during a walk must not be followed by
    // a stale refill from that same walk. Hold it pending until the PTW
    // returns, flush every TLB at that edge, discard the response and
    // re-enter IDLE. A permission-context change also discards/retries
    // the response, but needs no TLB flush because entries cache page
    // metadata rather than the current privilege/SUM/MXR decision.
    wire walk_invalidate = flush_pending | invalidate_now;
    wire walk_discard = walk_invalidate | access_context_changed;
    assign tlb_flush = ((tstate != T_WALK) && invalidate_now) ||
                       ((tstate == T_WALK) && ptw_resp_valid && walk_invalidate);

    mmu_ptw ptw_inst (
        .clk(clk), .rst(rst),
        .req_valid(ptw_req_valid),
        .req_vpn(ptw_req_vpn),
        .req_is_store(ptw_req_store),
        .req_is_fetch(ptw_req_fetch),
        .req_priv(current_priv),
        .req_sum(mstatus_sum),
        .req_mxr(mstatus_mxr),
        .satp_ppn(satp_ppn),
        .ready(),
        .resp_valid(ptw_resp_valid),
        .resp_fault(ptw_resp_fault),
        .resp_access_fault(ptw_resp_access_fault),
        .resp_fault_cause(ptw_resp_fault_cause),
        .resp_ppn(resp_ppn),
        .resp_superpage(resp_superpage),
        .resp_r(resp_r), .resp_w(resp_w), .resp_x(resp_x),
        .resp_u(resp_u), .resp_g(resp_g), .resp_a(resp_a), .resp_d(resp_d),
        .mem_req(ptw_mem_req),
        .mem_we(ptw_mem_we),
        .mem_addr(ptw_mem_addr),
        .mem_wdata(ptw_mem_wdata),
        .mem_rdata(ptw_mem_rdata),
        .mem_valid(ptw_mem_valid),
        .mem_error(ptw_mem_error)
    );

    assign walk_vpn = r_walk_vpn;

    wire refill_ok = (tstate == T_WALK) && ptw_resp_valid &&
                     !ptw_resp_fault && !walk_discard;
    assign itlb_refill       = refill_ok && !r_walk_is_d && !resp_superpage;
    assign itlb_super_refill = refill_ok && !r_walk_is_d &&  resp_superpage;
    assign dtlb_refill       = refill_ok &&  r_walk_is_d && !resp_superpage;
    assign dtlb_super_refill = refill_ok &&  r_walk_is_d &&  resp_superpage;

    assign fetch_fault       = (tstate == T_GATE) && r_walk_fault &&
                               !r_walk_access_fault && !r_walk_is_d && !gate_discard;
    assign mem_fault         = (tstate == T_GATE) && r_walk_fault &&
                               !r_walk_access_fault && r_walk_is_d && !gate_discard;
    assign fetch_access_fault = (tstate == T_GATE) && r_walk_access_fault &&
                                !r_walk_is_d && !gate_discard;
    assign mem_access_fault   = (tstate == T_GATE) && r_walk_access_fault &&
                                r_walk_is_d && !gate_discard;
    assign fetch_fault_cause = fetch_fault ? r_walk_fault_cause : 2'b00;
    assign mem_fault_cause   = mem_fault   ? r_walk_fault_cause : 2'b00;

    assign debug_controller_state = tstate;

    // ------------------------------------------------------
    // Optional translation trace buffer
    // ------------------------------------------------------
    reg        trace_event_valid;
    reg [79:0] trace_event_data;

    always @(*) begin
        trace_event_valid = 1'b0;
        trace_event_data  = 80'b0;

        if ((tstate == T_IDLE) && miss_now) begin
            trace_event_valid = 1'b1;
            trace_event_data = {
                3'd1, sel_d, 1'b0, FAULT_NONE,
                sel_d ? va_mem : va_fetch,
                sel_d ? pa_mem : pa_fetch,
                tstate, 7'b0
            };
        end
        else if ((tstate == T_WALK) && ptw_resp_valid) begin
            trace_event_valid = 1'b1;
            trace_event_data = {
                walk_discard ? 3'd4 : 3'd2,
                r_walk_is_d, ptw_resp_fault,
                ptw_resp_fault_cause, r_walk_va,
                {resp_ppn, r_walk_va[11:0]}, tstate, 7'b0
            };
        end
        else if (tstate == T_GATE) begin
            trace_event_valid = 1'b1;
            trace_event_data = {
                3'd3, r_walk_is_d, r_walk_fault,
                r_walk_fault_cause, r_walk_va, r_walk_pa,
                tstate, 7'b0
            };
        end
    end

    generate
        if (DEBUG_TRACE_ENABLE) begin : g_debug_trace
            mmu_debug_buffer trace_buffer (
                .clk(clk),
                .rst(rst),
                .event_valid(trace_event_valid),
                .event_data(trace_event_data),
                .read_index(debug_trace_rd_index),
                .read_data(debug_trace_rd_data),
                .record_count(debug_trace_count),
                .write_index(debug_trace_write_index)
            );
        end
        else begin : g_no_debug_trace
            assign debug_trace_rd_data     = 80'b0;
            assign debug_trace_count       = 5'b0;
            assign debug_trace_write_index = 4'b0;
        end
    endgenerate

    // A watchdog is useful in Vivado/ILA bring-up, but recovery is not
    // attempted here. Once a request has entered a cache or bus, merely
    // dropping ptw_mem_req cannot guarantee that its late response will
    // not be mistaken for a later request. A real recovery path therefore
    // also needs an error/cancel-or-drain handshake in the memory system.
    generate
        if (PTW_WATCHDOG_CYCLES > 0) begin : g_ptw_watchdog
            reg [31:0] wait_cycles;
            reg        timeout_sticky;
            assign ptw_timeout_error = timeout_sticky;

            always @(posedge clk) begin
                if (rst) begin
                    wait_cycles    <= 32'b0;
                    timeout_sticky <= 1'b0;
                end
                else if ((tstate != T_WALK) || ptw_resp_valid) begin
                    wait_cycles <= 32'b0;
                end
                else if (!timeout_sticky) begin
                    if (wait_cycles >= PTW_WATCHDOG_CYCLES-1)
                        timeout_sticky <= 1'b1;
                    else
                        wait_cycles <= wait_cycles + 32'd1;
                end
            end
        end
        else begin : g_no_ptw_watchdog
            assign ptw_timeout_error = 1'b0;
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            tstate             <= T_IDLE;
            r_walk_is_d        <= 1'b0;
            r_walk_fault       <= 1'b0;
            r_walk_access_fault <= 1'b0;
            r_walk_fault_cause <= FAULT_NONE;
            r_walk_vpn         <= 20'b0;
            r_walk_va          <= 32'b0;
            r_walk_pa          <= 32'b0;
            flush_pending      <= 1'b0;
            configured_mmu_enable <= 1'b0;
            configured_satp_ppn   <= 20'b0;
            r_walk_priv        <= PRIV_S;
            r_walk_sum         <= 1'b0;
            r_walk_mxr         <= 1'b0;
        end
        else begin
            configured_mmu_enable <= mmu_enable;
            configured_satp_ppn   <= satp_ppn;

            if ((tstate == T_WALK) && invalidate_now && !ptw_resp_valid)
                flush_pending <= 1'b1;
            else if ((tstate == T_WALK) && ptw_resp_valid && walk_invalidate)
                flush_pending <= 1'b0;
            else if (tstate != T_WALK)
                flush_pending <= 1'b0;

            case (tstate)
                T_IDLE: begin
                    if (miss_now) begin
                        r_walk_is_d <= sel_d;
                        r_walk_vpn  <= sel_d ? d_vpn : f_vpn;
                        r_walk_va   <= sel_d ? va_mem : va_fetch;
                        r_walk_priv <= current_priv;
                        r_walk_sum  <= mstatus_sum;
                        r_walk_mxr  <= mstatus_mxr;

                        if (sel_needs_walk) begin
                            tstate <= T_WALK;
                        end
                        else begin
                            // Hit, but the cached permissions
                            // don't cover this access: no PTW
                            // walk needed, fault immediately.
                            r_walk_fault       <= 1'b1;
                            r_walk_access_fault <= 1'b0;
                            r_walk_fault_cause <= FAULT_PERM;
                            r_walk_pa          <= sel_d ? pa_mem : pa_fetch;
                            tstate             <= T_GATE;
                        end
                    end
                end

                T_WALK: begin
                    if (ptw_resp_valid) begin
                        if (walk_discard) begin
                            // Do not expose a PA or fault derived from an
                            // invalidated address space or stale permission
                            // context. If translation remains enabled, IDLE
                            // sees the held VA and starts a fresh check/walk.
                            r_walk_fault       <= 1'b0;
                            r_walk_access_fault <= 1'b0;
                            r_walk_fault_cause <= FAULT_NONE;
                            tstate             <= T_IDLE;
                        end
                        else begin
                            r_walk_fault       <= ptw_resp_fault;
                            r_walk_access_fault <= ptw_resp_access_fault;
                            r_walk_fault_cause <= ptw_resp_fault_cause;
                            r_walk_pa          <= {resp_ppn, r_walk_va[11:0]};
                            tstate             <= T_GATE;
                        end
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
