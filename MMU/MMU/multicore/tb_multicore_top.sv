`timescale 1ps / 1ps
//
// tb_multicore_top: Phase-2 self-checking testbench. 4 independent
// core_top instances (see multicore_top.sv) each run a small standalone
// program, plus a genuine cross-core coherence dependency between core 0
// (producer) and core 1 (consumer) via a spin-flag in shared memory:
//
//   core0 @ 0x0000:
//     x1 = 100 ; store to 0x200            (own result)
//     x2 = 999 ; store to 0x100            (SHARED_DATA)
//     x3 = 1   ; store to 0x104            (SHARED_FLAG, published last)
//     halt
//
//   core1 @ 0x1000:
//     WAIT: x5 = load 0x104 (SHARED_FLAG)
//           if (x5 == 0) goto WAIT
//     x6 = load 0x100 (SHARED_DATA)        -- must observe core0's 999
//     store x6 to 0x300                    (observed value, for checking)
//     x1 = 110 ; store to 0x204            (own result)
//     halt
//
//   core2 @ 0x2000: x1 = 120 ; store to 0x208 ; halt
//   core3 @ 0x3000: x1 = 130 ; store to 0x20C ; halt
//
// If core1's private D-cache ever serves a *stale* cached copy of
// SHARED_FLAG (i.e. if the interconnect's snoop-invalidate coherence
// broadcast is broken), core1 spins forever on its first (0-valued)
// read and the testbench times out. If write-through-to-L2 is broken,
// core1 will eventually see the flag but read stale (0, not 999) shared
// data. Both failure modes are distinguished in the pass/fail report.
//
// All values are checked by peeking directly into the shared L2's data
// array (not DRAM): with only a handful of lines touched and 8192 sets
// available, none of them are ever evicted, so DRAM never actually gets
// written in this test — L2 is the source of truth to check against.
//
module tb_multicore_top;

    reg clk = 0;
    reg rst_n = 0;
    always #5000 clk = ~clk;

    wire [31:0] dbg_pc           [0:3];
    wire [31:0] dbg_instr        [0:3];
    wire        dbg_instr_retire [0:3];

    multicore_top #(.NUM_CORES(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr), .dbg_instr_retire(dbg_instr_retire)
    );

    // ------------------------------------------------------------------
    // Program images
    // ------------------------------------------------------------------
    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);
        // Land on a negedge (a later time step than the posedges above)
        // before preloading. mem_model256's reset-clear loop is
        // triggered by posedge clk while rst_n==0 and uses NONBLOCKING
        // writes; if preload_word's blocking writes happened in the same
        // simulation step as one of those posedges, simulator process
        // ordering between the two independent `always`/`initial` blocks
        // isn't guaranteed, and the reset-clear's NBA updates can land
        // *after* the preload and silently wipe the whole program back
        // to zero (this is exactly what caused every core to run off
        // into "instructions" that were all-zero NOPs instead of their
        // real program). Waiting for a negedge here guarantees we're
        // safely past that posedge's NBA settling before we write.
        @(negedge clk);

        // NOTE on addresses: D_CacheController.sv (inherited, not new in
        // Phase 2) selects its within-line slot using only cpu_addr[4:3]
        // (8-byte granularity) and always places a 32-bit word in the
        // LOW 32 bits of that slot — cpu_addr[2] is never consulted. Two
        // 32-bit addresses only 4 bytes apart (e.g. 0x100 and 0x104)
        // therefore alias to the exact same storage and would silently
        // clobber each other. Every address below is spaced >=16 bytes
        // apart specifically to avoid tripping this pre-existing bug;
        // see README_PHASE1.md / the Phase-2 notes for the real fix
        // (widen the D-cache's offset to cpu_addr[4:2] and patch at
        // 32-bit granularity instead of 64-bit).

        // CORE 0 @ 0x0000
        dut.u_dram.preload_word(32'h0000, 32'h06400093); // addi x1,x0,100
        dut.u_dram.preload_word(32'h0004, 32'h20102023); // sw   x1,0x200(x0)         own result
        dut.u_dram.preload_word(32'h0008, 32'h3E700113); // addi x2,x0,999
        dut.u_dram.preload_word(32'h000C, 32'h10202023); // sw   x2,0x100(x0)         SHARED_DATA
        dut.u_dram.preload_word(32'h0010, 32'h00100193); // addi x3,x0,1
        dut.u_dram.preload_word(32'h0014, 32'h10302823); // sw   x3,0x110(x0)         SHARED_FLAG
        dut.u_dram.preload_word(32'h0018, 32'h00000063); // beq  x0,x0,0 (halt)

        // CORE 1 @ 0x1000
        dut.u_dram.preload_word(32'h1000, 32'h11002283); // WAIT: lw x5,0x110(x0)     SHARED_FLAG
        dut.u_dram.preload_word(32'h1004, 32'hFE028EE3); // beq  x5,x0,WAIT (offset -4)
        dut.u_dram.preload_word(32'h1008, 32'h10002303); // lw   x6,0x100(x0)         SHARED_DATA
        dut.u_dram.preload_word(32'h100C, 32'h24602023); // sw   x6,0x240(x0)         observed value
        dut.u_dram.preload_word(32'h1010, 32'h06E00093); // addi x1,x0,110
        dut.u_dram.preload_word(32'h1014, 32'h20102823); // sw   x1,0x210(x0)         own result
        dut.u_dram.preload_word(32'h1018, 32'h00000063); // beq  x0,x0,0 (halt)

        // CORE 2 @ 0x2000
        dut.u_dram.preload_word(32'h2000, 32'h07800093); // addi x1,x0,120
        dut.u_dram.preload_word(32'h2004, 32'h22102023); // sw   x1,0x220(x0)         own result
        dut.u_dram.preload_word(32'h2008, 32'h00000063); // beq  x0,x0,0 (halt)

        // CORE 3 @ 0x3000
        dut.u_dram.preload_word(32'h3000, 32'h08200093); // addi x1,x0,130
        dut.u_dram.preload_word(32'h3004, 32'h22102823); // sw   x1,0x230(x0)         own result
        dut.u_dram.preload_word(32'h3008, 32'h00000063); // beq  x0,x0,0 (halt)

        // (No longer need a defensive zero-preload of SHARED_FLAG here:
        // mem_model256 now zero-initializes all of DRAM on reset. The
        // old preload call also used the wrong bit-layout convention for
        // a data word — see mem_model.sv's preload_word doc comment.)

        // Release reset immediately, still within this same negedge time
        // step and strictly before the next posedge clk — so that by the
        // time that next posedge arrives, rst_n is already 1 and
        // mem_model256 takes the normal (non-clearing) branch.
        rst_n = 1;
    end

    // ------------------------------------------------------------------
    // TEMP DEBUG: trace core 0's PC / branch decision every time it's
    // AT or NEAR its halt address (0x18), to see exactly why the
    // beq x0,x0,0 self-loop isn't holding. Hierarchical references into
    // core_top's own internal wires (pc_sel, branch_taken, alu_result,
    // pc) — no RTL changes needed. Capped at 40 lines so it can't run
    // away for the full 400us if the bug turns out to be "never gets
    // there at all."
    // ------------------------------------------------------------------
    integer dbg_lines = 0;
    integer dbg_lines2 = 0;
    always @(posedge clk) begin
        if (rst_n && dbg_lines < 30 && |dut.u_interconnect.snoop_en) begin
            $display("t=%0t SNOOP BROADCAST en=%b addr=%08h",
                $time, dut.u_interconnect.snoop_en, dut.u_interconnect.snoop_addr);
            dbg_lines = dbg_lines + 1;
        end
        if (rst_n && dbg_lines2 < 40 &&
            (dut.CORE[1].u_core.pc == 32'h1000 || dut.CORE[1].u_core.pc == 32'h1004) &&
            dut.CORE[1].u_core.instr_done) begin
            $display("t=%0t CORE1 pc=%08h instr=%08h x5=%08h retire=%b d_rdy=%b needs_mem=%b",
                $time, dut.CORE[1].u_core.pc, dut.CORE[1].u_core.instr,
                dut.CORE[1].u_core.u_decode.register_file_inst.reg_file[5],
                dut.CORE[1].u_core.instr_done, dut.CORE[1].u_core.d_cpu_ready,
                dut.CORE[1].u_core.needs_mem);
            dbg_lines2 = dbg_lines2 + 1;
        end
    end

    // ------------------------------------------------------------------
    // Halt detection: each core loops on its own `beq x0,x0,0` at a
    // known address. Declare done once every core has retired that
    // instruction twice in a row.
    // ------------------------------------------------------------------
    localparam [31:0] HALT_ADDR [0:3] = '{32'h0018, 32'h1018, 32'h2008, 32'h3008};
    integer halt_hits [0:3];
    integer c;

    initial begin
        for (c = 0; c < 4; c = c + 1) halt_hits[c] = 0;
    end

    always @(posedge clk) begin
        for (c = 0; c < 4; c = c + 1) begin
            if (rst_n && dbg_instr_retire[c] && dbg_pc[c] == HALT_ADDR[c] && halt_hits[c] < 2) begin
                halt_hits[c] = halt_hits[c] + 1;
            end
        end
    end

    function automatic bit all_halted;
        integer j;
        begin
            all_halted = 1'b1;
            for (j = 0; j < 4; j = j + 1) begin
                if (halt_hits[j] < 2) all_halted = 1'b0;
            end
        end
    endfunction

    // ------------------------------------------------------------------
    // L2 peek helper: reads a 32-bit word directly out of the shared
    // L2's tag/data arrays (see multicore/L2_TagArray.sv,
    // multicore/L2_DataArray.sv for the storage layout being poked).
    //
    // Offset math matches D_CacheController.sv's actual (inherited,
    // addr[2]-blind) convention: a 32-bit store lands in the LOW 32 bits
    // of the 64-bit slot selected by addr[4:3] — not in an addr[4:2]-
    // indexed 32-bit slot as you'd naively expect. See the address
    // spacing note in the preload block above.
    // ------------------------------------------------------------------
    function automatic [31:0] l2_peek32(input [31:0] addr);
        integer index, slot64, way;
        reg [13:0] tag;
        reg found;
        reg [255:0] line;
        begin
            index  = addr[17:5];
            tag    = addr[31:18];
            slot64 = addr[4:3];
            found  = 1'b0;
            line   = 256'hX;
            for (way = 0; way < 2; way = way + 1) begin
                if (!found && dut.u_l2.tag_array.valid[index][way] &&
                    dut.u_l2.tag_array.tags[index][way] == tag) begin
                    line  = dut.u_l2.data_array.data[index][way];
                    found = 1'b1;
                end
            end
            if (!found) begin
                $display("  [WARN] l2_peek32(0x%08h): line not found in L2 (index=%0d, tag=0x%04h)", addr, index, tag);
                l2_peek32 = 32'hDEAD_BEEF;
            end else begin
                l2_peek32 = line[(223 - 64*slot64) -: 32];
            end
        end
    endfunction

    task automatic check_mem(input [31:0] addr, input [31:0] expected, input string name);
        reg [31:0] actual;
        begin
            actual = l2_peek32(addr);
            if (actual !== expected) begin
                $display("  [FAIL] %s (0x%08h): expected 0x%08h, got 0x%08h", name, addr, expected, actual);
                errors = errors + 1;
            end else begin
                $display("  [ OK ] %s (0x%08h): 0x%08h", name, addr, actual);
            end
        end
    endtask

    integer errors;
    initial begin
        errors = 0;
        wait (rst_n == 1'b1);

        while (!all_halted()) @(posedge clk);

        // Give any in-flight write-through / snoop traffic a few extra
        // cycles to fully settle before peeking.
        repeat (20) @(posedge clk);

        check_mem(32'h0200, 32'd100, "core0 own result");
        check_mem(32'h0100, 32'd999, "SHARED_DATA (core0 write)");
        check_mem(32'h0110, 32'd1,   "SHARED_FLAG (core0 publish)");
        check_mem(32'h0240, 32'd999, "core1 observed SHARED_DATA (coherence!)");
        check_mem(32'h0210, 32'd110, "core1 own result");
        check_mem(32'h0220, 32'd120, "core2 own result");
        check_mem(32'h0230, 32'd130, "core3 own result");

        if (errors == 0) begin
            $display("PHASE2 TEST: PASS - 4-core system + interconnect + shared L2 + coherence verified.");
        end else begin
            $display("PHASE2 TEST: FAIL - %0d mismatch(es), see log above.", errors);
        end
        $finish;
    end

    // Safety timeout — if core1 is stuck spinning because coherence is
    // broken (stale SHARED_FLAG never invalidated), this is what fires.
    initial begin
        #400_000_000; // 400 us
        $display("PHASE2 TEST: FAIL - simulation timeout. halt_hits = %0d %0d %0d %0d (need 2 each).",
            halt_hits[0], halt_hits[1], halt_hits[2], halt_hits[3]);
        $display("  If core1 is stuck, check the coherence snoop path (interconnect.sv -> TagArray.sv snoop port).");
        $finish;
    end

endmodule
