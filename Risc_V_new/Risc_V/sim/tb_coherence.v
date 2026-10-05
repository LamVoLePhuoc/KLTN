`timescale 1ns / 1ps

// ============================================================
// tb_coherence
//
// Self-checking testbench for the 4-core MSI subsystem:
// l1_dcache.v + cache_controller_mmu.v + peer l2_cache.v.
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
// deliberately hitting specific MSI transitions (as opposed to
// hoping a hand-assembled multi-core program happens to race the
// right way). I-side ports are tied off (0 requests) -- I$ doesn't
// participate in coherence by design, see l1_icache.v.
//
// Covers I->S, S->M, M->S, M->I, four sharers, producer/consumer,
// false sharing, dirty L1 eviction, inclusive dirty L2 eviction and
// the rule that a value already present in L1/L2 must not be fetched
// from DRAM again. I$ and the CPU pipeline remain outside this unit
// test; the AHB bridge has its own companion testbench.
// A passing run here is necessary, not sufficient, evidence that
// the protocol is correct. Treat a FAIL as "found a real bug, go
// fix coherence_manager.v/l1_dcache.v/l2_cache.v" -- that is exactly
// what this file is for.
//
// ============================================================
module tb_coherence;

    localparam CLK_PERIOD = 10;
    localparam LINE_ADDR  = 32'h0000_1000;
    localparam FOUR_ADDR  = 32'h0000_1800;
    localparam FALSE_ADDR = 32'h0000_1C00;
    localparam L1_EVICT0  = 32'h0000_2200;
    localparam L2_EVICT0  = 32'h0000_0300;

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
    reg         c_flush [0:3];
    reg  [2:0]  c_memop [0:3];
    reg         c_amo [0:3];
    reg  [4:0]  c_amo_op [0:3];
    reg  [31:0] c_amo_operand [0:3];
    wire [31:0] c_rdata [0:3];
    wire        c_valid [0:3];
    wire        c_flush_busy [0:3];
    wire        c_flush_done [0:3];

    // ------------------------------------------------------
    // l1_dcache <-> coherence_manager per-core buses
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
    wire [31:0] perf_total_requests, perf_d_bus_reads, perf_d_rfos;
    wire [31:0] perf_d_writebacks, perf_i_reads, perf_l2_hits, perf_l2_misses;
    wire [31:0] perf_snoop_requests, perf_mem_read_words, perf_mem_write_words;
    wire [31:0] perf_busy_cycles;
    wire        protocol_error;
    wire        timeout_error;
    wire        memory_error;
    reg  [3:0]  debug_trace_rd_index;
    wire [95:0] debug_trace_rd_data;
    wire [4:0]  debug_trace_count;
    wire [3:0]  debug_trace_write_index;
    wire [3:0]  debug_controller_state;
    wire         l2_cmd_valid;
    wire         l2_cmd_we;
    wire [31:0]  l2_cmd_addr;
    wire [1:0]   l2_cmd_way;
    wire [255:0] l2_cmd_wdata;
    wire         l2_cmd_w_valid;
    wire         l2_cmd_w_dirty;
    wire [3:0]   l2_cmd_w_sharers;
    wire         l2_resp_valid;
    wire         l2_resp_hit;
    wire [1:0]   l2_resp_way;
    wire [14:0]  l2_resp_victim_tag;
    wire         l2_resp_victim_valid;
    wire         l2_resp_victim_dirty;
    wire [3:0]   l2_resp_victim_sharers;
    wire [255:0] l2_resp_line;
    wire [3:0]   l2_resp_sharers;

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : DCACHES
            l1_dcache u_dc (
                .clk(clk), .rst(rst), .flush(c_flush[gi]),
                .flush_busy(c_flush_busy[gi]), .flush_done(c_flush_done[gi]),
                .cpu_addr(c_addr[gi]), .cpu_wdata(c_wdata[gi]),
                .cpu_we(c_we[gi]), .cpu_re(c_re[gi]), .cpu_memop(c_memop[gi]),
                .cpu_amo(c_amo[gi]), .cpu_amo_op(c_amo_op[gi]),
                .cpu_amo_operand(c_amo_operand[gi]),
                .cpu_rdata(c_rdata[gi]), .cpu_valid(c_valid[gi]), .cpu_error(),
                .bus_req_valid(dreq_valid[gi]), .bus_req_type(dreq_type[gi]),
                .bus_req_addr(dreq_addr[gi]), .bus_req_line(dreq_line[gi]),
                .bus_resp_valid(dresp_valid[gi]), .bus_resp_error(dresp_error[gi]), .bus_resp_line(dresp_line[gi]), .bus_resp_state(dresp_state[gi]),
                .snoop_valid(dsnoop_valid[gi]), .snoop_type(dsnoop_type[gi]), .snoop_addr(dsnoop_addr[gi]),
                .snoop_ack_valid(dsnoop_ack_valid[gi]), .snoop_ack_hit(dsnoop_ack_hit[gi]),
                .snoop_ack_dirty(dsnoop_ack_dirty[gi]), .snoop_ack_line(dsnoop_ack_line[gi]), .flush_error()
            );
        end
    endgenerate

    // ------------------------------------------------------
    // External memory model for coherence_manager's CPU Memory Port:
    // simple 1-cycle latency (address sampled this edge, response
    // the next), zero-initialized, 1MB. The larger range lets the test
    // use addresses separated by one L2 way-size (0x20000) to force a
    // true same-set L2 eviction without aliasing in the memory model.
    // ------------------------------------------------------
    reg [31:0] mem [0:262143];
    integer mi;
    initial for (mi = 0; mi < 262144; mi = mi + 1) mem[mi] = 32'h0;

    wire        mem_req_valid;
    wire        mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;
    reg         mem_valid;
    integer dram_read_words;
    integer dram_write_words;

    always @(posedge clk) begin
        if (rst) begin
            mem_valid <= 1'b0;
            dram_read_words  <= 0;
            dram_write_words <= 0;
        end
        else begin
            mem_valid <= mem_req_valid;
            if (mem_req_valid) begin
                if (mem_we) begin
                    mem[mem_addr[19:2]] <= mem_wdata;
                    dram_write_words <= dram_write_words + 1;
                end
                else begin
                    mem_rdata <= mem[mem_addr[19:2]];
                    dram_read_words <= dram_read_words + 1;
                end
            end
        end
    end

    // ------------------------------------------------------
    // DUT
    // ------------------------------------------------------
    cache_controller_mmu #(.DEBUG_TRACE_ENABLE(1)) u_cm (
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

        .mem_req_valid(mem_req_valid), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata), .mem_valid(mem_valid), .mem_error(1'b0),
        .perf_total_requests(perf_total_requests), .perf_d_bus_reads(perf_d_bus_reads),
        .perf_d_rfos(perf_d_rfos), .perf_d_writebacks(perf_d_writebacks),
        .perf_i_reads(perf_i_reads), .perf_l2_hits(perf_l2_hits), .perf_l2_misses(perf_l2_misses),
        .perf_snoop_requests(perf_snoop_requests), .perf_mem_read_words(perf_mem_read_words),
        .perf_mem_write_words(perf_mem_write_words), .perf_busy_cycles(perf_busy_cycles),
        .protocol_error(protocol_error), .timeout_error(timeout_error), .memory_error(memory_error),
        .debug_trace_rd_index(debug_trace_rd_index), .debug_trace_rd_data(debug_trace_rd_data),
        .debug_trace_count(debug_trace_count), .debug_trace_write_index(debug_trace_write_index),
        .debug_controller_state(debug_controller_state),
        .l2_cmd_valid_o(l2_cmd_valid), .l2_cmd_we_o(l2_cmd_we),
        .l2_cmd_addr_o(l2_cmd_addr), .l2_cmd_way_o(l2_cmd_way),
        .l2_cmd_wdata_o(l2_cmd_wdata), .l2_cmd_w_valid_o(l2_cmd_w_valid),
        .l2_cmd_w_dirty_o(l2_cmd_w_dirty), .l2_cmd_w_sharers_o(l2_cmd_w_sharers),
        .l2_resp_valid_i(l2_resp_valid), .l2_resp_hit_i(l2_resp_hit),
        .l2_resp_way_i(l2_resp_way), .l2_resp_victim_tag_i(l2_resp_victim_tag),
        .l2_resp_victim_valid_i(l2_resp_victim_valid),
        .l2_resp_victim_dirty_i(l2_resp_victim_dirty),
        .l2_resp_victim_sharers_i(l2_resp_victim_sharers),
        .l2_resp_line_i(l2_resp_line), .l2_resp_sharers_i(l2_resp_sharers)
    );

    l2_cache u_shared_l2 (
        .clk(clk), .rst(rst),
        .cmd_valid(l2_cmd_valid), .cmd_we(l2_cmd_we),
        .cmd_addr(l2_cmd_addr), .cmd_way(l2_cmd_way),
        .cmd_wdata(l2_cmd_wdata), .cmd_w_valid(l2_cmd_w_valid),
        .cmd_w_dirty(l2_cmd_w_dirty), .cmd_w_sharers(l2_cmd_w_sharers),
        .resp_valid(l2_resp_valid), .resp_hit(l2_resp_hit),
        .resp_way(l2_resp_way), .resp_victim_tag(l2_resp_victim_tag),
        .resp_victim_valid(l2_resp_victim_valid),
        .resp_victim_dirty(l2_resp_victim_dirty),
        .resp_victim_sharers(l2_resp_victim_sharers),
        .resp_line(l2_resp_line), .resp_sharers(l2_resp_sharers)
    );

    // ------------------------------------------------------
    // Transaction monitor. L1 valid is level-held until response, so
    // count only its rising edge. Also reject the removed MESI E state.
    // ------------------------------------------------------
    reg prev_dreq_valid [0:3];
    integer busrd_count;
    integer rfo_count;
    integer wb_count;
    integer e_grant_count;
    integer mon_i;
    always @(posedge clk) begin
        if (rst) begin
            busrd_count  <= 0;
            rfo_count    <= 0;
            wb_count     <= 0;
            e_grant_count <= 0;
            for (mon_i = 0; mon_i < 4; mon_i = mon_i + 1)
                prev_dreq_valid[mon_i] <= 1'b0;
        end
        else begin
            for (mon_i = 0; mon_i < 4; mon_i = mon_i + 1) begin
                if (dreq_valid[mon_i] && !prev_dreq_valid[mon_i]) begin
                    case (dreq_type[mon_i])
                        2'b00: busrd_count <= busrd_count + 1;
                        2'b01: rfo_count   <= rfo_count + 1;
                        2'b10: wb_count    <= wb_count + 1;
                    endcase
                end
                if (dresp_valid[mon_i] && dresp_state[mon_i] == 2'b10)
                    e_grant_count <= e_grant_count + 1;
                prev_dreq_valid[mon_i] <= dreq_valid[mon_i];
            end
        end
    end

    // ------------------------------------------------------
    // Test sequencing tasks
    // ------------------------------------------------------
    integer errors;
    integer k;

    task automatic do_read(input integer core, input [31:0] addr, output [31:0] data);
        begin
            // Drive away from the DUT sampling edge.  This avoids an
            // active-region race that different simulators may order
            // differently when the request is asserted/deasserted at posedge.
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

    task automatic do_read_op(input integer core, input [31:0] addr,
                              input [2:0] memop, output [31:0] data);
        begin
            @(negedge clk);
            c_addr[core]  = addr;
            c_we[core]    = 1'b0;
            c_re[core]    = 1'b1;
            c_memop[core] = memop;
            @(posedge clk); #1;
            while (!c_valid[core]) begin
                @(posedge clk); #1;
            end
            data = c_rdata[core];
            @(negedge clk);
            c_re[core]    = 1'b0;
            c_memop[core] = 3'b010;
        end
    endtask

    task automatic do_write_op(input integer core, input [31:0] addr,
                               input [31:0] wdata, input [2:0] memop);
        begin
            @(negedge clk);
            c_addr[core]  = addr;
            c_wdata[core] = wdata;
            c_we[core]    = 1'b1;
            c_re[core]    = 1'b0;
            c_memop[core] = memop;
            @(posedge clk); #1;
            while (!c_valid[core]) begin
                @(posedge clk); #1;
            end
            @(negedge clk);
            c_we[core]    = 1'b0;
            c_memop[core] = 3'b010;
        end
    endtask

    task automatic do_amo(input integer core, input [31:0] addr,
                          input [4:0] amo_op, input [31:0] operand,
                          output [31:0] old_value);
        begin
            @(negedge clk);
            c_addr[core]        = addr;
            c_we[core]          = 1'b1;
            c_re[core]          = 1'b1;
            c_memop[core]       = 3'b010;
            c_amo[core]         = 1'b1;
            c_amo_op[core]      = amo_op;
            c_amo_operand[core] = operand;
            #1;
            if (c_valid[core]) begin
                // An M hit exposes the pre-RMW word combinationally.  Save
                // it before the following edge commits the new value.
                old_value = c_rdata[core];
                @(posedge clk);
                #1;
            end
            else begin
                // A cold miss or S->M upgrade completes on a response edge;
                // miss_done_pulse selects the saved pre-RMW word afterwards.
                while (!c_valid[core]) begin
                    @(posedge clk);
                    #1;
                end
                old_value = c_rdata[core];
            end
            c_we[core]          = 1'b0;
            c_re[core]          = 1'b0;
            c_amo[core]         = 1'b0;
            c_amo_op[core]      = 5'b0;
            c_amo_operand[core] = 32'b0;
            @(posedge clk);
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
            else begin
                $display("[PASS] %0s", name);
            end
        end
    endtask

    reg [31:0] rd;
    integer snap_rfo;
    integer snap_reads;
    integer snap_writes;
    integer snap_wb;
    integer rr_start;
    integer rr_first;
    integer resp_order [0:3];
    integer resp_count;
    reg [31:0] rr_rd0, rr_rd1, rr_rd2, rr_rd3;
    reg [31:0] stress_model [0:63];
    reg [31:0] stress_lfsr;
    reg [31:0] stress_value;
    integer stress_i;
    integer stress_core;
    integer stress_word;
    integer stress_failures;

    initial begin
        errors = 0;
        debug_trace_rd_index = 4'b0;
        rst = 1'b1;
        for (k = 0; k < 4; k = k + 1) begin
            c_addr[k] = 32'b0; c_wdata[k] = 32'b0; c_we[k] = 1'b0; c_re[k] = 1'b0;
            c_flush[k] = 1'b0; c_memop[k] = 3'b010;
            c_amo[k] = 1'b0; c_amo_op[k] = 5'b0; c_amo_operand[k] = 32'b0;
        end
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        $display("---------------------------------------------");
        $display("MSI A: cold BusRd must grant S");
        do_read(0, LINE_ADDR, rd);
        check_eq32("A: core0 initial read", rd, 32'h0000_0000);

        $display("MSI B: S write must issue RFO before entering M");
        snap_rfo = rfo_count;
        do_write(0, LINE_ADDR, 32'hAAAA_0001);
        check_true("B: S->M generated exactly one RFO", rfo_count == snap_rfo + 1);

        $display("MSI C: BusRd snoops M, forwards new data, M->S, no DRAM read");
        snap_reads = dram_read_words;
        do_read(1, LINE_ADDR, rd);
        check_eq32("C: core1 sees core0's dirty write", rd, 32'hAAAA_0001);
        check_true("C: value came from owner/L2 without DRAM", dram_read_words == snap_reads);
        do_read(0, LINE_ADDR, rd);
        check_eq32("C: downgraded core0 still reads shared value", rd, 32'hAAAA_0001);

        $display("MSI D: four readers, then one writer invalidates all sharers");
        do_read(0, FOUR_ADDR, rd);
        do_read(1, FOUR_ADDR, rd);
        do_read(2, FOUR_ADDR, rd);
        do_read(3, FOUR_ADDR, rd);
        snap_rfo = rfo_count;
        do_write(2, FOUR_ADDR, 32'hBBBB_0002);
        check_true("D: shared writer generated one RFO", rfo_count == snap_rfo + 1);
        do_read(0, FOUR_ADDR, rd);
        check_eq32("D: core0 re-fetches writer value", rd, 32'hBBBB_0002);
        do_read(1, FOUR_ADDR, rd);
        check_eq32("D: core1 re-fetches writer value", rd, 32'hBBBB_0002);
        do_read(3, FOUR_ADDR, rd);
        check_eq32("D: core3 re-fetches writer value", rd, 32'hBBBB_0002);

        $display("MSI E: false sharing preserves both words in one line");
        do_write(0, FALSE_ADDR,     32'h1111_AAAA);
        do_write(1, FALSE_ADDR + 4, 32'h2222_BBBB);
        do_read(2, FALSE_ADDR, rd);
        check_eq32("E: word 0 survives ownership transfer", rd, 32'h1111_AAAA);
        do_read(2, FALSE_ADDR + 4, rd);
        check_eq32("E: word 1 written by new owner", rd, 32'h2222_BBBB);

        $display("MSI F: dirty L1 eviction writes L2; consumer must not access DRAM");
        do_write(0, L1_EVICT0,               32'hCAFE_0000);
        do_write(0, L1_EVICT0 + 32'h00004000, 32'hCAFE_0001);
        do_write(0, L1_EVICT0 + 32'h00008000, 32'hCAFE_0002);
        check_true("F: conflicting third line caused an L1 writeback", wb_count > 0);
        snap_reads = dram_read_words;
        do_read(1, L1_EVICT0, rd);
        check_eq32("F: consumer sees L1-evicted value from L2", rd, 32'hCAFE_0000);
        check_true("F: L2 hit avoided DRAM", dram_read_words == snap_reads);

        $display("MSI G: inclusive dirty L2 eviction snoops victim and writes DRAM");
        do_write(0, L2_EVICT0 + 32'h00000000, 32'hD000_0000);
        do_write(1, L2_EVICT0 + 32'h00020000, 32'hD111_1111);
        do_write(2, L2_EVICT0 + 32'h00040000, 32'hD222_2222);
        do_write(3, L2_EVICT0 + 32'h00060000, 32'hD333_3333);
        snap_writes = dram_write_words;
        do_write(0, L2_EVICT0 + 32'h00080000, 32'hD444_4444);
        check_true("G: fifth same-set line wrote dirty victim to DRAM", dram_write_words == snap_writes + 8);
        do_read(1, L2_EVICT0, rd);
        check_eq32("G: evicted dirty victim is recoverable from DRAM", rd, 32'hD000_0000);

        $display("MSI H: whole-cache flush writes back M lines before invalidation");
        do_write(0, 32'h0000_5000, 32'hF1E5_0001);
        snap_wb = wb_count;
        @(negedge clk);
        c_flush[0] = 1'b1;
        @(negedge clk);
        c_flush[0] = 1'b0;
        wait (c_flush_busy[0]);
        wait (c_flush_done[0]);
        @(posedge clk);
        check_true("H: flush emitted writeback for dirty data", wb_count > snap_wb);
        snap_reads = dram_read_words;
        do_read(1, 32'h0000_5000, rd);
        check_eq32("H: another core sees flushed value", rd, 32'hF1E5_0001);
        check_true("H: flushed value was recovered from L2", dram_read_words == snap_reads);

        $display("MSI I: simultaneous misses are served in round-robin order");
        rr_start = u_cm.u_protocol_engine.rr_next;
        rr_first = (rr_start < 4) ? rr_start : 0;
        resp_count = 0;
        fork
            do_read(0, 32'h0001_0000, rr_rd0);
            do_read(1, 32'h0001_1000, rr_rd1);
            do_read(2, 32'h0001_2000, rr_rd2);
            do_read(3, 32'h0001_3000, rr_rd3);
            begin
                while (resp_count < 4) begin
                    @(posedge clk);
                    if (dresp_valid[0]) begin resp_order[resp_count] = 0; resp_count = resp_count + 1; end
                    if (dresp_valid[1]) begin resp_order[resp_count] = 1; resp_count = resp_count + 1; end
                    if (dresp_valid[2]) begin resp_order[resp_count] = 2; resp_count = resp_count + 1; end
                    if (dresp_valid[3]) begin resp_order[resp_count] = 3; resp_count = resp_count + 1; end
                end
            end
        join
        check_true("I: first grant follows saved round-robin pointer",
                   resp_order[0] == rr_first);
        check_true("I: all four grants rotate without starvation",
                   (resp_order[1] == ((rr_first + 1) % 4)) &&
                   (resp_order[2] == ((rr_first + 2) % 4)) &&
                   (resp_order[3] == ((rr_first + 3) % 4)));

        $display("MSI J: byte/halfword merge and signed/unsigned loads");
        do_write(0, 32'h0001_5000, 32'h1122_3344);
        do_write_op(0, 32'h0001_5001, 32'h0000_00AA, 3'b000); // SB
        do_write_op(0, 32'h0001_5002, 32'h0000_80FF, 3'b001); // SH
        do_read(0, 32'h0001_5000, rd);
        check_eq32("J: SB/SH preserve untouched lanes", rd, 32'h80FF_AA44);
        do_read_op(0, 32'h0001_5001, 3'b000, rd); // LB
        check_eq32("J: LB sign extends", rd, 32'hFFFF_FFAA);
        do_read_op(0, 32'h0001_5001, 3'b100, rd); // LBU
        check_eq32("J: LBU zero extends", rd, 32'h0000_00AA);
        do_read_op(0, 32'h0001_5002, 3'b001, rd); // LH
        check_eq32("J: LH sign extends", rd, 32'hFFFF_80FF);
        do_read_op(0, 32'h0001_5002, 3'b101, rd); // LHU
        check_eq32("J: LHU zero extends", rd, 32'h0000_80FF);

        $display("MSI K: cached AMO RMW is correct on cold miss, M hit and S upgrade");
        mem[32'h0001_8000 >> 2] = 32'd10;
        do_amo(0, 32'h0001_8000, 5'b00000, 32'd5, rd); // AMOADD
        check_eq32("K: cold AMOADD returns old filled value", rd, 32'd10);
        do_amo(0, 32'h0001_8000, 5'b00001, 32'h0000_00F0, rd); // SWAP
        check_eq32("K: AMOSWAP returns prior M value", rd, 32'd15);
        do_amo(0, 32'h0001_8000, 5'b00100, 32'h0000_000F, rd); // XOR
        check_eq32("K: AMOXOR returns prior value", rd, 32'h0000_00F0);
        do_amo(0, 32'h0001_8000, 5'b01000, 32'h0000_0100, rd); // OR
        check_eq32("K: AMOOR returns prior value", rd, 32'h0000_00FF);
        do_amo(0, 32'h0001_8000, 5'b01100, 32'h0000_001F, rd); // AND
        check_eq32("K: AMOAND returns prior value", rd, 32'h0000_01FF);
        do_amo(0, 32'h0001_8000, 5'b10000, 32'hFFFF_FFF0, rd); // MIN
        check_eq32("K: AMOMIN returns prior value", rd, 32'h0000_001F);
        do_amo(0, 32'h0001_8000, 5'b10100, 32'h0000_0002, rd); // MAX
        check_eq32("K: AMOMAX returns signed-negative prior", rd, 32'hFFFF_FFF0);
        do_amo(0, 32'h0001_8000, 5'b11000, 32'h0000_0001, rd); // MINU
        check_eq32("K: AMOMINU returns prior value", rd, 32'h0000_0002);
        do_amo(0, 32'h0001_8000, 5'b11100, 32'hFFFF_FFFF, rd); // MAXU
        check_eq32("K: AMOMAXU returns prior value", rd, 32'h0000_0001);
        do_read(1, 32'h0001_8000, rd); // force M->S, core1 now S
        check_eq32("K: another core observes final AMO value", rd, 32'hFFFF_FFFF);
        do_amo(1, 32'h0001_8000, 5'b00001, 32'h1234_5678, rd); // S->M SWAP
        check_eq32("K: shared AMO upgrade returns old value", rd, 32'hFFFF_FFFF);
        do_read(0, 32'h0001_8000, rd);
        check_eq32("K: AMO upgrade publishes new value", rd, 32'h1234_5678);
        do_amo(0, 32'h0001_800C, 5'b00001, 32'hDEAD_BEEF, rd); // word 3
        check_eq32("K: nonzero-word AMO returns its own old lane", rd, 32'h0000_0000);
        do_read(1, 32'h0001_800C, rd);
        check_eq32("K: nonzero-word AMO updates the selected lane", rd, 32'hDEAD_BEEF);
        do_read(1, 32'h0001_8000, rd);
        check_eq32("K: nonzero-word AMO preserves neighboring lane", rd, 32'h1234_5678);

        $display("MSI L: deterministic randomized ownership/flush stress");
        stress_lfsr = 32'h1ACE_B00C;
        stress_failures = 0;
        for (stress_i = 0; stress_i < 64; stress_i = stress_i + 1)
            stress_model[stress_i] = 32'b0;

        // Long, reproducible sequence across eight lines. Writes force
        // ownership migration between all four cores; reads compare the
        // externally visible value against a transaction-level scoreboard.
        // Periodic private-cache flushes exercise dirty writeback and stale
        // directory pruning in the middle of the sequence.
        for (stress_i = 0; stress_i < 160; stress_i = stress_i + 1) begin
            stress_lfsr = {stress_lfsr[30:0],
                           stress_lfsr[31] ^ stress_lfsr[21] ^
                           stress_lfsr[1] ^ stress_lfsr[0]};
            stress_core = stress_lfsr[1:0];
            stress_word = stress_lfsr[7:2];
            if (stress_lfsr[8]) begin
                stress_value = 32'h5A00_0000 ^ (stress_i << 8) ^
                               (stress_core << 4) ^ stress_word;
                do_write(stress_core, 32'h0003_0000 + (stress_word << 2),
                         stress_value);
                stress_model[stress_word] = stress_value;
            end
            else begin
                do_read(stress_core, 32'h0003_0000 + (stress_word << 2), rd);
                if (rd !== stress_model[stress_word]) begin
                    $display("[FAIL] L: stress op=%0d core=%0d word=%0d got=0x%08h expected=0x%08h",
                             stress_i, stress_core, stress_word, rd,
                             stress_model[stress_word]);
                    stress_failures = stress_failures + 1;
                    errors = errors + 1;
                end
            end

            if ((stress_i % 23) == 22) begin
                @(negedge clk);
                c_flush[stress_core] = 1'b1;
                @(negedge clk);
                c_flush[stress_core] = 1'b0;
                wait (c_flush_busy[stress_core]);
                wait (c_flush_done[stress_core]);
                @(posedge clk);
            end
        end

        // Force final ownership transfers from a different core for every
        // word so no dirty value can remain hidden in its last writer.
        for (stress_i = 0; stress_i < 64; stress_i = stress_i + 1) begin
            stress_core = (stress_i + 1) % 4;
            do_read(stress_core, 32'h0003_0000 + (stress_i << 2), rd);
            if (rd !== stress_model[stress_i]) begin
                $display("[FAIL] L: final stress word=%0d got=0x%08h expected=0x%08h",
                         stress_i, rd, stress_model[stress_i]);
                stress_failures = stress_failures + 1;
                errors = errors + 1;
            end
        end
        check_true("L: randomized MSI scoreboard stayed coherent",
                   stress_failures == 0);

        check_true("M: CM performance counters observed all D requests",
                   perf_total_requests == (perf_d_bus_reads + perf_d_rfos + perf_d_writebacks));
        check_true("M: CM observed both L2 hits and misses",
                   (perf_l2_hits != 0) && (perf_l2_misses != 0));
        check_true("M: CM protocol checker stayed clean", !protocol_error);
        check_true("M: CM handshake watchdog stayed clean", !timeout_error);
        check_true("M: CM external-memory error flag stayed clean", !memory_error);
        check_true("M: optional CM trace buffer captured events", debug_trace_count != 0);

        check_true("MSI never granted removed Exclusive state", e_grant_count == 0);

        $display("---------------------------------------------");
        if (errors == 0) begin
            $display("MSI_COHERENCE_TB: PASS");
        end
        else begin
            $display("MSI_COHERENCE_TB: FAIL (%0d check(s) failed)", errors);
        end
        $display("---------------------------------------------");
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 60000);
        $display("MSI_COHERENCE_TB: FAIL (global timeout -- dump coherence FSM waves)");
        $finish;
    end

endmodule
