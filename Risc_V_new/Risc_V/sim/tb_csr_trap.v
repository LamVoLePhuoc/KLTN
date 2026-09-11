`timescale 1ns / 1ps

// ============================================================
// tb_csr_trap
//
// Self-checking testbench for the CSR/Trap/Privilege subsystem
// built this session (sys_decoder.v + csr_trap_unit.v + the
// additive pipeline plumbing through Main_Decoder.v/decode_stage.v/
// if_id_registers.v/id_ex_registers.v/execute_stage.v/
// ex_mem_registers.v/mem_wb_registers.v/writeback_stage.v/RV32IMA.v
// -- see Risc_V_new/README.md mục -0.5). THIS IS THE SECOND MOST
// IMPORTANT TESTBENCH IN THE REPO after tb_coherence.v -- run it
// before trusting any program that uses CSRs, ECALL/EBREAK, or
// relies on a page fault actually trapping instead of just being
// silently forced to a NOP/blocked store.
//
// Instantiates RV32IMA directly (not through mmu_core_wrapper) --
// deliberately, to keep this test's timing fully hand-traceable:
// csr_trap_unit.v lives INSIDE RV32IMA.v itself, so none of what
// this file exercises (CSR read/write, ECALL/EBREAK/illegal-
// instruction detection, MRET, PC redirect, pipeline flush) needs
// an MMU in the loop at all. Fetch_PageFault_In/Data_PageFault_In
// are tied low throughout -- verifying "does an MMU page fault
// actually reach csr_trap_unit and trap" is a SEPARATE, narrower
// claim (mmu_core_wrapper.v correctly feeds its own fetch_fault/
// mem_fault into these same two ports -- see that file) that this
// testbench does NOT cover; a follow-up extension combining this
// program style with tb_mmu_core.v's page-table setup is the
// natural next step, not done here for the same time-budget reason
// noted throughout this session's README updates.
//
// Test program (hand-assembled, PA = VA since no MMU here; RESET_ADDR
// = RV32IMA's own default 0x1000):
//   1. Set mtvec = 0x2000 (a tiny, generic trap handler -- see below).
//   2. Exercise CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI on mscratch, checking
//      both the OLD value returned into rd and the NEW value that
//      lands in the CSR (read back with a following CSRRS rd,csr,x0).
//   3. EBREAK -> traps (cause 3), handler advances mepc by 4 and
//      MRETs back; a marker value written to a register right after
//      proves execution actually resumed at the right place.
//   4. ECALL from M-mode -> traps (cause 11, since priv is M
//      throughout this test -- no privilege drop is exercised),
//      same handler, same marker-after-resume pattern.
//   5. A literal 0x00000000 word (opcode 0000000, not in
//      Main_Decoder.v's known-opcode list) -> illegal-instruction
//      trap (cause 2), same handler/marker pattern.
//   6. Final CSRRS reads of mcause and mscratch confirm the state
//      csr_trap_unit.v is left in matches expectations exactly.
//
// Handler @ 0x2000 is deliberately generic (doesn't branch on cause):
//   CSRRS x31, mepc, x0   ; x31 = mepc
//   ADDI  x31, x31, 4     ; skip past the faulting instruction
//   CSRRW x0, mepc, x31   ; mepc = mepc + 4
//   MRET
// (Real EBREAK/illegal-instruction handlers don't always want to
// just skip forward -- this is a testbench convenience, not a
// software-engineering recommendation.)
// ============================================================
module tb_csr_trap;

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
    // Behavioral RAM: combinational read, synchronous write, word
    // granularity only -- every access in this test is a full-word
    // instruction fetch or CSR/ALU op with no load/store at all
    // (this program never touches Mem_AddrM for real data), so this
    // model only really needs to serve InstrF correctly. Kept the
    // full read/write shape anyway for consistency with the other
    // testbenches this session and in case the program is extended.
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
        .MemOpM(MemOpM), .Mem_ReadDataM(Mem_ReadDataM),

        .Fetch_PageFault_In(1'b0),
        .Data_PageFault_In(1'b0),

        .ResultW(ResultW), .ALU_ResultE_Debug(ALU_ResultE_Debug),

        .CurrentPriv(CurrentPriv),
        .Mmu_Enable_Csr(Mmu_Enable_Csr),
        .Satp_PPN_Csr(Satp_PPN_Csr),
        .Mmu_Flush_Csr(Mmu_Flush_Csr)
    );

    // ------------------------------------------------------
    // Program image
    // ------------------------------------------------------
    initial begin
        for (i = 0; i < RAM_WORDS; i = i + 1) ram[i] = 32'h0000_0013; // NOP filler

        // ---- Main program @ 0x1000 ----
        ram[32'h0000_1000 >> 2] = 32'h000020B7; // LUI  x1, 0x2            x1 = 0x2000
        ram[32'h0000_1004 >> 2] = 32'h30509073; // CSRRW x0, mtvec, x1     mtvec = 0x2000
        ram[32'h0000_1008 >> 2] = 32'h12345137; // LUI  x2, 0x12345        x2 = 0x12345000
        ram[32'h0000_100C >> 2] = 32'h340111F3; // CSRRW x3, mscratch, x2  mscratch=x2; x3=old(0)
        ram[32'h0000_1010 >> 2] = 32'h34002273; // CSRRS x4, mscratch, x0  x4 = mscratch (0x12345000), no write
        ram[32'h0000_1014 >> 2] = 32'h0F000293; // ADDI x5, x0, 0xF0       x5 = 0xF0
        ram[32'h0000_1018 >> 2] = 32'h3402A373; // CSRRS x6, mscratch, x5  mscratch |= 0xF0; x6=old(0x12345000)
        ram[32'h0000_101C >> 2] = 32'h3402B3F3; // CSRRC x7, mscratch, x5  mscratch &= ~0xF0; x7=old(0x123450F0)
        ram[32'h0000_1020 >> 2] = 32'h3402D473; // CSRRWI x8, mscratch, 5  mscratch=5; x8=old(0x12345000)
        ram[32'h0000_1024 >> 2] = 32'h3401E4F3; // CSRRSI x9, mscratch, 3  mscratch|=3(=>7); x9=old(5)
        ram[32'h0000_1028 >> 2] = 32'h00100073; // EBREAK                  -> trap cause 3
        ram[32'h0000_102C >> 2] = 32'h11100513; // ADDI x10, x0, 0x111     marker: resumed after EBREAK
        ram[32'h0000_1030 >> 2] = 32'h00000073; // ECALL                   -> trap cause 11 (M-mode)
        ram[32'h0000_1034 >> 2] = 32'h22200593; // ADDI x11, x0, 0x222     marker: resumed after ECALL
        ram[32'h0000_1038 >> 2] = 32'h00000000; // (illegal: opcode 0000000) -> trap cause 2
        ram[32'h0000_103C >> 2] = 32'h33300613; // ADDI x12, x0, 0x333     marker: resumed after illegal instr
        ram[32'h0000_1040 >> 2] = 32'h342026F3; // CSRRS x13, mcause, x0   x13 = mcause (expect 2, from illegal instr)
        ram[32'h0000_1044 >> 2] = 32'h34002773; // CSRRS x14, mscratch, x0 x14 = mscratch (expect 7)
        ram[32'h0000_1048 >> 2] = 32'h00000063; // BEQ x0, x0, 0           self-loop (halt)

        // ---- Generic trap handler @ 0x2000 ----
        ram[32'h0000_2000 >> 2] = 32'h34102FF3; // CSRRS x31, mepc, x0
        ram[32'h0000_2004 >> 2] = 32'h004F8F93; // ADDI  x31, x31, 4
        ram[32'h0000_2008 >> 2] = 32'h341F9073; // CSRRW x0, mepc, x31
        ram[32'h0000_200C >> 2] = 32'h30200073; // MRET
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

        // Generous budget: 19 main-program instructions + 3 trap
        // round trips (4-instruction handler each) + normal pipeline
        // fill/forwarding cycles, no MMU stalls at all in this test.
        repeat (400) @(posedge clk);

        $display("---------------------------------------------");
        $display("tb_csr_trap checks");
        $display("---------------------------------------------");

        check_eq32("x1  (LUI mtvec target)",        dut.decode_unit.rf.Register[1],  32'h0000_2000);
        check_eq32("x2  (LUI test value)",           dut.decode_unit.rf.Register[2],  32'h1234_5000);
        check_eq32("x3  (CSRRW old mscratch=reset0)",dut.decode_unit.rf.Register[3],  32'h0000_0000);
        check_eq32("x4  (CSRRS pure read)",           dut.decode_unit.rf.Register[4],  32'h1234_5000);
        check_eq32("x5  (ADDI mask)",                 dut.decode_unit.rf.Register[5],  32'h0000_00F0);
        check_eq32("x6  (CSRRS old, before OR)",      dut.decode_unit.rf.Register[6],  32'h1234_5000);
        check_eq32("x7  (CSRRC old, before AND-clr)", dut.decode_unit.rf.Register[7],  32'h1234_50F0);
        check_eq32("x8  (CSRRWI old, before =5)",     dut.decode_unit.rf.Register[8],  32'h1234_5000);
        check_eq32("x9  (CSRRSI old, before OR 3)",   dut.decode_unit.rf.Register[9],  32'h0000_0005);
        check_eq32("x10 (resumed after EBREAK)",      dut.decode_unit.rf.Register[10], 32'h0000_0111);
        check_eq32("x11 (resumed after ECALL)",       dut.decode_unit.rf.Register[11], 32'h0000_0222);
        check_eq32("x12 (resumed after illegal instr)",dut.decode_unit.rf.Register[12],32'h0000_0333);
        check_eq32("x13 (mcause after illegal instr)",dut.decode_unit.rf.Register[13], 32'h0000_0002);
        check_eq32("x14 (final mscratch)",            dut.decode_unit.rf.Register[14], 32'h0000_0007);

        check_eq32("CurrentPriv stayed M throughout",  {30'b0, CurrentPriv}, 32'h0000_0003);

        $display("---------------------------------------------");
        if (errors == 0) begin
            $display("CSR_TRAP_TB: PASS");
        end
        else begin
            $display("CSR_TRAP_TB: FAIL (%0d check(s) failed)", errors);
        end
        $display("---------------------------------------------");
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 5000);
        $display("CSR_TRAP_TB: FAIL (global timeout -- core never reached the self-loop; dump waves)");
        $finish;
    end

endmodule
