`timescale 1ns / 1ps

// ============================================================
// tb_mmu_core
//
// Self-checking testbench for mmu_core_wrapper (= mmu_top: iTLB +
// dTLB + shared 2-level PTW, wrapped around one RV32IMA core), per
// Risc_V_new/address_mapping:
//   VA(32b) = VPN[1](10b) | VPN[0](10b) | Offset(12b)
//   2-level page table, Sv32-style PTE flags {D,A,G,U,X,W,R,V}
//
// This is a single-core, standalone harness -- it does NOT touch
// RV32IMA_DualCore_Wrapper.v / RV32IMA_DualCore_BoardTop.v (both
// already synthesized/implemented for hardware; see the Vivado
// .runs/ artifacts). It exists purely to answer the question "does
// the MMU RTL that already exists in rtl/ actually work", since
// nothing in the repo instantiated or exercised mmu_core_wrapper
// before this file.
//
// Memory map built by this testbench (all in one flat behavioral
// RAM, word-addressed, shared by fetch / data / PTW traffic exactly
// like RV32IMA_DualCore_BoardTop.v's `ram` model):
//
//   PA 0x0000            : L1 (root) page table, 1024 x 4B  (only entry 0 used)
//   PA 0x1000            : L0 page table, 1024 x 4B
//     entry[1] (VA 0x1000) -> PA 0x2000, R+X        (code page)
//     entry[2] (VA 0x2000) -> PA 0x3000, R+W        (writable data page)
//     entry[3] (VA 0x3000) -> left invalid (V=0)    (not-present fault test)
//     entry[4] (VA 0x4000) -> PA 0x4000, R only     (permission fault test)
//   PA 0x2000            : test program (13 instructions)
//   PA 0x3000            : scratch data page
//   PA 0x4000             : scratch RO page, pre-loaded with a sentinel
//
// Test program (assembled by hand below; see the header comment on
// each `ram[...] = ...` line for the disassembly):
//   1. Computes x3 = 5 + 10 = 15.
//   2. Stores x3 to VA 0x2000 (mapped, writable) and loads it back
//      into x4 -- proves the data-side translate+walk path and a
//      plain hit/miss round trip.
//   3. Stores to VA 0x4000 (mapped read-only) -- must fault, and the
//      store must NOT reach memory (PTW catches this during the
//      walk itself, since the request's is_store bit is checked
//      against the PTE's W bit before ever refilling the TLB).
//   4. Loads from VA 0x4000 -- must succeed (R=1) and return the
//      untouched sentinel, proving check 3 really did block the
//      write.
//   5. Loads from VA 0x3000 (entry[3], invalid PTE) -- must fault
//      with not-present and return 0.
//   6. Self-loop (`beq x0,x0,0`) so the testbench can just run for a
//      fixed number of cycles and then inspect final state.
//
// Register file is read back via hierarchical reference (simulation
// only -- this is not synthesizable and is not meant to be):
//   dut.core.decode_unit.rf.Register[n]
// (mmu_core_wrapper's inner RV32IMA instance is named "core";
// RV32IMA's decode_stage instance is "decode_unit"; decode_stage's
// Register_File instance is "rf"; Register_File.v's storage array is
// `Register[31:1]`.) If any of those instance names ever change,
// this hierarchical path needs updating to match.
//
// How to run (Vivado XSIM):
//   Add as simulation sources: everything in rtl/ (mmu_*.v included)
//   plus this file. Set tb_mmu_core as the simulation top. Run
//   Behavioral Simulation, `run -all` in the Tcl console. Watch for
//   "MMU_TB: PASS" or "MMU_TB: FAIL" plus one PASS/FAIL line per
//   check.
// ============================================================
module tb_mmu_core;

    localparam CLK_PERIOD = 10;
    localparam RAM_WORDS  = 16384; // 64KB, word-addressed by addr[15:2]

    reg clk;
    reg rst;

    // ------------------------------------------------------
    // DUT ports
    // ------------------------------------------------------
    reg         Stall_Core_External;
    reg         Mmu_Enable;
    reg  [19:0] Satp_PPN;
    reg         Mmu_Flush;
    reg  [31:0] Snoop_Addr;
    reg         Snoop_WE;

    wire [31:0] PCF;
    wire [31:0] InstrF;

    wire [31:0] Mem_AddrM;
    wire [31:0] Mem_WriteDataM;
    wire        Mem_WriteEnM;
    wire        Mem_ReadEnM;
    wire [2:0]  MemOpM;
    wire [31:0] Mem_ReadDataM;

    wire [31:0] ResultW;
    wire [31:0] ALU_ResultE_Debug;

    wire        Fetch_PageFault;
    wire        Data_PageFault;
    wire [1:0]  Fetch_PageFault_Cause;
    wire [1:0]  Data_PageFault_Cause;

    // ------------------------------------------------------
    // Behavioral RAM: program + page tables + data, all in one
    // flat physical space, exactly like BoardTop's `ram` model
    // (combinational read, synchronous write, word granularity
    // only -- every access in this test is a full SW/LW word op
    // or a PTW word read, so byte lanes are not needed here).
    // ------------------------------------------------------
    reg [31:0] ram [0:RAM_WORDS-1];
    integer i;

    assign InstrF        = ram[PCF[15:2]];
    assign Mem_ReadDataM = ram[Mem_AddrM[15:2]];

    always @(posedge clk) begin
        if (Mem_WriteEnM) begin
            ram[Mem_AddrM[15:2]] <= Mem_WriteDataM;
        end
    end

    // ------------------------------------------------------
    // DUT
    // ------------------------------------------------------
    mmu_core_wrapper #(
        .RESET_ADDR(32'h0000_1000)
    ) dut (
        .clk                (clk),
        .rst                (rst),
        .Stall_Core_External(Stall_Core_External),

        .Mmu_Enable         (Mmu_Enable),
        .Satp_PPN           (Satp_PPN),
        .Mmu_Flush          (Mmu_Flush),

        .Snoop_Addr         (Snoop_Addr),
        .Snoop_WE           (Snoop_WE),

        .PCF                (PCF),
        .InstrF             (InstrF),

        .Mem_AddrM          (Mem_AddrM),
        .Mem_WriteDataM     (Mem_WriteDataM),
        .Mem_WriteEnM       (Mem_WriteEnM),
        .Mem_ReadEnM        (Mem_ReadEnM),
        .MemOpM             (MemOpM),
        .Mem_ReadDataM      (Mem_ReadDataM),

        .ResultW            (ResultW),
        .ALU_ResultE_Debug  (ALU_ResultE_Debug),

        .Fetch_PageFault       (Fetch_PageFault),
        .Data_PageFault        (Data_PageFault),
        .Fetch_PageFault_Cause (Fetch_PageFault_Cause),
        .Data_PageFault_Cause  (Data_PageFault_Cause)
    );

    // ------------------------------------------------------
    // Clock
    // ------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------
    // Page-fault pulse counters (for checks 3 and 5)
    // ------------------------------------------------------
    integer data_fault_count;
    integer fetch_fault_count;

    always @(posedge clk) begin
        if (rst) begin
            data_fault_count  <= 0;
            fetch_fault_count <= 0;
        end
        else begin
            if (Data_PageFault)  data_fault_count  <= data_fault_count  + 1;
            if (Fetch_PageFault) fetch_fault_count <= fetch_fault_count + 1;
        end
    end

    // ------------------------------------------------------
    // Memory / page-table image
    // ------------------------------------------------------
    initial begin
        for (i = 0; i < RAM_WORDS; i = i + 1) begin
            ram[i] = 32'h0000_0000;
        end

        // --- L1 (root) page table @ PA 0x0000 ---
        // entry[0] (VPN[1]=0, covers all VA < 0x0040_0000): pointer
        // to the L0 table @ PA 0x1000. Flags = V=1,R=0,W=0,X=0 (0x1).
        ram[32'h0000_0000 >> 2] = 32'h0000_1001;

        // --- L0 page table @ PA 0x1000 ---
        // entry[1] (VA 0x1000-0x1FFF) -> PA 0x2000, V+R+X (0xB)
        ram[32'h0000_1004 >> 2] = 32'h0000_200B;
        // entry[2] (VA 0x2000-0x2FFF) -> PA 0x3000, V+R+W (0x7)
        ram[32'h0000_1008 >> 2] = 32'h0000_3007;
        // entry[3] (VA 0x3000-0x3FFF) -> left 0 (not present)
        // entry[4] (VA 0x4000-0x4FFF) -> PA 0x4000, V+R only (0x3)
        ram[32'h0000_1010 >> 2] = 32'h0000_4003;

        // --- Test program @ PA 0x2000 (= VA 0x1000 translated) ---
        ram[32'h0000_2000 >> 2] = 32'h0050_0093; // addi x1, x0, 5
        ram[32'h0000_2004 >> 2] = 32'h00A0_0113; // addi x2, x0, 10
        ram[32'h0000_2008 >> 2] = 32'h0020_81B3; // add  x3, x1, x2      -> x3=15
        ram[32'h0000_200C >> 2] = 32'h0000_22B7; // lui  x5, 0x2         -> x5=0x2000
        ram[32'h0000_2010 >> 2] = 32'h0032_A023; // sw   x3, 0(x5)       -> VA 0x2000 <= 15
        ram[32'h0000_2014 >> 2] = 32'h0002_A203; // lw   x4, 0(x5)       -> x4 <= mem[VA 0x2000]
        ram[32'h0000_2018 >> 2] = 32'h0000_4337; // lui  x6, 0x4         -> x6=0x4000
        ram[32'h0000_201C >> 2] = 32'h0630_0393; // addi x7, x0, 99
        ram[32'h0000_2020 >> 2] = 32'h0073_2023; // sw   x7, 0(x6)       -> RO page: must fault, must NOT write
        ram[32'h0000_2024 >> 2] = 32'h0003_2403; // lw   x8, 0(x6)       -> x8 <= mem[VA 0x4000] (sentinel, R ok)
        ram[32'h0000_2028 >> 2] = 32'h0000_34B7; // lui  x9, 0x3         -> x9=0x3000
        ram[32'h0000_202C >> 2] = 32'h0004_A503; // lw   x10, 0(x9)      -> not-present: must fault, x10 <= 0
        ram[32'h0000_2030 >> 2] = 32'h0000_0063; // beq  x0, x0, 0       -> self-loop (halt)

        // --- Scratch RO page @ PA 0x4000, pre-loaded sentinel ---
        ram[32'h0000_4000 >> 2] = 32'hDEAD_BEEF;
    end

    // ------------------------------------------------------
    // Stimulus + checks
    // ------------------------------------------------------
    integer errors;

    task check_eq32(input [8*48-1:0] name, input [31:0] got, input [31:0] exp);
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

    initial begin
        errors               = 0;
        rst                  = 1'b1;
        Stall_Core_External  = 1'b0;
        Mmu_Enable           = 1'b1;
        Satp_PPN             = 20'h0_0000; // root table at PA 0x0000 -> PPN 0
        Mmu_Flush            = 1'b0;
        Snoop_Addr           = 32'b0;
        Snoop_WE             = 1'b0;

        repeat (5) @(posedge clk);
        rst = 1'b0;

        // Generous cycle budget: iTLB/dTLB miss -> PTW walk is two
        // sequential word reads (~a handful of cycles) per miss, and
        // this program takes at most one walk per unique page (5
        // distinct pages touched) plus the retry after the RO-store
        // walk-time fault. 2000 cycles is a large margin over that.
        repeat (2000) @(posedge clk);

        $display("---------------------------------------------");
        $display("MMU_TB checks");
        $display("---------------------------------------------");

        check_eq32("x1 (addi)",                dut.core.decode_unit.rf.Register[1],  32'd5);
        check_eq32("x2 (addi)",                dut.core.decode_unit.rf.Register[2],  32'd10);
        check_eq32("x3 (add)",                 dut.core.decode_unit.rf.Register[3],  32'd15);
        check_eq32("x4 (load back after store)", dut.core.decode_unit.rf.Register[4], 32'd15);
        check_eq32("x5 (lui 0x2)",             dut.core.decode_unit.rf.Register[5],  32'h0000_2000);
        check_eq32("x6 (lui 0x4)",             dut.core.decode_unit.rf.Register[6],  32'h0000_4000);
        check_eq32("x7 (addi 99)",             dut.core.decode_unit.rf.Register[7],  32'd99);
        check_eq32("x8 (RO load, sentinel intact)", dut.core.decode_unit.rf.Register[8], 32'hDEAD_BEEF);
        check_eq32("x9 (lui 0x3)",             dut.core.decode_unit.rf.Register[9],  32'h0000_3000);
        check_eq32("x10 (not-present fault -> 0)", dut.core.decode_unit.rf.Register[10], 32'd0);

        check_eq32("PA 0x4000 unchanged by blocked RO store", ram[32'h0000_4000 >> 2], 32'hDEAD_BEEF);

        if (data_fault_count < 2) begin
            $display("[FAIL] Data_PageFault pulse count: got=%0d expected>=2 (RO store + not-present load)", data_fault_count);
            errors = errors + 1;
        end
        else begin
            $display("[PASS] Data_PageFault pulsed %0d times", data_fault_count);
        end

        if (fetch_fault_count != 0) begin
            $display("[FAIL] Fetch_PageFault pulse count: got=%0d expected=0 (every fetch in this test is mapped)", fetch_fault_count);
            errors = errors + 1;
        end
        else begin
            $display("[PASS] Fetch_PageFault never pulsed (all fetches were mapped, as expected)");
        end

        $display("---------------------------------------------");
        if (errors == 0) begin
            $display("MMU_TB: PASS");
        end
        else begin
            $display("MMU_TB: FAIL (%0d check(s) failed)", errors);
        end
        $display("---------------------------------------------");

        $finish;
    end

    // Safety net in case the core never reaches the self-loop.
    initial begin
        #(CLK_PERIOD * 5000);
        $display("MMU_TB: FAIL (global timeout -- core did not settle; dump waves and check the PTW/TLB FSMs)");
        $finish;
    end

endmodule
