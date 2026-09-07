`timescale 1ps / 1ps
//
// tb_core_top: Phase-1 self-checking testbench for the single-core RV32I
// integration (core_top.sv = decode+execute+write_back+pc_unit+MMU).
//
// Program under test (see comments below for the hand-assembled machine
// code): exercises ADDI, ADD (R-type), SW, LW, BEQ (taken), JAL, JALR,
// and confirms that instructions on the not-taken/skipped side of a
// branch/jump never execute. Ends in a self-loop (BEQ x0,x0,0) that the
// testbench detects to stop the run.
//
// How to run in Vivado:
//   1. Add all files in RV32/source/*.v, RV32/source/*.sv, and
//      ../../{MMU.sv,I_Cache.sv,D_Cache.sv,I_CacheController.sv,
//      D_CacheController.sv,TagArray.sv,DataArray.sv,Comparator.sv} as
//      simulation (or design, doesn't matter for behavioral sim) sources.
//   2. Set tb_core_top as the simulation top.
//   3. Run Behavioral Simulation; watch the Tcl console for
//      "PHASE1 TEST: PASS" / "PHASE1 TEST: FAIL".
//
module tb_core_top;

    reg clk = 0;
    reg rst_n = 0;

    always #5000 clk = ~clk; // 100 MHz-equivalent period in the 1ps timescale

    wire [31:0]  i_mem_req_addr, d_mem_req_addr;
    wire         i_mem_req_read, i_mem_req_write, d_mem_req_read, d_mem_req_write;
    wire [255:0] i_mem_req_wdata, d_mem_req_wdata;
    wire [255:0] i_mem_rdata, d_mem_rdata;
    wire         i_mem_ready, d_mem_ready;

    wire [31:0] dbg_pc, dbg_instr;
    wire        dbg_instr_retire;
    wire        dbg_i_cpu_ready, dbg_d_cpu_ready, dbg_needs_mem, dbg_mem_read, dbg_mem_write;

    core_top dut (
        .clk(clk), .rst_n(rst_n),
        .i_mem_req_addr(i_mem_req_addr), .i_mem_req_read(i_mem_req_read),
        .i_mem_req_write(i_mem_req_write), .i_mem_req_wdata(i_mem_req_wdata),
        .i_mem_rdata(i_mem_rdata), .i_mem_ready(i_mem_ready),
        .d_mem_req_addr(d_mem_req_addr), .d_mem_req_read(d_mem_req_read),
        .d_mem_req_write(d_mem_req_write), .d_mem_req_wdata(d_mem_req_wdata),
        .d_mem_rdata(d_mem_rdata), .d_mem_ready(d_mem_ready),
        .snoop_en(1'b0), .snoop_addr(32'b0), // Phase 1 = single core, no coherence traffic
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr), .dbg_instr_retire(dbg_instr_retire),
        .dbg_i_cpu_ready(dbg_i_cpu_ready), .dbg_d_cpu_ready(dbg_d_cpu_ready),
        .dbg_needs_mem(dbg_needs_mem), .dbg_mem_read(dbg_mem_read), .dbg_mem_write(dbg_mem_write)
    );

    mem_model256 #(.LINES(256), .LAT_CYCLES(2)) imem (
        .clk(clk), .rst_n(rst_n),
        .mem_req_addr(i_mem_req_addr), .mem_req_read(i_mem_req_read),
        .mem_req_write(i_mem_req_write), .mem_req_wdata(i_mem_req_wdata),
        .mem_rdata(i_mem_rdata), .mem_ready(i_mem_ready)
    );

    mem_model256 #(.LINES(256), .LAT_CYCLES(2)) dmem (
        .clk(clk), .rst_n(rst_n),
        .mem_req_addr(d_mem_req_addr), .mem_req_read(d_mem_req_read),
        .mem_req_write(d_mem_req_write), .mem_req_wdata(d_mem_req_wdata),
        .mem_rdata(d_mem_rdata), .mem_ready(d_mem_ready)
    );

    // ------------------------------------------------------------------
    // Debug trace: prints one line whenever an instruction retires
    // (dbg_instr_retire), plus a periodic heartbeat so a stuck core is
    // visible even if it never retires anything. Capped so it can't spam
    // the log forever on a real hang.
    // ------------------------------------------------------------------
    integer trace_lines = 0;
    always @(posedge clk) begin
        if (rst_n && trace_lines < 400) begin
            if (dbg_instr_retire || (($time % 100000) == 0)) begin
                $display("t=%0t pc=%08h instr=%08h retire=%0d i_rdy=%0d d_rdy=%0d need_mem=%0d rd=%0d wr=%0d",
                    $time, dbg_pc, dbg_instr, dbg_instr_retire,
                    dbg_i_cpu_ready, dbg_d_cpu_ready, dbg_needs_mem, dbg_mem_read, dbg_mem_write);
                trace_lines = trace_lines + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Program image (see README_PHASE1.md for the assembly listing this
    // was hand-encoded from).
    // ------------------------------------------------------------------
    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);

        imem.preload_word(32'h00, 32'h00A00093); // addi x1, x0, 10
        imem.preload_word(32'h04, 32'h01400113); // addi x2, x0, 20
        imem.preload_word(32'h08, 32'h002081B3); // add  x3, x1, x2
        imem.preload_word(32'h0C, 32'h00302023); // sw   x3, 0(x0)
        imem.preload_word(32'h10, 32'h00002203); // lw   x4, 0(x0)
        imem.preload_word(32'h14, 32'h00418463); // beq  x3, x4, 0x1C  (taken)
        imem.preload_word(32'h18, 32'h3E700293); // addi x5, x0, 999   [must be SKIPPED]
        imem.preload_word(32'h1C, 32'h0080036F); // jal  x6, 0x24
        imem.preload_word(32'h20, 32'h37800393); // addi x7, x0, 888   [must be SKIPPED]
        imem.preload_word(32'h24, 32'h02A00413); // addi x8, x0, 42
        imem.preload_word(32'h28, 32'h030004E7); // jalr x9, x0, 0x30
        imem.preload_word(32'h2C, 32'h06F00513); // addi x10, x0, 111  [must be SKIPPED]
        imem.preload_word(32'h30, 32'h03700593); // addi x11, x0, 55
        imem.preload_word(32'h34, 32'h00000063); // beq  x0, x0, 0     (halt self-loop)

        @(negedge clk);
        rst_n = 1;
    end

    // ------------------------------------------------------------------
    // Run until the core is spinning on the halt self-loop at 0x34, then
    // check architectural state.
    // ------------------------------------------------------------------
    integer errors;
    integer halt_hits;
    initial begin
        errors    = 0;
        halt_hits = 0;
        wait (rst_n == 1'b1);

        // Wait until PC==0x34 retires twice in a row (proof it's looping,
        // not just passing through).
        while (halt_hits < 2) begin
            @(posedge clk);
            if (dbg_instr_retire && dbg_pc == 32'h34) begin
                halt_hits = halt_hits + 1;
            end
        end

        check_reg(1, 32'd10,  "x1 (addi)");
        check_reg(2, 32'd20,  "x2 (addi)");
        check_reg(3, 32'd30,  "x3 (add)");
        check_reg(4, 32'd30,  "x4 (lw after sw)");
        check_reg(5, 32'd0,   "x5 (must be skipped by beq)");
        check_reg(6, 32'h20,  "x6 (jal link addr)");
        check_reg(7, 32'd0,   "x7 (must be skipped by jal)");
        check_reg(8, 32'd42,  "x8 (jal target)");
        check_reg(9, 32'h2C,  "x9 (jalr link addr)");
        check_reg(10, 32'd0,  "x10 (must be skipped by jalr)");
        check_reg(11, 32'd55, "x11 (jalr target)");

        if (errors == 0) begin
            $display("PHASE1 TEST: PASS - RV32I core_top + MMU (L0/L1) verified.");
        end else begin
            $display("PHASE1 TEST: FAIL - %0d mismatch(es), see log above.", errors);
        end
        $finish;
    end

    task automatic check_reg(input integer idx, input [31:0] expected, input string name);
        reg [31:0] actual;
        begin
            actual = dut.u_decode.register_file_inst.reg_file[idx];
            if (actual !== expected) begin
                $display("  [FAIL] %s: expected 0x%08h, got 0x%08h", name, expected, actual);
                errors = errors + 1;
            end else begin
                $display("  [ OK ] %s: 0x%08h", name, actual);
            end
        end
    endtask

    // Safety timeout in case something hangs. Kept under the 32-bit delay
    // literal limit (Verilog `#` delays are a 32-bit constant in this
    // 1ps timescale, so anything above ~2.14e9 silently wraps — Vivado
    // will warn and truncate it, as it did with the previous value here).
    initial begin
        #200_000_000; // 200,000 ns = 200 us — the program needs a few us at most
        $display("PHASE1 TEST: FAIL - simulation timeout, core never reached halt loop.");
        $finish;
    end

endmodule
