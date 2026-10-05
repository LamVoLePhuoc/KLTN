`timescale 1ns / 1ps

// ============================================================
// tb_coherence_ahb
//
// NEW testbench, closing a gap explicitly flagged as unfinished in
// Risc_V_new/README.md (mục -0.25.2 / mục 9, item 15): quad_core_soc_ahb.v
// + ahb_lite_l1_adapter.v + ahb_lite_l1_slave_adapter.v had ONLY been
// checked statically (port cross-reference + hand trace), never
// exercised by a testbench. This matters much more now that AHB-Lite
// is the FINAL, chosen bus between the 4 cores and the rest of the
// system (README mục 4) -- quad_core_soc_ahb.v is no longer just an
// alternative, it is the architecture going in the report.
//
// Deliberately NOT a from-scratch test: this is tb_coherence.v's own
// 5-step MSI scenario (steps A-E, same addresses, same expected
// values, same checks), copied verbatim, with exactly one structural
// change -- each of the 4 l1_dcache instances' bus_req/bus_resp port
// no longer wires DIRECTLY to coherence_manager.v's dreq/dresp port;
// it goes through one ahb_lite_l1_adapter (master side) + one
// ahb_lite_l1_slave_adapter (slave side) pair instead, exactly
// mirroring quad_core_soc_ahb.v's own per-core D$ wiring (see that
// file's header for why this is 4 independent point-to-point links,
// not a shared multi-master AHB-Lite bus needing its own arbiter).
// Reusing the exact same test sequence this way means a PASS here is
// strong, direct evidence that the AHB-Lite bridge is protocol-
// transparent -- the same MSI ownership/data-forwarding invariant has
// to keep holding with
// the bridge spliced in, or this fails exactly where tb_coherence.v
// would have passed, pointing straight at the adapters as the cause.
//
// SCOPE (identical to tb_coherence.v, see its own header for the full
// reasoning): exercises the single highest-risk property of the whole
// design end-to-end THROUGH the AHB-Lite bridge. Does NOT exercise
// L1/L2 capacity eviction, I$ traffic, or a real RV32IMA pipeline --
// same limitations as tb_coherence.v, now also inherited by this file.
// A passing run here is necessary, not sufficient, evidence the
// bridge is correct.
//
// KNOWN, EXPECTED DIFFERENCE from tb_coherence.v's timing (NOT a bug
// if you see it in a waveform): every transaction now takes visibly
// longer in cycles -- 8 sequential single-word AHB-Lite transfers per
// line-fill/writeback (ahb_lite_l1_adapter.v's own documented,
// deliberate non-pipelined-burst tradeoff) versus tb_coherence.v's
// direct, effectively-1-cycle-per-word custom protocol. The cycle
// budget below is sized generously for this.
// ============================================================
module tb_coherence_ahb;

    localparam CLK_PERIOD = 10;
    localparam LINE_ADDR  = 32'h0000_1000;
    localparam L1_EVICT0  = 32'h0000_2200;

    reg clk, rst;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    wire HRESETn = ~rst;

    // ------------------------------------------------------
    // Simple per-core CPU-side drive (to l1_dcache) -- identical to
    // tb_coherence.v.
    // ------------------------------------------------------
    reg  [31:0] c_addr  [0:3];
    reg  [31:0] c_wdata [0:3];
    reg         c_we    [0:3];
    reg         c_re    [0:3];
    reg  [2:0]  c_memop [0:3];
    wire [31:0] c_rdata [0:3];
    wire        c_valid [0:3];

    // ------------------------------------------------------
    // l1_dcache <-> AHB-Lite bridge <-> coherence_manager per-core
    // buses. dreq_*/dresp_* here are the POST-bridge signals reaching
    // coherence_manager.v (same names/shape tb_coherence.v's own
    // dreq_*/dresp_* had, since that IS coherence_manager.v's fixed
    // port shape) -- the l1_dcache-side bus_req_*/bus_resp_* wires
    // (pre-bridge) are new, local to this file, one set per core.
    // ------------------------------------------------------
    wire         dreq_valid [0:3];
    wire [1:0]   dreq_type  [0:3];
    wire [31:0]  dreq_addr  [0:3];
    wire [255:0] dreq_line  [0:3];
    wire         dresp_valid[0:3];
    wire         dresp_error[0:3];
    wire [255:0] dresp_line [0:3];
    wire [1:0]   dresp_state[0:3];
    wire         dsnoop_valid[0:3];
    wire         dsnoop_type [0:3];
    wire [31:0]  dsnoop_addr [0:3];
    wire         dsnoop_ack_valid[0:3];
    wire         dsnoop_ack_hit  [0:3];
    wire         dsnoop_ack_dirty[0:3];
    wire [255:0] dsnoop_ack_line [0:3];

    // Pre-bridge (l1_dcache <-> ahb_lite_l1_adapter) ports
    wire         bus_req_valid [0:3];
    wire [1:0]   bus_req_type  [0:3];
    wire [31:0]  bus_req_addr  [0:3];
    wire [255:0] bus_req_line  [0:3];
    wire         bus_resp_valid[0:3];
    wire         bus_resp_error[0:3];
    wire [255:0] bus_resp_line [0:3];
    wire [1:0]   bus_resp_state[0:3];

    // AHB-Lite link wires, one set per core (point-to-point, same
    // topology reasoning as quad_core_soc_ahb.v -- no shared-bus
    // arbiter needed, coherence_manager.v's own 8-source arbiter
    // already does the real cross-core arbitration on the far side).
    wire [31:0] haddr  [0:3];
    wire        hwrite [0:3];
    wire [1:0]  htrans [0:3];
    wire [31:0] hwdata [0:3];
    wire [31:0] hrdata [0:3];
    wire        hready [0:3];
    wire [1:0]  hresp  [0:3];
    wire        hmastlock [0:3];
    wire [2:0]  hsize [0:3];
    wire [3:0]  hprot [0:3];

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : DCACHES
            l1_dcache u_dc (
                .clk(clk), .rst(rst), .flush(1'b0),
                .flush_busy(), .flush_done(),
                .cpu_addr(c_addr[gi]), .cpu_wdata(c_wdata[gi]),
                .cpu_we(c_we[gi]), .cpu_re(c_re[gi]), .cpu_memop(c_memop[gi]),
                .cpu_amo(1'b0), .cpu_amo_op(5'b0), .cpu_amo_operand(32'b0),
                .cpu_rdata(c_rdata[gi]), .cpu_valid(c_valid[gi]), .cpu_error(),
                .bus_req_valid(bus_req_valid[gi]), .bus_req_type(bus_req_type[gi]),
                .bus_req_addr(bus_req_addr[gi]), .bus_req_line(bus_req_line[gi]),
                .bus_resp_valid(bus_resp_valid[gi]), .bus_resp_error(bus_resp_error[gi]), .bus_resp_line(bus_resp_line[gi]), .bus_resp_state(bus_resp_state[gi]),
                .snoop_valid(dsnoop_valid[gi]), .snoop_type(dsnoop_type[gi]), .snoop_addr(dsnoop_addr[gi]),
                .snoop_ack_valid(dsnoop_ack_valid[gi]), .snoop_ack_hit(dsnoop_ack_hit[gi]),
                .snoop_ack_dirty(dsnoop_ack_dirty[gi]), .snoop_ack_line(dsnoop_ack_line[gi]), .flush_error()
            );

            ahb_lite_l1_adapter u_ahb_m (
                .HCLK(clk), .HRESETn(HRESETn),
                .bus_req_valid(bus_req_valid[gi]), .bus_req_type(bus_req_type[gi]),
                .bus_req_addr(bus_req_addr[gi]), .bus_req_line(bus_req_line[gi]),
                .bus_resp_valid(bus_resp_valid[gi]), .bus_resp_error(bus_resp_error[gi]), .bus_resp_line(bus_resp_line[gi]), .bus_resp_state(bus_resp_state[gi]),
                .HADDR(haddr[gi]), .HWRITE(hwrite[gi]), .HSIZE(hsize[gi]), .HTRANS(htrans[gi]),
                .HWDATA(hwdata[gi]), .HBURST(), .HPROT(hprot[gi]), .HMASTLOCK(hmastlock[gi]),
                .HRDATA(hrdata[gi]), .HREADY(hready[gi]), .HRESP(hresp[gi])
            );

            ahb_lite_l1_slave_adapter u_ahb_s (
                .HCLK(clk), .HRESETn(HRESETn),
                .HADDR(haddr[gi]), .HWRITE(hwrite[gi]), .HTRANS(htrans[gi]), .HWDATA(hwdata[gi]), .HMASTLOCK(hmastlock[gi]), .HSIZE(hsize[gi]), .HPROT(hprot[gi]),
                .HREADYOUT(hready[gi]), .HRDATA(hrdata[gi]), .HRESP(hresp[gi]),
                .dreq_valid(dreq_valid[gi]), .dreq_type(dreq_type[gi]),
                .dreq_addr(dreq_addr[gi]), .dreq_line(dreq_line[gi]),
                .dresp_valid(dresp_valid[gi]), .dresp_error(dresp_error[gi]), .dresp_line(dresp_line[gi]), .dresp_state(dresp_state[gi])
            );
        end
    endgenerate

    // ------------------------------------------------------
    // External memory model for coherence_manager's CPU Memory Port
    // -- identical to tb_coherence.v.
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
    // DUT -- coherence_manager.v itself is completely unmodified from
    // tb_coherence.v's own instantiation (same port shape, same
    // instantiation); only what feeds its dreq_*/dresp_* ports changed
    // (now the AHB-Lite slave adapters above, not l1_dcache directly).
    // ------------------------------------------------------
    coherence_manager u_cm (
        .clk(clk), .rst(rst),

        .c0_dreq_valid(dreq_valid[0]), .c0_dreq_type(dreq_type[0]), .c0_dreq_addr(dreq_addr[0]), .c0_dreq_line(dreq_line[0]),
        .c0_dresp_valid(dresp_valid[0]), .c0_dresp_error(dresp_error[0]), .c0_dresp_line(dresp_line[0]), .c0_dresp_state(dresp_state[0]),
        .c0_dsnoop_valid(dsnoop_valid[0]), .c0_dsnoop_type(dsnoop_type[0]), .c0_dsnoop_addr(dsnoop_addr[0]),
        .c0_dsnoop_ack_valid(dsnoop_ack_valid[0]), .c0_dsnoop_ack_hit(dsnoop_ack_hit[0]),
        .c0_dsnoop_ack_dirty(dsnoop_ack_dirty[0]), .c0_dsnoop_ack_line(dsnoop_ack_line[0]),
        .c0_ireq_valid(1'b0), .c0_ireq_addr(32'b0), .c0_iresp_valid(), .c0_iresp_error(), .c0_iresp_line(),

        .c1_dreq_valid(dreq_valid[1]), .c1_dreq_type(dreq_type[1]), .c1_dreq_addr(dreq_addr[1]), .c1_dreq_line(dreq_line[1]),
        .c1_dresp_valid(dresp_valid[1]), .c1_dresp_error(dresp_error[1]), .c1_dresp_line(dresp_line[1]), .c1_dresp_state(dresp_state[1]),
        .c1_dsnoop_valid(dsnoop_valid[1]), .c1_dsnoop_type(dsnoop_type[1]), .c1_dsnoop_addr(dsnoop_addr[1]),
        .c1_dsnoop_ack_valid(dsnoop_ack_valid[1]), .c1_dsnoop_ack_hit(dsnoop_ack_hit[1]),
        .c1_dsnoop_ack_dirty(dsnoop_ack_dirty[1]), .c1_dsnoop_ack_line(dsnoop_ack_line[1]),
        .c1_ireq_valid(1'b0), .c1_ireq_addr(32'b0), .c1_iresp_valid(), .c1_iresp_error(), .c1_iresp_line(),

        .c2_dreq_valid(dreq_valid[2]), .c2_dreq_type(dreq_type[2]), .c2_dreq_addr(dreq_addr[2]), .c2_dreq_line(dreq_line[2]),
        .c2_dresp_valid(dresp_valid[2]), .c2_dresp_error(dresp_error[2]), .c2_dresp_line(dresp_line[2]), .c2_dresp_state(dresp_state[2]),
        .c2_dsnoop_valid(dsnoop_valid[2]), .c2_dsnoop_type(dsnoop_type[2]), .c2_dsnoop_addr(dsnoop_addr[2]),
        .c2_dsnoop_ack_valid(dsnoop_ack_valid[2]), .c2_dsnoop_ack_hit(dsnoop_ack_hit[2]),
        .c2_dsnoop_ack_dirty(dsnoop_ack_dirty[2]), .c2_dsnoop_ack_line(dsnoop_ack_line[2]),
        .c2_ireq_valid(1'b0), .c2_ireq_addr(32'b0), .c2_iresp_valid(), .c2_iresp_error(), .c2_iresp_line(),

        .c3_dreq_valid(dreq_valid[3]), .c3_dreq_type(dreq_type[3]), .c3_dreq_addr(dreq_addr[3]), .c3_dreq_line(dreq_line[3]),
        .c3_dresp_valid(dresp_valid[3]), .c3_dresp_error(dresp_error[3]), .c3_dresp_line(dresp_line[3]), .c3_dresp_state(dresp_state[3]),
        .c3_dsnoop_valid(dsnoop_valid[3]), .c3_dsnoop_type(dsnoop_type[3]), .c3_dsnoop_addr(dsnoop_addr[3]),
        .c3_dsnoop_ack_valid(dsnoop_ack_valid[3]), .c3_dsnoop_ack_hit(dsnoop_ack_hit[3]),
        .c3_dsnoop_ack_dirty(dsnoop_ack_dirty[3]), .c3_dsnoop_ack_line(dsnoop_ack_line[3]),
        .c3_ireq_valid(1'b0), .c3_ireq_addr(32'b0), .c3_iresp_valid(), .c3_iresp_error(), .c3_iresp_line(),

        .mem_req_valid(mem_req_valid), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_valid(mem_valid), .mem_error(1'b0),
        .perf_total_requests(), .perf_d_bus_reads(), .perf_d_rfos(), .perf_d_writebacks(),
        .perf_i_reads(), .perf_l2_hits(), .perf_l2_misses(), .perf_snoop_requests(),
        .perf_mem_read_words(), .perf_mem_write_words(), .perf_busy_cycles(), .protocol_error(), .timeout_error(), .memory_error(),
        .debug_trace_rd_index(4'b0), .debug_trace_rd_data(), .debug_trace_count(),
        .debug_trace_write_index(), .debug_controller_state()
    );

    // ------------------------------------------------------
    // Verify an MSI S->M upgrade crosses the bridge as an RFO, uses
    // HMASTLOCK, reaches the CM with type=RFO, and exercises HREADY
    // back-pressure while the serialized transaction is pending.
    // ------------------------------------------------------
    reg monitor_core0_bus;
    integer core0_bus_events;
    integer core0_lock_cycles;
    integer core0_backend_rfo_cycles;
    integer core0_backend_rfo_total;
    integer backend_wb_total;
    integer core0_wait_cycles;
    integer e_grant_count;
    integer mon_i;
    always @(posedge clk) begin
        if (rst) begin
            core0_bus_events <= 0;
            core0_lock_cycles <= 0;
            core0_backend_rfo_cycles <= 0;
            core0_backend_rfo_total <= 0;
            backend_wb_total <= 0;
            core0_wait_cycles <= 0;
            e_grant_count <= 0;
        end
        else begin
            if (monitor_core0_bus && bus_req_valid[0]) core0_bus_events <= core0_bus_events + 1;
            if (monitor_core0_bus && hmastlock[0]) core0_lock_cycles <= core0_lock_cycles + 1;
            if (monitor_core0_bus && dreq_valid[0] && dreq_type[0] == 2'b01)
                core0_backend_rfo_cycles <= core0_backend_rfo_cycles + 1;
            if (dreq_valid[0] && dreq_type[0] == 2'b01)
                core0_backend_rfo_total <= core0_backend_rfo_total + 1;
            for (mon_i = 0; mon_i < 4; mon_i = mon_i + 1)
                if (dreq_valid[mon_i] && dreq_type[mon_i] == 2'b10)
                    backend_wb_total <= backend_wb_total + 1;
            if (monitor_core0_bus && !hready[0])
                core0_wait_cycles <= core0_wait_cycles + 1;
            for (mon_i = 0; mon_i < 4; mon_i = mon_i + 1)
                if (dresp_valid[mon_i] && dresp_state[mon_i] == 2'b10)
                    e_grant_count <= e_grant_count + 1;
        end
    end

    // ------------------------------------------------------
    // Test sequencing tasks -- identical to tb_coherence.v.
    // ------------------------------------------------------
    integer errors;
    integer k;

    task automatic do_read(input integer core, input [31:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            c_addr[core]  = addr;
            c_we[core]    = 1'b0;
            c_re[core]    = 1'b1;
            c_memop[core] = 3'b010; // LW
            @(posedge clk); #1;
            while (!c_valid[core]) begin
                @(posedge clk); #1;
            end
            data = c_rdata[core];
            @(negedge clk);
            c_re[core] = 1'b0;
        end
    endtask

    task automatic do_write(input integer core, input [31:0] addr, input [31:0] wdata);
        begin
            @(negedge clk);
            c_addr[core]  = addr;
            c_wdata[core] = wdata;
            c_we[core]    = 1'b1;
            c_re[core]    = 1'b0;
            c_memop[core] = 3'b010; // SW
            @(posedge clk); #1;
            while (!c_valid[core]) begin
                @(posedge clk); #1;
            end
            @(negedge clk);
            c_we[core] = 1'b0;
        end
    endtask

    task check_eq32(input [8*80-1:0] name, input [31:0] got, input [31:0] exp);
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

    task check_true(input [8*80-1:0] name, input condition);
        begin
            if (!condition) begin
                $display("[FAIL] %0s", name);
                errors = errors + 1;
            end
            else $display("[PASS] %0s", name);
        end
    endtask

    reg [31:0] rd;
    reg [31:0] rd0_concurrent;
    reg [31:0] rd3_concurrent;
    integer snap_backend_rfo;
    integer snap_backend_wb;

    initial begin
        errors = 0;
        rst = 1'b1;
        monitor_core0_bus = 1'b0;
        for (k = 0; k < 4; k = k + 1) begin
            c_addr[k] = 32'b0; c_wdata[k] = 32'b0; c_we[k] = 1'b0; c_re[k] = 1'b0; c_memop[k] = 3'b010;
        end
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        $display("---------------------------------------------");
        $display("MSI/AHB A: cold read returns S through the bridge");
        do_read(0, LINE_ADDR, rd);
        check_eq32("A: core0 initial read", rd, 32'h0000_0000);

        $display("MSI/AHB B: S->M must cross AHB as locked RFO");
        monitor_core0_bus = 1'b1;
        core0_bus_events  = 0;
        core0_lock_cycles = 0;
        core0_backend_rfo_cycles = 0;
        core0_wait_cycles = 0;
        snap_backend_rfo = core0_backend_rfo_total;
        do_write(0, LINE_ADDR, 32'hAAAA_0001);
        monitor_core0_bus = 1'b0;
        check_true("B: upgrade generated cache-side traffic", core0_bus_events > 0);
        check_true("B: RFO encoded with HMASTLOCK", core0_lock_cycles > 0);
        check_true("B: slave reconstructed backend RFO", core0_backend_rfo_total > snap_backend_rfo);
        check_true("B: HREADY inserted back-pressure", core0_wait_cycles > 0);

        $display("MSI/AHB C: another reader snoops M and gets latest data");
        do_read(1, LINE_ADDR, rd);
        check_eq32("C: core1 sees core0's dirty write", rd, 32'hAAAA_0001);

        $display("MSI/AHB D: another writer invalidates both sharers");
        do_write(2, LINE_ADDR, 32'hBBBB_0002);
        do_read(0, LINE_ADDR, rd); // core0 must miss now (was invalidated) and re-fetch
        check_eq32("D: core0 re-read after being invalidated by core2's RFO", rd, 32'hBBBB_0002);

        $display("MSI/AHB E: invalidated reader re-fetches authoritative value");
        do_read(1, LINE_ADDR, rd);
        check_eq32("E: core1 re-read after being invalidated by core2's RFO", rd, 32'hBBBB_0002);

        $display("MSI/AHB F: dirty L1 eviction crosses AHB as a writeback");
        do_write(0, L1_EVICT0,                32'hCAFE_0000);
        do_write(0, L1_EVICT0 + 32'h00004000, 32'hCAFE_0001);
        snap_backend_wb = backend_wb_total;
        do_write(0, L1_EVICT0 + 32'h00008000, 32'hCAFE_0002);
        check_true("F: slave reconstructed backend WRITEBACK", backend_wb_total > snap_backend_wb);
        do_read(1, L1_EVICT0, rd);
        check_eq32("F: consumer sees value written back through AHB", rd, 32'hCAFE_0000);

        $display("MSI/AHB G: simultaneous cores hold requests under CM back-pressure");
        fork
            begin do_read(0, 32'h0000_2A00, rd0_concurrent); end
            begin do_read(3, 32'h0000_2E00, rd3_concurrent); end
        join
        check_eq32("G: first concurrent read completes", rd0_concurrent, 32'h0000_0000);
        check_eq32("G: second held concurrent read is not lost", rd3_concurrent, 32'h0000_0000);

        check_true("MSI/AHB never granted Exclusive", e_grant_count == 0);
        $display("---------------------------------------------");
        if (errors == 0) begin
            $display("MSI_COHERENCE_AHB_TB: PASS");
        end
        else begin
            $display("MSI_COHERENCE_AHB_TB: FAIL (%0d check(s) failed)", errors);
        end
        $display("---------------------------------------------");
        $finish;
    end

    // Larger timeout than tb_coherence.v's -- see header: every
    // transaction now takes 8 sequential AHB-Lite word transfers
    // instead of tb_coherence.v's direct ~1-cycle-per-word protocol.
    initial begin
        #(CLK_PERIOD * 40000);
        $display("MSI_COHERENCE_AHB_TB: FAIL (global timeout -- dump AHB/coherence waves)");
        $finish;
    end

endmodule
