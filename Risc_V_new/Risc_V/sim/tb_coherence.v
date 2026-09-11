`timescale 1ns / 1ps

// ============================================================
// tb_coherence
//
// Self-checking testbench for the MESI coherence subsystem built
// this session: l1_dcache.v + coherence_manager.v + l2_cache.v.
// THIS IS THE MOST IMPORTANT TESTBENCH IN THE REPO RIGHT NOW --
// coherence_manager.v is the highest-risk, least-verified file in
// the whole design (see Risc_V_new/README.md mục 9). Run this
// before trusting anything built on top of it.
//
// Drives 4 REAL l1_dcache.v instances directly at their simple
// cpu_addr/cpu_we/cpu_re/cpu_wdata/cpu_memop interface (i.e. as if
// each were a core's memory stage), rather than running real
// RV32IMA pipelines -- this keeps the exact cross-core access
// sequencing fully controllable by hand, which matters a lot for
// deliberately hitting specific MESI transitions (as opposed to
// hoping a hand-assembled multi-core program happens to race the
// right way). I-side ports are tied off (0 requests) -- I$ doesn't
// participate in coherence by design, see l1_icache.v.
//
// SCOPE: this exercises the single highest-risk property of the
// whole design -- the "mandatory snoop of a lone sharer" invariant
// that lets l2_cache.v's directory skip a separate "dirty owner"
// bit (see coherence_manager.v's header). It does NOT exercise:
//   - L1 or L2 capacity eviction / voluntary writeback (would need
//     enough distinct conflicting addresses to force it; not set up
//     here)
//   - I$ traffic
//   - Any interaction with a real RV32IMA pipeline (mmu_core_wrapper,
//     core_l1_wrapper) -- this tests the coherence subsystem in
//     isolation
// A passing run here is necessary, not sufficient, evidence that
// the protocol is correct. Treat a FAIL as "found a real bug, go
// fix coherence_manager.v/l1_dcache.v/l2_cache.v" -- that is exactly
// what this file is for.
//
// Test outline (single shared line @ PA 0x1000, one word tested):
//   A. core0 reads it (cold) -> L2 miss -> fetch-from-mem (returns 0,
//      memory model below is zero-initialized) -> granted Exclusive.
//   B. core0 writes it -> LOCAL hit on E, silently promotes to M, NO
//      bus transaction at all (checked explicitly).
//   C. core1 reads it -> L2 still shows sharers={core0}, dirty=0 (L2
//      has NO idea core0 silently went to M) -> the mandatory single-
//      sharer snoop must catch this, retrieve core0's real (dirty)
//      data, and hand core1 the CORRECT value -- not the stale value
//      L2 originally fetched from memory. This is the crux of the
//      whole directory design; if it fails, the "no dirty-owner bit
//      needed" argument in coherence_manager.v's header is wrong.
//   D. core2 writes it (RFO, line missing locally) -> must invalidate
//      BOTH core0 and core1 (2 sharers -- no snoop needed for
//      freshness per the invariant, but INVALIDATE is still required
//      to actually evict them), then core2 holds M with its own
//      stored value.
//   E. core0 reads it again (was invalidated in D) -> L2 shows a lone
//      sharer (core2) again -> mandatory snoop must retrieve core2's
//      dirty data (core2's OWN write, not the earlier value) and
//      hand it to core0 correctly. Proves the mandatory-snoop path
//      works in both "give me a share" directions, repeatedly, not
//      just once.
// ============================================================
module tb_coherence;

    localparam CLK_PERIOD = 10;
    localparam LINE_ADDR  = 32'h0000_1000;

    reg clk, rst;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------
    // Simple per-core CPU-side drive (to l1_dcache)
    // ------------------------------------------------------
    reg  [31:0] c_addr  [0:3];
    reg  [31:0] c_wdata [0:3];
    reg         c_we    [0:3];
    reg         c_re    [0:3];
    reg  [2:0]  c_memop [0:3];
    wire [31:0] c_rdata [0:3];
    wire        c_valid [0:3];

    // ------------------------------------------------------
    // l1_dcache <-> coherence_manager per-core buses
    // ------------------------------------------------------
    wire         dreq_valid [0:3];
    wire [1:0]   dreq_type  [0:3];
    wire [31:0]  dreq_addr  [0:3];
    wire [255:0] dreq_line  [0:3];
    wire         dresp_valid[0:3];
    wire [255:0] dresp_line [0:3];
    wire [1:0]   dresp_state[0:3];
    wire         dsnoop_valid[0:3];
    wire         dsnoop_type [0:3];
    wire [31:0]  dsnoop_addr [0:3];
    wire         dsnoop_ack_valid[0:3];
    wire         dsnoop_ack_hit  [0:3];
    wire         dsnoop_ack_dirty[0:3];
    wire [255:0] dsnoop_ack_line [0:3];

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : DCACHES
            l1_dcache u_dc (
                .clk(clk), .rst(rst), .flush(1'b0),
                .cpu_addr(c_addr[gi]), .cpu_wdata(c_wdata[gi]),
                .cpu_we(c_we[gi]), .cpu_re(c_re[gi]), .cpu_memop(c_memop[gi]),
                .cpu_rdata(c_rdata[gi]), .cpu_valid(c_valid[gi]),
                .bus_req_valid(dreq_valid[gi]), .bus_req_type(dreq_type[gi]),
                .bus_req_addr(dreq_addr[gi]), .bus_req_line(dreq_line[gi]),
                .bus_resp_valid(dresp_valid[gi]), .bus_resp_line(dresp_line[gi]), .bus_resp_state(dresp_state[gi]),
                .snoop_valid(dsnoop_valid[gi]), .snoop_type(dsnoop_type[gi]), .snoop_addr(dsnoop_addr[gi]),
                .snoop_ack_valid(dsnoop_ack_valid[gi]), .snoop_ack_hit(dsnoop_ack_hit[gi]),
                .snoop_ack_dirty(dsnoop_ack_dirty[gi]), .snoop_ack_line(dsnoop_ack_line[gi])
            );
        end
    endgenerate

    // ------------------------------------------------------
    // External memory model for coherence_manager's CPU Memory Port:
    // simple 1-cycle latency (address sampled this edge, response
    // the next), zero-initialized, 64KB.
    // ------------------------------------------------------
    reg [31:0] mem [0:16383];
    integer mi;
    initial for (mi = 0; mi < 16384; mi = mi + 1) mem[mi] = 32'h0;

    wire        mem_req_valid;
    wire        mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    reg  [31:0] mem_rdata;
    reg         mem_valid;

    always @(posedge clk) begin
        if (rst) begin
            mem_valid <= 1'b0;
        end
        else begin
            mem_valid <= mem_req_valid;
            if (mem_req_valid) begin
                if (mem_we) mem[mem_addr[15:2]] <= mem_wdata;
                else        mem_rdata           <= mem[mem_addr[15:2]];
            end
        end
    end

    // ------------------------------------------------------
    // DUT
    // ------------------------------------------------------
    coherence_manager u_cm (
        .clk(clk), .rst(rst),

        .c0_dreq_valid(dreq_valid[0]), .c0_dreq_type(dreq_type[0]), .c0_dreq_addr(dreq_addr[0]), .c0_dreq_line(dreq_line[0]),
        .c0_dresp_valid(dresp_valid[0]), .c0_dresp_line(dresp_line[0]), .c0_dresp_state(dresp_state[0]),
        .c0_dsnoop_valid(dsnoop_valid[0]), .c0_dsnoop_type(dsnoop_type[0]), .c0_dsnoop_addr(dsnoop_addr[0]),
        .c0_dsnoop_ack_valid(dsnoop_ack_valid[0]), .c0_dsnoop_ack_hit(dsnoop_ack_hit[0]),
        .c0_dsnoop_ack_dirty(dsnoop_ack_dirty[0]), .c0_dsnoop_ack_line(dsnoop_ack_line[0]),
        .c0_ireq_valid(1'b0), .c0_ireq_addr(32'b0), .c0_iresp_valid(), .c0_iresp_line(),

        .c1_dreq_valid(dreq_valid[1]), .c1_dreq_type(dreq_type[1]), .c1_dreq_addr(dreq_addr[1]), .c1_dreq_line(dreq_line[1]),
        .c1_dresp_valid(dresp_valid[1]), .c1_dresp_line(dresp_line[1]), .c1_dresp_state(dresp_state[1]),
        .c1_dsnoop_valid(dsnoop_valid[1]), .c1_dsnoop_type(dsnoop_type[1]), .c1_dsnoop_addr(dsnoop_addr[1]),
        .c1_dsnoop_ack_valid(dsnoop_ack_valid[1]), .c1_dsnoop_ack_hit(dsnoop_ack_hit[1]),
        .c1_dsnoop_ack_dirty(dsnoop_ack_dirty[1]), .c1_dsnoop_ack_line(dsnoop_ack_line[1]),
        .c1_ireq_valid(1'b0), .c1_ireq_addr(32'b0), .c1_iresp_valid(), .c1_iresp_line(),

        .c2_dreq_valid(dreq_valid[2]), .c2_dreq_type(dreq_type[2]), .c2_dreq_addr(dreq_addr[2]), .c2_dreq_line(dreq_line[2]),
        .c2_dresp_valid(dresp_valid[2]), .c2_dresp_line(dresp_line[2]), .c2_dresp_state(dresp_state[2]),
        .c2_dsnoop_valid(dsnoop_valid[2]), .c2_dsnoop_type(dsnoop_type[2]), .c2_dsnoop_addr(dsnoop_addr[2]),
        .c2_dsnoop_ack_valid(dsnoop_ack_valid[2]), .c2_dsnoop_ack_hit(dsnoop_ack_hit[2]),
        .c2_dsnoop_ack_dirty(dsnoop_ack_dirty[2]), .c2_dsnoop_ack_line(dsnoop_ack_line[2]),
        .c2_ireq_valid(1'b0), .c2_ireq_addr(32'b0), .c2_iresp_valid(), .c2_iresp_line(),

        .c3_dreq_valid(dreq_valid[3]), .c3_dreq_type(dreq_type[3]), .c3_dreq_addr(dreq_addr[3]), .c3_dreq_line(dreq_line[3]),
        .c3_dresp_valid(dresp_valid[3]), .c3_dresp_line(dresp_line[3]), .c3_dresp_state(dresp_state[3]),
        .c3_dsnoop_valid(dsnoop_valid[3]), .c3_dsnoop_type(dsnoop_type[3]), .c3_dsnoop_addr(dsnoop_addr[3]),
        .c3_dsnoop_ack_valid(dsnoop_ack_valid[3]), .c3_dsnoop_ack_hit(dsnoop_ack_hit[3]),
        .c3_dsnoop_ack_dirty(dsnoop_ack_dirty[3]), .c3_dsnoop_ack_line(dsnoop_ack_line[3]),
        .c3_ireq_valid(1'b0), .c3_ireq_addr(32'b0), .c3_iresp_valid(), .c3_iresp_line(),

        .mem_req_valid(mem_req_valid), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_valid(mem_valid)
    );

    // ------------------------------------------------------
    // Bus-traffic monitor: catches "core0's silent local upgrade in
    // step B accidentally also hit the bus" (it must NOT).
    // ------------------------------------------------------
    reg monitor_core0_bus;
    integer core0_bus_events;
    always @(posedge clk) begin
        if (rst) core0_bus_events <= 0;
        else if (monitor_core0_bus && dreq_valid[0]) core0_bus_events <= core0_bus_events + 1;
    end

    // ------------------------------------------------------
    // Test sequencing tasks
    // ------------------------------------------------------
    integer errors;
    integer k;

    task automatic do_read(input integer core, input [31:0] addr, output [31:0] data);
        begin
            c_addr[core]  = addr;
            c_we[core]    = 1'b0;
            c_re[core]    = 1'b1;
            c_memop[core] = 3'b010; // LW
            @(posedge clk);
            while (!c_valid[core]) @(posedge clk);
            data = c_rdata[core];
            c_re[core] = 1'b0;
            @(posedge clk); // 1 idle cycle so the next op starts clean
        end
    endtask

    task automatic do_write(input integer core, input [31:0] addr, input [31:0] wdata);
        begin
            c_addr[core]  = addr;
            c_wdata[core] = wdata;
            c_we[core]    = 1'b1;
            c_re[core]    = 1'b0;
            c_memop[core] = 3'b010; // SW
            @(posedge clk);
            while (!c_valid[core]) @(posedge clk);
            c_we[core] = 1'b0;
            @(posedge clk);
        end
    endtask

    task check_eq32(input [8*40-1:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("[FAIL] %0s: got=0x%08h expected=0x%08h", name, got, exp);
                errors = errors + 1;
            end
            else begin
                $display("[PASS] %0s: 0x%08h", name, got);
            end
        end
    endtask

    reg [31:0] rd;

    initial begin
        errors = 0;
        rst = 1'b1;
        monitor_core0_bus = 1'b0;
        for (k = 0; k < 4; k = k + 1) begin
            c_addr[k] = 32'b0; c_wdata[k] = 32'b0; c_we[k] = 1'b0; c_re[k] = 1'b0; c_memop[k] = 3'b010;
        end
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        $display("---------------------------------------------");
        $display("tb_coherence: step A -- core0 cold read (expect 0, grant E)");
        do_read(0, LINE_ADDR, rd);
        check_eq32("A: core0 initial read", rd, 32'h0000_0000);

        $display("tb_coherence: step B -- core0 local write (E->M, no bus traffic expected)");
        monitor_core0_bus = 1'b1;
        core0_bus_events  = 0;
        do_write(0, LINE_ADDR, 32'hAAAA_0001);
        monitor_core0_bus = 1'b0;
        if (core0_bus_events != 0) begin
            $display("[FAIL] B: core0's E->M write hit the bus %0d time(s) -- should be silent/local", core0_bus_events);
            errors = errors + 1;
        end
        else begin
            $display("[PASS] B: core0's E->M write stayed local (no bus traffic)");
        end

        $display("tb_coherence: step C -- core1 read (must catch core0's silent M via mandatory snoop)");
        do_read(1, LINE_ADDR, rd);
        check_eq32("C: core1 sees core0's dirty write", rd, 32'hAAAA_0001);

        $display("tb_coherence: step D -- core2 RFO write (must invalidate core0 AND core1)");
        do_write(2, LINE_ADDR, 32'hBBBB_0002);
        do_read(0, LINE_ADDR, rd); // core0 must miss now (was invalidated) and re-fetch
        check_eq32("D: core0 re-read after being invalidated by core2's RFO", rd, 32'hBBBB_0002);

        $display("tb_coherence: step E -- core... re-check core1 also invalidated, and core2's data is authoritative");
        do_read(1, LINE_ADDR, rd);
        check_eq32("E: core1 re-read after being invalidated by core2's RFO", rd, 32'hBBBB_0002);

        $display("---------------------------------------------");
        if (errors == 0) begin
            $display("COHERENCE_TB: PASS");
        end
        else begin
            $display("COHERENCE_TB: FAIL (%0d check(s) failed)", errors);
        end
        $display("---------------------------------------------");
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 20000);
        $display("COHERENCE_TB: FAIL (global timeout -- likely a hang in coherence_manager's FSM; dump waves)");
        $finish;
    end

endmodule
