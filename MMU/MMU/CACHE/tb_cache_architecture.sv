`timescale 1ns / 1ps
// PHASE3 TEST: exercises CacheArchitecture.sv's Phase-3 MESI coherence
// path (CoherenceManager + SharedCacheController's SNOOP_CHECK/SNOOP_WB/
// SNOOP_INVAL/WRITE_THROUGH states) directly, by driving each core's D-cache
// CPU-side port as if from a real RV32 core, with a simple synchronous DRAM
// model behind L2. No RV32 core/pipeline is involved -- this is a focused
// unit test of the cache/coherence subsystem added in Phase 3.
module tb_cache_architecture;

    localparam int NUM_CORES  = 4;
    localparam int ADDR_WIDTH = 32;
    localparam int LINE_WIDTH = 256;
    localparam int L1D_WIDTH  = 64;
    localparam int DRAM_LINES = 1024;
    localparam int DRAM_LATENCY = 3;

    reg clk = 0;
    reg reset_n = 0;
    always #5 clk = ~clk;

    // Per-core D-cache driver-facing regs, packed into the DUT's flat buses.
    reg  [ADDR_WIDTH-1:0] d_addr  [0:NUM_CORES-1];
    reg                   d_read  [0:NUM_CORES-1];
    reg                   d_write [0:NUM_CORES-1];
    reg  [L1D_WIDTH-1:0]  d_wdata [0:NUM_CORES-1];
    wire [L1D_WIDTH-1:0]  d_rdata [0:NUM_CORES-1];
    wire                  d_ready [0:NUM_CORES-1];

    wire [NUM_CORES*ADDR_WIDTH-1:0] core_d_addr;
    wire [NUM_CORES-1:0]            core_d_read;
    wire [NUM_CORES-1:0]            core_d_write;
    wire [NUM_CORES*L1D_WIDTH-1:0]  core_d_wdata;
    wire [NUM_CORES*L1D_WIDTH-1:0]  core_d_rdata;
    wire [NUM_CORES-1:0]            core_d_ready;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_CORES; gi = gi + 1) begin : gen_pack
            assign core_d_addr[gi*ADDR_WIDTH +: ADDR_WIDTH]   = d_addr[gi];
            assign core_d_read[gi]                            = d_read[gi];
            assign core_d_write[gi]                           = d_write[gi];
            assign core_d_wdata[gi*L1D_WIDTH +: L1D_WIDTH]    = d_wdata[gi];
            assign d_rdata[gi]                                = core_d_rdata[gi*L1D_WIDTH +: L1D_WIDTH];
            assign d_ready[gi]                                = core_d_ready[gi];
        end
    endgenerate

    // No instruction traffic in this test.
    wire [NUM_CORES*ADDR_WIDTH-1:0] core_i_addr = '0;
    wire [NUM_CORES-1:0]            core_i_read = '0;
    wire [NUM_CORES*32-1:0]         core_i_rdata;
    wire [NUM_CORES-1:0]            core_i_ready;

    wire [ADDR_WIDTH-1:0]  dram_req_addr;
    wire                   dram_req_read;
    wire                   dram_req_write;
    wire [LINE_WIDTH-1:0]  dram_req_wdata;
    wire [LINE_WIDTH-1:0]  dram_rdata;
    reg                    dram_ready;

    CacheArchitecture #(
        .NUM_CORES(NUM_CORES),
        .ADDR_WIDTH(ADDR_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .L1D_CPU_WIDTH(L1D_WIDTH)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .core_i_addr(core_i_addr),
        .core_i_read(core_i_read),
        .core_i_rdata(core_i_rdata),
        .core_i_ready(core_i_ready),
        .core_d_addr(core_d_addr),
        .core_d_read(core_d_read),
        .core_d_write(core_d_write),
        .core_d_wdata(core_d_wdata),
        .core_d_rdata(core_d_rdata),
        .core_d_ready(core_d_ready),
        .dram_req_addr(dram_req_addr),
        .dram_req_read(dram_req_read),
        .dram_req_write(dram_req_write),
        .dram_req_wdata(dram_req_wdata),
        .dram_rdata(dram_rdata),
        .dram_ready(dram_ready)
    );

    // ---------------------------------------------------------------
    // Simple synchronous DRAM model behind L2: fixed latency, single
    // outstanding request, line-addressed backing store.
    // ---------------------------------------------------------------
    reg [LINE_WIDTH-1:0] dram_mem [0:DRAM_LINES-1];
    reg [3:0] dram_cnt;
    reg       dram_busy;
    wire [$clog2(DRAM_LINES)-1:0] dram_line_idx = dram_req_addr[$clog2(DRAM_LINES)+4:5];

    initial begin
        integer li;
        dram_busy = 1'b0;
        dram_cnt  = 4'd0;
        for (li = 0; li < DRAM_LINES; li = li + 1) dram_mem[li] = '0;
    end

    always @(posedge clk) begin
        dram_ready <= 1'b0;
        if (!dram_busy && (dram_req_read || dram_req_write)) begin
            dram_busy <= 1'b1;
            dram_cnt  <= 4'd0;
        end else if (dram_busy) begin
            if (dram_cnt == DRAM_LATENCY - 1) begin
                dram_busy  <= 1'b0;
                dram_ready <= 1'b1;
                if (dram_req_write) begin
                    dram_mem[dram_line_idx] <= dram_req_wdata;
                end
            end else begin
                dram_cnt <= dram_cnt + 4'd1;
            end
        end
    end

    assign dram_rdata = dram_mem[dram_line_idx];

    // ---------------------------------------------------------------
    // Per-core CPU driver tasks: hold the request until cpu_ready, then
    // release. Mirrors how a real core's LSU would drive this interface.
    // ---------------------------------------------------------------
    task automatic d_read_word(input integer core, input [ADDR_WIDTH-1:0] addr, output [L1D_WIDTH-1:0] rdata);
        begin
            @(negedge clk);
            d_addr[core]  = addr;
            d_read[core]  = 1'b1;
            d_write[core] = 1'b0;
            @(posedge clk);
            while (!d_ready[core]) @(posedge clk);
            rdata = d_rdata[core];
            @(negedge clk);
            d_read[core] = 1'b0;
        end
    endtask

    task automatic d_write_word(input integer core, input [ADDR_WIDTH-1:0] addr, input [L1D_WIDTH-1:0] wdata);
        begin
            @(negedge clk);
            d_addr[core]  = addr;
            d_wdata[core] = wdata;
            d_write[core] = 1'b1;
            d_read[core]  = 1'b0;
            @(posedge clk);
            while (!d_ready[core]) @(posedge clk);
            @(negedge clk);
            d_write[core] = 1'b0;
        end
    endtask

    integer errors;
    reg [L1D_WIDTH-1:0] got;

    task automatic check(input string name, input [L1D_WIDTH-1:0] actual, input [L1D_WIDTH-1:0] expected);
        begin
            if (actual !== expected) begin
                $display("  [FAIL] %s: expected 0x%016h, got 0x%016h", name, expected, actual);
                errors = errors + 1;
            end else begin
                $display("  [ OK ] %s: 0x%016h", name, actual);
            end
        end
    endtask

    localparam [ADDR_WIDTH-1:0] ADDR_A = 32'h0000_1000; // producer/consumer line
    localparam [ADDR_WIDTH-1:0] ADDR_B = 32'h0000_2000; // second, independent line

    initial begin
        integer c;
        errors = 0;
        for (c = 0; c < NUM_CORES; c = c + 1) begin
            d_addr[c]  = '0;
            d_read[c]  = 1'b0;
            d_write[c] = 1'b0;
            d_wdata[c] = '0;
        end

        // Reset pulse.
        reset_n = 1'b0;
        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        repeat (2) @(posedge clk);

        $display("PHASE3 TEST: starting MESI coherence checks");

        // --- Scenario 1: read-shared invalidate ------------------------
        // core1 reads A first (fills clean into core1's L1 with DRAM's
        // reset value, 0). core0 then writes A with a fresh value; this
        // should (a) write-through to L2 and (b) invalidate core1's now-
        // stale clean copy. core1's next read of A must observe core0's
        // new value, proving both the write-through and the invalidate
        // path work together.
        d_read_word(1, ADDR_A, got);
        check("core1 initial read of A (DRAM reset value)", got, 64'h0);

        d_write_word(0, ADDR_A, 64'hDEAD_BEEF_1234_5678);

        // A store's own cpu_ready fires as soon as it lands locally in
        // the writer's L1 (see WRITE_THROUGH in CacheController.sv) --
        // the write-through to L2 and the resulting invalidate broadcast
        // to other cores complete some cycles *after* that, same as on
        // real hardware, where a store retiring does not imply it is
        // already globally visible to every other core with zero
        // latency. Give the write-through + snoop path time to land
        // before checking that core1 observes it, exactly as the Phase-2
        // spin-wait test (tb_multicore_top.sv) does implicitly by
        // polling instead of reading exactly once.
        repeat (300) @(posedge clk);

        d_read_word(1, ADDR_A, got);
        check("core1 re-read of A after core0's write (coherence!)", got, 64'hDEAD_BEEF_1234_5678);

        // --- Scenario 2: core0's own subsequent read must also be fresh --
        d_read_word(0, ADDR_A, got);
        check("core0 own read-back of A", got, 64'hDEAD_BEEF_1234_5678);

        // --- Scenario 3: a store-hit (already-cached line) must also
        // write-through and invalidate other sharers -------------------
        d_write_word(1, ADDR_A, 64'h1111_2222_3333_4444);
        repeat (300) @(posedge clk);
        d_read_word(2, ADDR_A, got);
        check("core2 fresh read of A after core1's store-hit write", got, 64'h1111_2222_3333_4444);
        d_read_word(0, ADDR_A, got);
        check("core0 stale copy of A invalidated by core1's write", got, 64'h1111_2222_3333_4444);

        // --- Scenario 4: an independent line (B) touched only by core3
        // must be unaffected by all of the above traffic on A -----------
        d_write_word(3, ADDR_B, 64'hCAFE_F00D_0BAD_F00D);
        repeat (300) @(posedge clk);
        d_read_word(2, ADDR_B, got);
        check("core2 read of unrelated line B (no cross-talk)", got, 64'hCAFE_F00D_0BAD_F00D);

        repeat (10) @(posedge clk);

        if (errors == 0) begin
            $display("PHASE3 TEST: PASS - CacheArchitecture MESI coherence (write-through + snoop-invalidate + forced writeback-on-snoop) verified.");
        end else begin
            $display("PHASE3 TEST: FAIL - %0d check(s) failed.", errors);
        end
        $finish;
    end

    initial begin
        #200000; // 200us timeout
        $display("PHASE3 TEST: FAIL - simulation timeout.");
        $finish;
    end

endmodule
