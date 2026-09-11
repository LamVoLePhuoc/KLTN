`timescale 1ns / 1ps

// ============================================================
// csr_trap_unit
//
// M/S/U privilege mode, the M- and S-level CSR file, and synchronous
// exception (trap) handling -- ECALL/EBREAK/illegal-instruction/
// page-fault detection, mcause/mepc/mtval capture, mstatus stacking,
// MRET/SRET return, and PC redirect. Instantiated by RV32IMA.v (see
// that file for exactly how its inputs are wired from the pipeline
// and how TrapTakenM/TrapPCM override the normal PC-select/flush
// logic without needing to modify fetch_stage.v or hazard_unit.v).
//
// SCOPE / DELIBERATE SIMPLIFICATIONS (read before extending):
//   - No interrupts. mie/mip/sie/sip exist as plain read/write
//     storage (so software that probes them doesn't fault), but
//     nothing in this SoC ever sets a pending-interrupt bit or asks
//     this unit to take an interrupt trap -- there is no timer, no
//     PLIC/CLINT, no external IRQ line into any core yet (see
//     Risc_V_new/README.md's gap analysis, "Interrupt Controller").
//     Only *synchronous* exceptions (instruction-caused) are handled.
//   - mstatus/sstatus implement only the fields that matter for this
//     core's own trap-entry/return stacking: MIE/SIE, MPIE/SPIE,
//     MPP/SPP. Other fields (FS, XS, MXR, SUM, MPRV, TVM, TW, TSR,
//     SD, ...) read as 0 and writes to their bit positions are
//     ignored -- legal (WPRI-like) for unimplemented optional
//     behaviour, and honest about what's NOT implemented (MPRV in
//     particular: M-mode loads/stores here always use M-mode
//     access rules, never borrow mstatus.MPP's permissions).
//   - misa reads a fixed RV32IMASU encoding; writes are silently
//     ignored (legal WARL behaviour -- this implementation doesn't
//     support runtime extension toggling). mhartid is read-only
//     (its address's bits[11:10]==2'b11 architecturally requires
//     that, and IS enforced below -- a write attempt traps illegal-
//     instruction, unlike misa's silent-ignore).
//   - satp: fully real (software can CSRRW it; Mmu_Enable_Csr/
//     Satp_PPN_Csr reflect the current value, already gated by
//     current privilege -- see the assign site below). NOW WIRED to
//     actually drive mmu_core_wrapper/mmu_top, behind a parameter
//     (mmu_core_wrapper.v's MMU_CTRL_FROM_CSR) so the existing,
//     already-traced tb_mmu_core.v -- which deliberately drives
//     Mmu_Enable/Satp_PPN directly to isolate MMU/PTW/TLB correctness
//     from CSR correctness -- keeps compiling and behaving exactly as
//     before, unchanged. The new real top-level (core_l1_wrapper.v)
//     instantiates mmu_core_wrapper with MMU_CTRL_FROM_CSR=1 to make
//     satp the one real source of truth. See Risc_V_new/README.md.
//   - CSR read-only/write-only/privilege-level enforcement uses the
//     standard address-bit convention (addr[11:10]==2'b11 -> read-
//     only, addr[9:8] -> minimum privilege) EXCEPT it does not special
//     -case "CSRRS/CSRRC with rs1==x0 targeting a read-only CSR"
//     (spec says that specific case must NOT fault since it performs
//     no write; this implementation faults it anyway, a minor,
//     rarely-hit conservative deviation -- no real software does a
//     pointless CSRRS x0 on a WARL-read-only CSR).
//   - Only ONE trap target computed per commit cycle (no attempt to
//     encode a full priority list beyond what's naturally mutually
//     exclusive by construction -- see the priority mux below and
//     RV32IMA.v's wiring comment for why overlaps can't actually
//     happen here).
// ============================================================
module csr_trap_unit #(
    parameter [31:0] HART_ID = 32'd0
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        Stall_Core_External,

    // ---- CSR access, EX/MEM-boundary timing ----
    input  wire         CsrOpM,
    input  wire [2:0]   CsrFunct3M,
    input  wire [11:0]  CsrAddrM,
    input  wire [31:0]  CsrWDataM,
    output reg  [31:0]  CsrRDataM,

    // ---- privileged sub-decode, EX/MEM-boundary timing ----
    input  wire         IsEcallM,
    input  wire         IsEbreakM,
    input  wire         IsMretM,
    input  wire         IsSretM,
    input  wire         IsSfenceVmaM,
    input  wire         IsPrivIllegalM,
    input  wire         IsIllegalOpM,

    // ---- other exception sources, EX/MEM-boundary timing ----
    input  wire         MemReadM,
    input  wire         MemWriteM,
    input  wire         FetchPageFaultM,
    input  wire         DataPageFaultM,
    input  wire [31:0]  PCM,           // this instruction's own PC
    input  wire [31:0]  InstrM,
    input  wire [31:0]  MemAddrM,      // load/store VA (ALU_ResultM)

    // ---- trap redirect out (see RV32IMA.v for how these are consumed) ----
    output wire          TrapTakenM,
    output reg  [31:0]   TrapPCM,       // combinational (see the always@* block below) -- must be
                                          // valid the SAME cycle as TrapTakenM, not one cycle later

    // ---- observability / future MMU integration ----
    output wire [1:0]    CurrentPriv,
    output wire          Mmu_Enable_Csr,
    output wire [19:0]   Satp_PPN_Csr,
    output reg           Mmu_Flush_Csr
);

    localparam [1:0] PRIV_U = 2'b00, PRIV_S = 2'b01, PRIV_M = 2'b11;

    // ------------------------------------------------------
    // CSR addresses used
    // ------------------------------------------------------
    localparam [11:0]
        CSR_SSTATUS  = 12'h100,
        CSR_SIE      = 12'h104,
        CSR_STVEC    = 12'h105,
        CSR_SSCRATCH = 12'h140,
        CSR_SEPC     = 12'h141,
        CSR_SCAUSE   = 12'h142,
        CSR_STVAL    = 12'h143,
        CSR_SIP      = 12'h144,
        CSR_SATP     = 12'h180,
        CSR_MSTATUS  = 12'h300,
        CSR_MISA     = 12'h301,
        CSR_MEDELEG  = 12'h302,
        CSR_MIDELEG  = 12'h303,
        CSR_MIE      = 12'h304,
        CSR_MTVEC    = 12'h305,
        CSR_MSCRATCH = 12'h340,
        CSR_MEPC     = 12'h341,
        CSR_MCAUSE   = 12'h342,
        CSR_MTVAL    = 12'h343,
        CSR_MIP      = 12'h344,
        CSR_MHARTID  = 12'hF14;

    // ------------------------------------------------------
    // State
    // ------------------------------------------------------
    reg [1:0] priv;               // current privilege mode

    // mstatus fields actually implemented (rest read 0 / ignore writes)
    reg mie_bit, mpie_bit, sie_bit, spie_bit;
    reg [1:0] mpp_bit;
    reg spp_bit;

    reg [31:0] mtvec, stvec;
    reg [31:0] mscratch, sscratch;
    reg [31:0] mepc, sepc;
    reg [31:0] mcause, scause;
    reg [31:0] mtval, stval;
    reg [31:0] mie_reg, mip_reg;   // full 32-bit storage (unused bits inert, see header)
    reg [31:0] medeleg, mideleg;
    reg [19:0] satp_ppn;
    reg        satp_mode;          // 0 = Bare, 1 = Sv32

    // ------------------------------------------------------
    // Read mux (combinational)
    // ------------------------------------------------------
    wire [31:0] mstatus_r = { 1'b0,                 // SD
                               8'b0,                 // WPRI / not implemented
                               1'b0, 1'b0,           // TSR, TW
                               1'b0,                 // TVM
                               1'b0,                 // MXR
                               1'b0,                 // SUM
                               1'b0,                 // MPRV
                               2'b0,                 // XS
                               2'b0,                 // FS
                               mpp_bit,              // MPP [12:11]
                               2'b0,                 // WPRI
                               spp_bit,              // SPP [8]
                               mpie_bit,             // MPIE [7]
                               1'b0,                 // WPRI
                               spie_bit,             // SPIE [5]
                               1'b0,                 // UPIE (unused, no N-ext)
                               mie_bit,              // MIE [3]
                               1'b0,                 // WPRI
                               sie_bit,              // SIE [1]
                               1'b0 };                // UIE (unused)

    wire [31:0] sstatus_r = mstatus_r & 32'h800DE133; // S-mode-visible subset (SD,MXR,SUM,XS,FS,SPP,SPIE,UPIE,SIE,UIE)

    // Custom satp layout (documented deviation from real Sv32, matching
    // this repo's already-established 20-bit-PPN convention -- see
    // mmu_ptw.v's own header comment on why PPN is 20b not Sv32's 22b):
    //   bit20 = MODE (0=Bare, 1=Sv32-lite), bits[19:0] = PPN, rest reserved/0.
    wire [31:0] satp_r = {11'b0, satp_mode, satp_ppn};

    always @(*) begin
        case (CsrAddrM)
            CSR_SSTATUS:  CsrRDataM = sstatus_r;
            CSR_SIE:      CsrRDataM = mie_reg & mideleg;
            CSR_STVEC:    CsrRDataM = stvec;
            CSR_SSCRATCH: CsrRDataM = sscratch;
            CSR_SEPC:     CsrRDataM = sepc;
            CSR_SCAUSE:   CsrRDataM = scause;
            CSR_STVAL:    CsrRDataM = stval;
            CSR_SIP:      CsrRDataM = mip_reg & mideleg;
            CSR_SATP:     CsrRDataM = satp_r;
            CSR_MSTATUS:  CsrRDataM = mstatus_r;
            CSR_MISA:     CsrRDataM = 32'h40141101; // RV32, extensions A,I,M,S,U
            CSR_MEDELEG:  CsrRDataM = medeleg;
            CSR_MIDELEG:  CsrRDataM = mideleg;
            CSR_MIE:      CsrRDataM = mie_reg;
            CSR_MTVEC:    CsrRDataM = mtvec;
            CSR_MSCRATCH: CsrRDataM = mscratch;
            CSR_MEPC:     CsrRDataM = mepc;
            CSR_MCAUSE:   CsrRDataM = mcause;
            CSR_MTVAL:    CsrRDataM = mtval;
            CSR_MIP:      CsrRDataM = mip_reg;
            CSR_MHARTID:  CsrRDataM = HART_ID;
            default:      CsrRDataM = 32'b0;
        endcase
    end

    // ------------------------------------------------------
    // Access legality (checked regardless of whether this cycle is
    // the true commit cycle -- only used to steer the trap decision
    // below, which IS itself gated to the true commit cycle)
    // ------------------------------------------------------
    wire [1:0] csr_min_priv   = CsrAddrM[9:8];
    wire       csr_readonly   = (CsrAddrM[11:10] == 2'b11);
    wire       csr_known      = (CsrAddrM == CSR_SSTATUS)  || (CsrAddrM == CSR_SIE)     ||
                                 (CsrAddrM == CSR_STVEC)    || (CsrAddrM == CSR_SSCRATCH)||
                                 (CsrAddrM == CSR_SEPC)     || (CsrAddrM == CSR_SCAUSE)  ||
                                 (CsrAddrM == CSR_STVAL)    || (CsrAddrM == CSR_SIP)     ||
                                 (CsrAddrM == CSR_SATP)     || (CsrAddrM == CSR_MSTATUS) ||
                                 (CsrAddrM == CSR_MISA)     || (CsrAddrM == CSR_MEDELEG) ||
                                 (CsrAddrM == CSR_MIDELEG)  || (CsrAddrM == CSR_MIE)     ||
                                 (CsrAddrM == CSR_MTVEC)    || (CsrAddrM == CSR_MSCRATCH)||
                                 (CsrAddrM == CSR_MEPC)     || (CsrAddrM == CSR_MCAUSE)  ||
                                 (CsrAddrM == CSR_MTVAL)    || (CsrAddrM == CSR_MIP)     ||
                                 (CsrAddrM == CSR_MHARTID);
    wire       csr_priv_ok    = (priv >= csr_min_priv);   // PRIV_U=0 < PRIV_S=1 < PRIV_M=3 (2'b11); the
                                                            // gap at 2'b10 (Hypervisor) is never used as
                                                            // csr_min_priv by any address implemented here
    wire       csr_write_ok   = ~csr_readonly;             // see header: rs1==x0 special-case not modelled
    wire       csr_access_bad = CsrOpM & (~csr_known | ~csr_priv_ok | ~csr_write_ok);

    // ------------------------------------------------------
    // Trap cause selection (priority chain -- see header: in
    // practice at most one of these is ever true at once, given how
    // each is decoded, but the chain is written defensively anyway)
    // ------------------------------------------------------
    reg        exc_valid;
    reg [3:0]  exc_cause;      // low nibble of mcause (bit31 interrupt-flag always 0 here)
    reg [31:0] exc_tval;

    always @(*) begin
        exc_valid = 1'b1;
        exc_cause = 4'd0;
        exc_tval  = 32'd0;

        if (FetchPageFaultM) begin
            exc_cause = 4'd12; exc_tval = PCM;
        end
        else if (IsIllegalOpM || IsPrivIllegalM || csr_access_bad) begin
            exc_cause = 4'd2;  exc_tval = InstrM;
        end
        else if (IsEbreakM) begin
            exc_cause = 4'd3;  exc_tval = PCM;
        end
        else if (IsEcallM) begin
            exc_cause = (priv == PRIV_M) ? 4'd11 : (priv == PRIV_S) ? 4'd9 : 4'd8;
        end
        else if (DataPageFaultM) begin
            exc_cause = MemWriteM ? 4'd15 : 4'd13; exc_tval = MemAddrM;
        end
        else begin
            exc_valid = 1'b0;
        end
    end

    wire do_trap  = exc_valid & ~Stall_Core_External;
    wire do_mret  = IsMretM   & ~Stall_Core_External;
    wire do_sret  = IsSretM   & ~Stall_Core_External;
    wire do_sfence= IsSfenceVmaM & ~Stall_Core_External;
    wire do_csr_write = CsrOpM & ~Stall_Core_External & ~csr_access_bad;

    // delegate to S-mode only if: currently at or below S, and the
    // cause bit is set in medeleg
    wire deleg_to_s = (priv != PRIV_M) & medeleg[exc_cause];

    assign TrapTakenM = do_trap | do_mret | do_sret;

    // Combinational, same-cycle as TrapTakenM (see the port comment
    // above for why this can't be a registered assignment): reads
    // whatever mepc/sepc/mtvec/stvec currently hold, which is exactly
    // right since it's *this* cycle's trap/return we're redirecting
    // for, not a future one.
    always @(*) begin
        if (do_mret)      TrapPCM = mepc;
        else if (do_sret) TrapPCM = sepc;
        else if (do_trap) TrapPCM = deleg_to_s ? stvec : mtvec;
        else              TrapPCM = 32'b0; // don't-care: TrapTakenM is 0 this cycle
    end

    assign CurrentPriv    = priv;
    // Real RISC-V semantics (and this design does not implement
    // mstatus.MPRV, so there is no exception to it here): M-mode
    // NEVER translates, regardless of satp.MODE -- satp only governs
    // S-mode and U-mode accesses. So the enable signal a caller
    // should actually gate translation with is satp.MODE AND
    // "not M-mode" combined, not the raw satp.MODE bit alone; doing
    // the gating here (the one place that owns both satp and priv)
    // means every consumer (mmu_core_wrapper.v et al) gets it right
    // automatically instead of re-deriving this rule themselves.
    assign Mmu_Enable_Csr = satp_mode & (priv != PRIV_M);
    assign Satp_PPN_Csr   = satp_ppn[19:0];

    // ------------------------------------------------------
    // CSR write value computation (RW/RS/RC on the raw storage bits
    // this address maps to -- applied below only on do_csr_write)
    // ------------------------------------------------------
    function [31:0] csr_next_value;
        input [31:0] old_val;
        input [31:0] wdata;
        input [2:0]  funct3;
        begin
            case (funct3[1:0])       // bit2 (immediate-vs-register) doesn't change the op itself
                2'b01: csr_next_value = wdata;               // CSRRW/CSRRWI
                2'b10: csr_next_value = old_val | wdata;      // CSRRS/CSRRSI
                2'b11: csr_next_value = old_val & ~wdata;      // CSRRC/CSRRCI
                default: csr_next_value = old_val;
            endcase
        end
    endfunction

    // Full-width "what would this register become" for the 3 multi-
    // field registers (mstatus/sstatus/satp) -- computed from the
    // ALREADY-correctly-laid-out *_r read values above, so RS/RC
    // combine against real bit positions instead of a repositioned
    // single bit. Individual bit fields are then extracted from
    // THESE at their real positions in the write-commit block below.
    // (A field-by-field reposition-to-bit-0-then-combine shortcut was
    // tried first and was wrong -- CsrWDataM's bits are at the real
    // mstatus/satp positions, e.g. MPP at [12:11], not at [1:0], so
    // combining a repositioned single bit against the untouched
    // CsrWDataM silently read the wrong bits of the write data. Fixed
    // by always combining full-width, real-position values instead.)
    wire [31:0] mstatus_next = csr_next_value(mstatus_r, CsrWDataM, CsrFunct3M);
    wire [31:0] sstatus_next = csr_next_value(sstatus_r, CsrWDataM, CsrFunct3M);
    wire [31:0] satp_next    = csr_next_value(satp_r,    CsrWDataM, CsrFunct3M);

    always @(posedge clk) begin
        if (rst) begin
            priv         <= PRIV_M;
            mie_bit <= 1'b0; mpie_bit <= 1'b0; sie_bit <= 1'b0; spie_bit <= 1'b0;
            mpp_bit <= PRIV_M; spp_bit <= 1'b0;
            mtvec <= 32'b0; stvec <= 32'b0;
            mscratch <= 32'b0; sscratch <= 32'b0;
            mepc <= 32'b0; sepc <= 32'b0;
            mcause <= 32'b0; scause <= 32'b0;
            mtval <= 32'b0; stval <= 32'b0;
            mie_reg <= 32'b0; mip_reg <= 32'b0;
            medeleg <= 32'b0; mideleg <= 32'b0;
            satp_ppn <= 20'b0; satp_mode <= 1'b0;
            Mmu_Flush_Csr <= 1'b0;
        end
        else begin
            Mmu_Flush_Csr <= 1'b0; // 1-cycle pulse, default low

            // ---- CSR write commit (applied before/independent of a
            // trap on the SAME instruction -- a CSR op and a trap
            // never coincide on the same instruction: CSR ops always
            // have csr_access_bad computed first, and a legit CSR op
            // matches none of the exc_* conditions above) ----
            if (do_csr_write) begin
                case (CsrAddrM)
                    CSR_SSTATUS: begin
                        spp_bit  <= sstatus_next[8];
                        spie_bit <= sstatus_next[5];
                        sie_bit  <= sstatus_next[1];
                    end
                    CSR_SIE:      mie_reg  <= (mie_reg & ~mideleg) | (csr_next_value(mie_reg & mideleg, CsrWDataM, CsrFunct3M) & mideleg);
                    CSR_STVEC:    stvec    <= csr_next_value(stvec, CsrWDataM, CsrFunct3M) & ~32'h3;
                    CSR_SSCRATCH: sscratch <= csr_next_value(sscratch, CsrWDataM, CsrFunct3M);
                    CSR_SEPC:     sepc     <= csr_next_value(sepc, CsrWDataM, CsrFunct3M) & ~32'h3;
                    CSR_SCAUSE:   scause   <= csr_next_value(scause, CsrWDataM, CsrFunct3M);
                    CSR_STVAL:    stval    <= csr_next_value(stval, CsrWDataM, CsrFunct3M);
                    CSR_SIP:      mip_reg  <= (mip_reg & ~mideleg) | (csr_next_value(mip_reg & mideleg, CsrWDataM, CsrFunct3M) & mideleg);
                    CSR_SATP: begin
                        satp_mode <= satp_next[20];
                        satp_ppn  <= satp_next[19:0];
                    end
                    CSR_MSTATUS: begin
                        mpp_bit  <= mstatus_next[12:11];
                        spp_bit  <= mstatus_next[8];
                        mpie_bit <= mstatus_next[7];
                        spie_bit <= mstatus_next[5];
                        mie_bit  <= mstatus_next[3];
                        sie_bit  <= mstatus_next[1];
                    end
                    CSR_MISA: ; // WARL, silently ignored (see header)
                    CSR_MEDELEG:  medeleg  <= csr_next_value(medeleg, CsrWDataM, CsrFunct3M);
                    CSR_MIDELEG:  mideleg  <= csr_next_value(mideleg, CsrWDataM, CsrFunct3M);
                    CSR_MIE:      mie_reg  <= csr_next_value(mie_reg, CsrWDataM, CsrFunct3M);
                    CSR_MTVEC:    mtvec    <= csr_next_value(mtvec, CsrWDataM, CsrFunct3M) & ~32'h3;
                    CSR_MSCRATCH: mscratch <= csr_next_value(mscratch, CsrWDataM, CsrFunct3M);
                    CSR_MEPC:     mepc     <= csr_next_value(mepc, CsrWDataM, CsrFunct3M) & ~32'h3;
                    CSR_MCAUSE:   mcause   <= csr_next_value(mcause, CsrWDataM, CsrFunct3M);
                    CSR_MTVAL:    mtval    <= csr_next_value(mtval, CsrWDataM, CsrFunct3M);
                    CSR_MIP:      mip_reg  <= csr_next_value(mip_reg, CsrWDataM, CsrFunct3M);
                    default: ; // MHARTID or unknown: no storage to write (MHARTID already
                                // blocked from reaching here by csr_access_bad's read-only check)
                endcase
            end

            // ---- SFENCE.VMA: flush pulse (see header: not yet wired to the real MMU) ----
            if (do_sfence) begin
                Mmu_Flush_Csr <= 1'b1;
            end

            // ---- MRET / SRET ----
            if (do_mret) begin
                priv     <= mpp_bit;
                mie_bit  <= mpie_bit;
                mpie_bit <= 1'b1;
                mpp_bit  <= PRIV_U;      // spec: MPP set to least-privileged supported mode (U, here)
            end
            else if (do_sret) begin
                priv     <= {1'b0, spp_bit};
                sie_bit  <= spie_bit;
                spie_bit <= 1'b1;
                spp_bit  <= 1'b0;
            end

            // ---- Synchronous exception ----
            else if (do_trap) begin
                if (deleg_to_s) begin
                    scause   <= {28'b0, exc_cause};
                    sepc     <= PCM;
                    stval    <= exc_tval;
                    spp_bit  <= (priv != PRIV_U); // came from S (1) or U (0)
                    spie_bit <= sie_bit;
                    sie_bit  <= 1'b0;
                    priv     <= PRIV_S;
                end
                else begin
                    mcause   <= {28'b0, exc_cause};
                    mepc     <= PCM;
                    mtval    <= exc_tval;
                    mpp_bit  <= priv;
                    mpie_bit <= mie_bit;
                    mie_bit  <= 1'b0;
                    priv     <= PRIV_M;
                end
            end
        end
    end

endmodule
