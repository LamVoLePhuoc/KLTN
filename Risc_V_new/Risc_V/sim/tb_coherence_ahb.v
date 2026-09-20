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
// 5-step MESI scenario (steps A-E, same addresses, same expected
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
// transparent -- the same MESI invariant tb_coherence.v already
// checks (mandatory snoop of a lone sharer) has to keep holding with
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

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : DCACHES
            l1_dcache u_dc (
                .clk(clk), .rst(rst), .flush(1'b0),
                .cpu_addr(c_addr[gi]), .cpu_wdata(c_wdata[gi]),
                .cpu_we(c_we[gi]), .cpu_re(c_re[gi]), .cpu_memop(c_memop[gi]),
                .cpu_rdata(c_rdata[gi]), .cpu_valid(c_valid[gi]),
                .bus_req_valid(bus_req_valid[gi]), .bus_req_type(bus_req_type[gi]),
                .bus_req_addr(bus_req_addr[gi]), .bus_req_line(bus_req_line[gi]),
                .bus_resp_valid(bus_resp_valid[gi]), .bus_resp_line(bus_resp_line[gi]), .bus_resp_state(bus_resp_state[gi]),
                .snoop_valid(dsnoop_valid[gi]), .snoop_type(dsnoop_type[gi]), .snoop_addr(dsnoop_addr[gi]),
                .snoop_ack_valid(dsnoop_ack_valid[gi]), .snoop_ack_hit(dsnoop_ack_hit[gi]),
                .snoop_ack_dirty(dsnoop_ack_dirty[gi]), .snoop_ack_line(dsnoop_ack_line[gi])
            );

            ahb_lite_l1_adapter u_ahb_m (
                .HCLK(clk), .HRESETn(HRESETn),
                .bus_req_valid(bus_req_valid[gi]), .bus_req_type(bus_req_type[gi]),
                .bus_req_addr(bus_req_addr[gi]), .bus_req_line(bus_req_line[gi]),
                .bus_resp_valid(bus_resp_valid[gi]), .bus_resp_line(bus_resp_line[gi]), .bus_resp_state(bus_resp_state[gi]),
                .HADDR(haddr[gi]), .HWRITE(hwrite[gi]), .HSIZE(), .HTRANS(htrans[gi]),
                .HWDATA(hwdata[gi]), .HBURST(), .HPROT(), .HMASTLOCK(),
                .HRDATA(hrdata[gi]), .HREADY(hready[gi]), .HRESP(hresp[gi])
            );

            ahb_lite_l1_slave_adapter u_ahb_s (
                .HCLK(clk), .HRESETn(HRESETn),
                .HADDR(haddr[gi]), .HWRITE(hwrite[gi]), .HTRANS(htrans[gi]), .HWDATA(hwdata[gi]),
                .HREADYOUT(hready[gi]), .HRDATA(hrdata[gi]), .HRESP(hresp[gi]),
                .dreq_valid(dreq_valid[gi]), .dreq_type(dreq_type[gi]),
                .dreq_addr(dreq_addr[gi]), .dreq_line(dreq_line[gi]),
                .dresp_valid(dresp_valid[gi]), .dresp_line(dresp_line[gi]), .dresp_state(dresp_state[gi])
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
    // Bus-traffic monitor -- identical purpose to tb_coherence.v's
    // (catch step B's E->M upgrade accidentally reaching the bus), now
    // watching the PRE-bridge bus_req_valid[0] (the point closest to
    // the cache itself -- if the upgrade stayed local, NOTHING past
    // this point, AHB-Lite included, should ever see traffic for it).
    // ------------------------------------------------------
    reg monitor_core0_bus;
    integer core0_bus_events;
    always @(posedge clk) begin
        if (rst) core0_bus_events <= 0;
        else if (monitor_core0_bus && bus_req_valid[0]) core0_bus_events <= core0_bus_events + 1;
    end

    // ------------------------------------------------------
    // Test sequencing tasks -- identical to tb_coherence.v.
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
        $display("tb_coherence_ahb: step A -- core0 cold read (expect 0, grant E), through AHB-Lite bridge");
        do_read(0, LINE_ADDR, rd);
        check_eq32("A: core0 initial read", rd, 32'h0000_0000);

        $display("tb_coherence_ahb: step B -- core0 local write (E->M, no bridge/bus traffic expected)");
        monitor_core0_bus = 1'b1;
        core0_bus_events  = 0;
        do_write(0, LINE_ADDR, 32'hAAAA_0001);
        monitor_core0_bus = 1'b0;
        if (core0_bus_events != 0) begin
            $display("[FAIL] B: core0's E->M write reached the AHB-Lite bridge %0d time(s) -- should be silent/local", core0_bus_events);
            errors = errors + 1;
        end
        else begin
            $display("[PASS] B: core0's E->M write stayed local (no bridge/bus traffic)");
        end

        $display("tb_coherence_ahb: step C -- core1 read (must catch core0's silent M via mandatory snoop)");
        do_read(1, LINE_ADDR, rd);
        check_eq32("C: core1 sees core0's dirty write", rd, 32'hAAAA_0001);

        $display("tb_coherence_ahb: step D -- core2 RFO write (must invalidate core0 AND core1)");
        do_write(2, LINE_ADDR, 32'hBBBB_0002);
        do_read(0, LINE_ADDR, rd); // core0 must miss now (was invalidated) and re-fetch
        check_eq32("D: core0 re-read after being invalidated by core2's RFO", rd, 32'hBBBB_0002);

        $display("tb_coherence_ahb: step E -- re-check core1 also invalidated, core2's data is authoritative");
        do_read(1, LINE_ADDR, rd);
        check_eq32("E: core1 re-read after being invalidated by core2's RFO", rd, 32'hBBBB_0002);

        $display("---------------------------------------------");
        if (errors == 0) begin
            $display("COHERENCE_AHB_TB: PASS");
        end
        else begin
            $display("COHERENCE_AHB_TB: FAIL (%0d check(s) failed)", errors);
        end
        $display("---------------------------------------------");
        $finish;
    end

    // Larger timeout than tb_coherence.v's -- see header: every
    // transaction now takes 8 sequential AHB-Lite word transfers
    // instead of tb_coherence.v's direct ~1-cycle-per-word protocol.
    initial begin
        #(CLK_PERIOD * 40000);
        $display("COHERENCE_AHB_TB: FAIL (global timeout -- likely a hang in the AHB-Lite bridge or coherence_manager's FSM; dump waves)");
        $finish;
    end

endmodule
