// Interleaved weighted round-robin arbiter. Written to fill a genuinely
// missing dependency (rtl/common/arbiter/iwrr/ was empty in this repo).
//
// grant_valid_o is COMBINATIONAL: it reflects, every cycle, who would be
// granted right now given req_i and the current (registered) round-robin
// pointer/credit state -- it does not wait for grant_ready_i to produce a
// value. Only the internal state (pointer rotation, credit decrement)
// updates synchronously, and only on a cycle where the grant is actually
// accepted (grant_found && grant_ready_i). This matches how callers in
// this project use it: e.g. sa_Ax_channel.v ANDs arb_grant_valid together
// with arb_grant_ready in the same cycle to decide whether to consume a
// FIFO entry (see rd_addr_info in sa_Ax_channel.v) -- if grant_valid_o
// were registered (one cycle behind grant_ready_i, which itself is only a
// pulse), the two would never line up on the same cycle and the design
// would deadlock. "1cycle" in the module name refers to granting exactly
// one requester per cycle (as opposed to a multi-phase/multi-cycle
// arbitration scheme), not to output latency.
//
// Weights are taken from the P_REQUESTER_WEIGHT parameter (a packed array,
// 32 bits per requester), not from the req_weight_i port -- every caller in
// this project leaves req_weight_i unconnected and configures weights at
// elaboration time via the parameter instead (see sa_Ax_channel.v, which
// passes MST_WEIGHT = {L1_MASTER_AMT{32'd1}}, i.e. equal priority). Each
// requester gets a credit counter that starts at its weight and decrements
// by one per accepted grant; when it reaches zero it's reloaded from the
// weight parameter. The scan for the next grantee starts at a rotating
// pointer (round-robin) and prefers requesters that still have credit this
// round; if none of the currently-requesting masters have credit left
// (e.g. a misconfigured zero weight), it falls back to plain round-robin
// so the arbiter never deadlocks/starves everyone.
module arbiter_iwrr_1cycle #(
    parameter                          P_REQUESTER_NUM     = 4,
    parameter [P_REQUESTER_NUM*32-1:0] P_REQUESTER_WEIGHT  = {P_REQUESTER_NUM{32'd1}},
    parameter                          P_NUM_GRANT_REQ_W   = 1
)(
    input                               clk,
    input                               rst_n,
    input      [P_REQUESTER_NUM-1:0]    req_i,
    input      [P_REQUESTER_NUM*32-1:0] req_weight_i,
    input      [P_NUM_GRANT_REQ_W-1:0]  num_grant_req_i,
    input                               grant_ready_i,
    output     [P_REQUESTER_NUM-1:0]    grant_valid_o
);

    localparam PTR_W = (P_REQUESTER_NUM <= 1) ? 1 : $clog2(P_REQUESTER_NUM);

    function [31:0] weight_of;
        input integer idx;
        weight_of = P_REQUESTER_WEIGHT[idx*32 +: 32];
    endfunction

    reg [31:0]      credit [0:P_REQUESTER_NUM-1];
    reg [PTR_W-1:0] ptr;

    integer w;

    // Combinational scan: starting at ptr, find the next requester that
    // is asking (req_i) and still has credit this round; if none do,
    // fall back to the next requester that is simply asking.
    reg              grant_found;
    reg [PTR_W-1:0]  grant_idx;
    integer          k;
    integer          scan_idx;

    always @(*) begin
        grant_found = 1'b0;
        grant_idx   = ptr;
        for (k = 0; k < P_REQUESTER_NUM; k = k + 1) begin
            scan_idx = (ptr + k) % P_REQUESTER_NUM;
            if (!grant_found && req_i[scan_idx] && (credit[scan_idx] != 32'd0)) begin
                grant_found = 1'b1;
                grant_idx   = scan_idx[PTR_W-1:0];
            end
        end
        if (!grant_found) begin
            for (k = 0; k < P_REQUESTER_NUM; k = k + 1) begin
                scan_idx = (ptr + k) % P_REQUESTER_NUM;
                if (!grant_found && req_i[scan_idx]) begin
                    grant_found = 1'b1;
                    grant_idx   = scan_idx[PTR_W-1:0];
                end
            end
        end
    end

    assign grant_valid_o = grant_found ? ({{(P_REQUESTER_NUM-1){1'b0}}, 1'b1} << grant_idx) : {P_REQUESTER_NUM{1'b0}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr <= {PTR_W{1'b0}};
            for (w = 0; w < P_REQUESTER_NUM; w = w + 1) begin
                credit[w] <= weight_of(w);
            end
        end else if (grant_found && grant_ready_i) begin
            ptr <= (grant_idx == P_REQUESTER_NUM-1) ? {PTR_W{1'b0}} : grant_idx + 1'b1;
            if (credit[grant_idx] > 32'd1) begin
                credit[grant_idx] <= credit[grant_idx] - 32'd1;
            end else begin
                credit[grant_idx] <= weight_of(grant_idx);
            end
        end
    end

endmodule
