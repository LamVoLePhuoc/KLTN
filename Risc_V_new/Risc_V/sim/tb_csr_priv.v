`timescale 1ns / 1ps

// ============================================================
// tb_csr_priv
//
// Extends what tb_csr_trap.v covers (CSR read/write, ECALL/EBREAK/
// illegal-instruction trapping, MRET, PC redirect) with the two
// things that testbench explicitly does NOT exercise (see its own
// header): a REAL M/S/U privilege drop/raise sequence, and `medeleg`
// trap delegation to S-mode. This is "Direction 1" from
// Risc_V_new/README.md mục -0.25/mục 7 (Phase 9) -- the MMU-page-
// fault-actually-traps half of that direction is covered separately
// by the now-fixed sim/tb_mmu_core.v (see its own updated header),
// not here: that needs mmu_core_wrapper as the DUT, this file
// deliberately does not (same reasoning as tb_csr_trap.v -- keep the
// privilege/delegation state machine hand-traceable without an MMU
// walk also in flight).
//
// Same DUT choice as tb_csr_trap.v (raw RV32IMA, not through
// mmu_core_wrapper) and same reasoning: csr_trap_unit.v lives inside
// RV32IMA.v itself, so privilege transitions and delegation need no
// MMU in the loop. Fetch_PageFault_In/Data_PageFault_In tied low
// throughout.
//
// Full privilege narrative exercised (6 real transitions, verified
// two independent ways -- see "Checks" below):
//   M (reset) --MRET(mstatus.MPP=S)--> S --SRET(sstatus.SPP=U)--> U
//     --ECALL, medeleg[8]=1--> S (delegated: scause/sepc/stvec used,
//     NOT mcause/mepc/mtvec)
//     --SRET--> U
//     --EBREAK, medeleg[3]=0--> M (NOT delegated, even though priv
//     was U at fault time -- proves delegation is selective per
//     cause, not "any non-M trap goes to S")
//     --MRET--> U (final; self-loop halts here)
//
// Register/CSR assembly notes (real bugs caught by hand-tracing
// before ever running this, same discipline as tb_csr_trap.v's own
// Phase 7b forwarding bug -- see Risc_V_new/README.md):
//   - mstatus.MPP lives at bits[12:11]. The natural-looking
//     `ADDI x28, x0, 0x800` to build that bit pattern is WRONG: ADDI's
//     12-bit immediate is sign-extended, and 0x800 has ITS OWN bit 11
//     set (the immediate field's sign bit), so the instruction would
//     actually load x28 = 0xFFFFF800, not 0x00000800 -- which would
//     have set MPP to "11" (M) instead of "01" (S), silently sending
//     the first MRET back to M instead of dropping to S. Fixed by
//     building the value as `ADDI x28,x0,1` (safe, small, positive)
//     then `SLLI x28,x28,11` (shift operates on the register's actual
//     32-bit value, not a re-interpreted signed immediate -- no
//     sign-extension pitfall).
//   - Every plain marker constant used below is kept <= 0x7FF (2047)
//     for the same reason -- an earlier draft used 0x999 as the final
//     marker, which has the same problem (bit 11 set) and would have
//     landed x8 = 0xFFFFF999 instead of 0x00000999. Changed to 0x666.
//   - CSR *addresses* (mtvec=0x305, medeleg=0x302, mstatus=0x300,
//     mepc=0x341, stvec=0x105, sepc=0x141, scause=0x142, sstatus=0x100,
//     mcause=0x342) are placed directly into instr[31:20] and read
//     back out the same way by csr_trap_unit.v (CsrAddrM = InstrM[31:20],
//     a plain unsigned field extraction) -- they never pass through
//     the sign-extending immediate-generation datapath at all, so
//     none of them are at risk of the ADDI pitfall above regardless
//     of which bits happen to be set.
//
// Privilege-gated CSR access as a SECOND, independent correctness
// signal (beyond just "did the marker register get written"): S_handler
// reads `scause` (an S-min CSR, address bits[9:8]=01) and M_handler
// reads `mcause` (an M-min CSR, bits[9:8]=11) -- if CurrentPriv were
// NOT actually S/M respectively at that point, csr_access_bad would
// make that read fault as illegal-instruction instead of returning
// the real cause value, and the whole rest of the program would never
// reach its markers. A clean PASS on x5/x7 below is therefore also
// indirect proof the privilege level was genuinely correct at each
// handler, not just that "some code executed".
// ============================================================
module tb_csr_priv;

    localparam CLK_PERIOD = 10;
    localparam RAM_WORDS  = 16384; // 64KB, word-addressed by addr[15:2]

    reg clk, rst;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------
    // DUT ports
    // ------------------------------------------------------
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
    wire [1:0]  CurrentPriv;
    wire        Mmu_Enable_Csr;
    wire [19:0] Satp_PPN_Csr;
    wire        Mmu_Flush_Csr;

    // ------------------------------------------------------
    // Behavioral RAM -- same shape as tb_csr_trap.v (combinational
    // read, synchronous write, word granularity; this program never
    // does a real load/store either, only instruction fetch + CSR ops).
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
    RV32IMA #(
        .RESET_ADDR(32'h0000_1000)
    ) dut (
        .clk(clk), .rst(rst),
        .Stall_Core_External(1'b0),

        .Snoop_Addr(32'b0), .Snoop_WE(1'b0),

        .PCF(PCF), .InstrF(InstrF),

        .Mem_AddrM(Mem_AddrM), .Mem_WriteDataM(Mem_WriteDataM),
        .Mem_WriteEnM(Mem_WriteEnM), .Mem_ReadEnM(Mem_ReadEnM),
        .MemOpM(MemOpM),
        .Mem_AmoRmwM(), .Mem_AmoOpM(), .Mem_AmoOperandM(),
        .Mem_ReadDataM(Mem_ReadDataM),

        // No MMU in this testbench (VA=PA transparently, see header) --
        // loop Mem_AddrM (this core's own output) back into the new
        // Mem_PhysAddrM input, exact identity, see memory_stage.v's
        // header on the LR/SC VA-vs-PA fix.
        .Mem_PhysAddrM(Mem_AddrM),

        .Fetch_PageFault_In(1'b0),
        .Data_PageFault_In(1'b0),
        .Fetch_AccessFault_In(1'b0),
        .Data_AccessFault_In(1'b0),

        .ResultW(ResultW), .ALU_ResultE_Debug(ALU_ResultE_Debug),

        .CurrentPriv(CurrentPriv),
        .Mmu_Enable_Csr(Mmu_Enable_Csr),
        .Satp_PPN_Csr(Satp_PPN_Csr),
        .Mstatus_Sum(), .Mstatus_Mxr(),
        .Mmu_Flush_Csr(Mmu_Flush_Csr),
        .FenceI_M()
    );

    // ------------------------------------------------------
    // Privilege history tracker: records CurrentPriv every time it
    // actually CHANGES (edge-detected), independent of any register
    // marker -- a direct, hand-traceable log of the real privilege
    // trajectory the core took, not an inference from side effects.
    // Reset value of priv inside csr_trap_unit.v is PRIV_M (2'b11),
    // so priv_prev starts there to match (no false "transition #0"
    // recorded just from the testbench's own reset).
    // ------------------------------------------------------
    reg [1:0] priv_history [0:15];
    integer   priv_hist_count;
    reg [1:0] priv_prev;

    always @(posedge clk) begin
        if (rst) begin
            priv_hist_count <= 0;
            priv_prev       <= 2'b11;
        end
        else begin
            if (CurrentPriv !== priv_prev) begin
                if (priv_hist_count < 16) priv_history[priv_hist_count] <= CurrentPriv;
                priv_hist_count <= priv_hist_count + 1;
                priv_prev <= CurrentPriv;
            end
        end
    end

    // ------------------------------------------------------
    // Program image -- see the header for the full narrative. All
    // instructions hand-assembled and cross-checked against a small
    // scratch assembler + an independent field decoder (both outside
    // the repo, not simulator substitutes -- only catches encoding
    // mistakes, says nothing about the RTL's own correctness).
    // ------------------------------------------------------
    initial begin
        for (i = 0; i < RAM_WORDS; i = i + 1) ram[i] = 32'h0000_0013; // NOP filler

        // ---- M-mode program @ 0x1000 (RESET_ADDR) ----
        ram[32'h0000_1000 >> 2] = 32'h00001E37; // LUI  x28, 0x1           x28=0x1000
        ram[32'h0000_1004 >> 2] = 32'h100E0E13; // ADDI x28, x28, 0x100    x28=0x1100 (M_handler)
        ram[32'h0000_1008 >> 2] = 32'h305E1073; // CSRRW x0, mtvec, x28    mtvec=0x1100
        ram[32'h0000_100C >> 2] = 32'h10000E13; // ADDI x28, x0, 0x100     x28=0x100 (medeleg bit8 mask)
        ram[32'h0000_1010 >> 2] = 32'h302E1073; // CSRRW x0, medeleg, x28  medeleg=0x100 (ECALL-from-U -> S)
        ram[32'h0000_1014 >> 2] = 32'h11100093; // ADDI x1, x0, 0x111      x1: M-mode ran (marker)
        ram[32'h0000_1018 >> 2] = 32'h00100E13; // ADDI x28, x0, 1         x28=1 (see header NOTE on the 0x800 pitfall)
        ram[32'h0000_101C >> 2] = 32'h00BE1E13; // SLLI x28, x28, 11       x28=0x800 (mstatus.MPP bits[12:11]=01=S)
        ram[32'h0000_1020 >> 2] = 32'h300E1073; // CSRRW x0, mstatus, x28  mstatus=0x800 -> MPP=S
        ram[32'h0000_1024 >> 2] = 32'h00001E37; // LUI  x28, 0x1           x28=0x1000
        ram[32'h0000_1028 >> 2] = 32'h200E0E13; // ADDI x28, x28, 0x200    x28=0x1200 (S_entry)
        ram[32'h0000_102C >> 2] = 32'h341E1073; // CSRRW x0, mepc, x28     mepc=0x1200
        ram[32'h0000_1030 >> 2] = 32'h30200073; // MRET                    -> priv=S, PC=0x1200

        // ---- M_handler @ 0x1100 (non-delegated traps land here; here: EBREAK from U, cause 3) ----
        ram[32'h0000_1100 >> 2] = 32'h34102FF3; // CSRRS x31, mepc, x0     x31=mepc (=0x140C)
        ram[32'h0000_1104 >> 2] = 32'h004F8F93; // ADDI  x31, x31, 4       x31=0x1410
        ram[32'h0000_1108 >> 2] = 32'h341F9073; // CSRRW x0, mepc, x31     mepc=0x1410
        ram[32'h0000_110C >> 2] = 32'h342023F3; // CSRRS x7, mcause, x0    x7: mcause after EBREAK (expect 3) -- M-min CSR, proves priv==M here
        ram[32'h0000_1110 >> 2] = 32'h30200073; // MRET                    -> priv=mpp(=U, saved at trap time), PC=0x1410

        // ---- S-mode program @ 0x1200 (first S-mode entry, via M's MRET) ----
        ram[32'h0000_1200 >> 2] = 32'h00001DB7; // LUI  x27, 0x1           x27=0x1000
        ram[32'h0000_1204 >> 2] = 32'h300D8D93; // ADDI x27, x27, 0x300    x27=0x1300 (S_handler)
        ram[32'h0000_1208 >> 2] = 32'h105D9073; // CSRRW x0, stvec, x27    stvec=0x1300
        ram[32'h0000_120C >> 2] = 32'h22200113; // ADDI x2, x0, 0x222      x2: S-mode ran (marker, first entry)
        ram[32'h0000_1210 >> 2] = 32'h10000D93; // ADDI x27, x0, 0x100     x27=0x100 (sstatus.SPP bit8 mask)
        ram[32'h0000_1214 >> 2] = 32'h100DB073; // CSRRC x0, sstatus, x27  sstatus.SPP=0=U (explicit; also already 0 on reset)
        ram[32'h0000_1218 >> 2] = 32'h00001DB7; // LUI  x27, 0x1           x27=0x1000
        ram[32'h0000_121C >> 2] = 32'h400D8D93; // ADDI x27, x27, 0x400    x27=0x1400 (U_entry)
        ram[32'h0000_1220 >> 2] = 32'h141D9073; // CSRRW x0, sepc, x27     sepc=0x1400
        ram[32'h0000_1224 >> 2] = 32'h10200073; // SRET                    -> priv=U, PC=0x1400

        // ---- S_handler @ 0x1300 (delegated trap lands here; here: ECALL from U, cause 8) ----
        ram[32'h0000_1300 >> 2] = 32'h14102EF3; // CSRRS x29, sepc, x0     x29=sepc (=0x1404)
        ram[32'h0000_1304 >> 2] = 32'h004E8E93; // ADDI  x29, x29, 4       x29=0x1408
        ram[32'h0000_1308 >> 2] = 32'h141E9073; // CSRRW x0, sepc, x29     sepc=0x1408
        ram[32'h0000_130C >> 2] = 32'h142022F3; // CSRRS x5, scause, x0    x5: scause after delegated ECALL (expect 8) -- S-min CSR, proves priv==S here
        ram[32'h0000_1310 >> 2] = 32'h10200073; // SRET                    -> priv={0,spp}=U (trap recorded SPP=0, came from U), PC=0x1408

        // ---- U-mode program @ 0x1400 (first entry, via S's SRET) ----
        ram[32'h0000_1400 >> 2] = 32'h33300193; // ADDI x3, x0, 0x333      x3: U-mode ran (marker, first entry)
        ram[32'h0000_1404 >> 2] = 32'h00000073; // ECALL                   -> cause 8; medeleg[8]=1 & priv=U!=M -> delegated to S (stvec)
        ram[32'h0000_1408 >> 2] = 32'h44400213; // ADDI x4, x0, 0x444      x4: U resumed after DELEGATED trap (marker)
        ram[32'h0000_140C >> 2] = 32'h00100073; // EBREAK                  -> cause 3; medeleg[3]=0 -> NOT delegated, goes to M (mtvec)
        ram[32'h0000_1410 >> 2] = 32'h55500313; // ADDI x6, x0, 0x555      x6: U resumed after NON-delegated trap via M (marker)
        ram[32'h0000_1414 >> 2] = 32'h66600413; // ADDI x8, x0, 0x666      x8: final marker -- full round trip done
        ram[32'h0000_1418 >> 2] = 32'h00000063; // BEQ  x0, x0, 0          self-loop (halt), still in U-mode
    end

    // ------------------------------------------------------
    // Checks
    // ------------------------------------------------------
    integer errors;

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

    initial begin
        errors = 0;
        rst    = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        // Generous budget: ~40 instructions across 6 privilege
        // redirects (each costing a pipeline-flush's worth of bubble
        // cycles, plus this session's own csr_load_use_hazard stall
        // firing on every "CSRRS x,csr,x0" immediately followed by an
        // ADDI using that value -- both handlers do exactly that).
        // 800 cycles is a large margin over that.
        repeat (800) @(posedge clk);

        $display("---------------------------------------------");
        $display("tb_csr_priv checks");
        $display("---------------------------------------------");

        check_eq32("x1 (M-mode ran)",                    dut.decode_unit.rf.Register[1], 32'h0000_0111);
        check_eq32("x2 (S-mode ran, first entry)",        dut.decode_unit.rf.Register[2], 32'h0000_0222);
        check_eq32("x3 (U-mode ran, first entry)",        dut.decode_unit.rf.Register[3], 32'h0000_0333);
        check_eq32("x4 (U resumed after delegated ECALL)",dut.decode_unit.rf.Register[4], 32'h0000_0444);
        check_eq32("x5 (scause after delegated ECALL)",   dut.decode_unit.rf.Register[5], 32'h0000_0008);
        check_eq32("x6 (U resumed after non-deleg EBREAK)",dut.decode_unit.rf.Register[6],32'h0000_0555);
        check_eq32("x7 (mcause after non-deleg EBREAK)",  dut.decode_unit.rf.Register[7], 32'h0000_0003);
        check_eq32("x8 (final marker, full round trip)",  dut.decode_unit.rf.Register[8], 32'h0000_0666);

        check_eq32("CurrentPriv ended in U",              {30'b0, CurrentPriv}, 32'h0000_0000);

        // Independent check: the exact sequence of privilege CHANGES
        // must be S,U,S,U,M,U (6 transitions) -- see tracker above.
        // This is orthogonal to the register-marker checks: those
        // prove code ran and (for x5/x7) that a privilege-gated CSR
        // read succeeded; this proves the CurrentPriv signal itself
        // took exactly the expected path, in order.
        if (priv_hist_count != 6) begin
            $display("[FAIL] priv_hist_count: got=%0d expected=6", priv_hist_count);
            errors = errors + 1;
        end
        else begin
            $display("[PASS] priv_hist_count: 6 transitions recorded");
        end
        check_eq32("priv_history[0] (M->S, first MRET)",      {30'b0, priv_history[0]}, 32'h0000_0001);
        check_eq32("priv_history[1] (S->U, first SRET)",      {30'b0, priv_history[1]}, 32'h0000_0000);
        check_eq32("priv_history[2] (U->S, delegated ECALL)", {30'b0, priv_history[2]}, 32'h0000_0001);
        check_eq32("priv_history[3] (S->U, second SRET)",     {30'b0, priv_history[3]}, 32'h0000_0000);
        check_eq32("priv_history[4] (U->M, non-deleg EBREAK)",{30'b0, priv_history[4]}, 32'h0000_0003);
        check_eq32("priv_history[5] (M->U, second MRET)",     {30'b0, priv_history[5]}, 32'h0000_0000);

        $display("---------------------------------------------");
        if (errors == 0) begin
            $display("CSR_PRIV_TB: PASS");
        end
        else begin
            $display("CSR_PRIV_TB: FAIL (%0d check(s) failed)", errors);
        end
        $display("---------------------------------------------");
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 10000);
        $display("CSR_PRIV_TB: FAIL (global timeout -- core never reached the self-loop; dump waves)");
        $finish;
    end

endmodule
