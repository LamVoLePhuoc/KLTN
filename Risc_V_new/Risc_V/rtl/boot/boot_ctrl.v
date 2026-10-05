`timescale 1ns / 1ps

// ============================================================
// boot_ctrl
//
// The PL-side half of the Genesys ZU-5EV SD-card boot flow (see
// Risc_V_new/README.md's boot-flow section for the full picture and
// WHY this exists in this shape). Deliberately tiny and simple --
// this is exactly the kind of "provably correct by inspection" block
// this session favors: a small register bank, one-shot outputs and no
// FSM beyond the AXI4-Lite handshake itself.
//
// THE PROBLEM THIS SOLVES: on Genesys ZU-5EV, the microSD card is
// wired to the Zynq UltraScale+ PS's own hardened SD controller (MIO
// pins), NOT to any PL-fabric pin -- confirmed via Digilent's own
// documented boot flow (FSBL + BOOT.BIN packaged and read from SD by
// the PS's boot ROM; see README). This means a PL-only RISC-V core
// cannot itself bit-bang the SD card -- there is no electrical path
// from PL to the card's pins on this board. The PS, however, already
// has a fully verified, hardened SD+FAT stack (Xilinx's FSBL /
// xilffs), so the natural, low-risk architecture is:
//   1. PS boots normally from SD (already works out of the box on
//      this board -- nothing new needed here).
//   2. A small PS-side loader (bare-metal app or FSBL hook, see
//      README -- runs on the ARM cores, a completely different
//      toolchain from RISC-V, out of scope for hand-assembly in this
//      repo) reads the RISC-V program image from the SD card's FAT32
//      filesystem into DRAM, at whatever address the RISC-V cores'
//      RESET_ADDR / memory map expects.
//   3. The PS writes GO=1 through this register block (reached via
//      an AXI-Lite GP port from PS to PL) to release the RISC-V cores
//      from reset, only once the program is actually in place.
// Without step 3, the RISC-V cores would come out of PL configuration
// reset and start fetching from a DRAM region the PS hasn't finished
// writing yet -- boot_ctrl's whole job is to prevent that race by
// holding CORE_RESETN asserted (RISC-V side held in reset) until the
// PS explicitly says the image is ready.
//
// One-shot by design: once GO is written 1, core_resetn stays high
// (released) permanently -- there is no register bit to re-assert it
// from software. A real "reboot the RISC-V side" would go through the
// system-wide ARESETN (power-on/PS reset) instead, same as any other
// peripheral; boot_ctrl only ever needs to gate the FIRST release.
//
// SECOND JOB (added after reconsidering the "automated evaluation"
// piece -- see Risc_V_new/README.md): also carries a RESULT register
// the RISC-V program writes its PASS/FAIL code into, and the PS reads
// back. This exists because axi_uartlite's physical TX/RX pins have
// NO CONFIRMED path to anything the host can actually see on Genesys
// ZU-5EV -- the board's one on-board USB-UART bridge is, like the SD
// card, almost certainly wired to the PS's own hardened UART (MIO
// pins), not to any PL pin a custom axi_uartlite instance could reach
// (same class of PS-vs-PL wiring question as boot_ctrl's whole reason
// to exist -- see above). Routing the result through THIS block
// instead sidesteps that uncertainty entirely: it reuses the exact
// same PS<->PL AXI-Lite path already proven necessary for the GO bit,
// and the PS prints/relays the result over its OWN console UART,
// which is guaranteed to exist and already work on any Zynq board
// (that is precisely how you interact with the FSBL/Linux console
// today). A physical PL UART (axi_uartlite) is still wired into
// scripts/build_soc_zu5ev_boot.tcl as a bonus/debug peripheral -- use
// it for real serial output ONLY once you've confirmed this board
// actually exposes a PL-reachable UART-capable connector; don't rely
// on it for the automated PASS/FAIL result.
//
// core_go itself is exactly what makes it SAFE for the RISC-V side to
// write RESULT at all: the register write reaches this block through
// the same AXI interconnect cpu0's own M_AXI is on (see the Tcl
// script), and that path only starts producing real traffic after
// the RISC-V cores are actually released and running -- i.e. after
// GO is already 1. There is no ordering hazard to reason about beyond
// that.
//
// A fourth register at offset 0xC closes the control loop for
// non-coherent DMA after boot: PS software can request a global cache
// clean/invalidate and poll BUSY/DONE/ERROR/REJECTED without relying on
// board-level GPIO. See docs/BOOT_DMA_PROTOCOL.md for the required
// quiesce-before-DMA and post-DMA invalidate sequence.
// ============================================================
module boot_ctrl (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 S_AXI_ACLK CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET S_AXI_ARESETN" *)
    input  wire        S_AXI_ACLK,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 S_AXI_ARESETN RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        S_AXI_ARESETN,

    // ---- AXI4-Lite slave (32-bit data/addr, single-beat only -- no
    // bursts, nothing here needs them) ----
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    input  wire [3:0]  S_AXI_AWADDR,   // bits[3:2] select four word registers
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  wire        S_AXI_AWVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output reg         S_AXI_AWREADY,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  wire [31:0] S_AXI_WDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  wire [3:0]  S_AXI_WSTRB,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  wire        S_AXI_WVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output reg         S_AXI_WREADY,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output wire [1:0]  S_AXI_BRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output reg         S_AXI_BVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  wire        S_AXI_BREADY,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  wire [3:0]  S_AXI_ARADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  wire        S_AXI_ARVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output reg         S_AXI_ARREADY,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output reg  [31:0] S_AXI_RDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output wire [1:0]  S_AXI_RRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output reg         S_AXI_RVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  wire        S_AXI_RREADY,

    // ---- to the RISC-V side ----
    // Active-HIGH release, matching this repo's plain `rst`/core-reset
    // convention elsewhere (RV32IMA.v, quad_core_soc.v, ...) rather
    // than AXI's own active-LOW convention -- the caller (see
    // quad_core_axi_wrapper_bootable.v) is what actually combines this
    // with the system ARESETN, so the polarity used here is a purely
    // internal, local choice.
    output wire        core_go,

    // ---- cache-maintenance bridge for PS-controlled DMA ----
    // Write bit0=1 to REG_CACHE (0xC) to emit one request pulse. The
    // command is accepted only after GO and while the hierarchy is idle.
    input  wire        cache_flush_busy,
    input  wire        cache_flush_done,
    input  wire        cache_flush_error,
    output reg         cache_flush_request
);

    localparam [1:0] REG_CTRL   = 2'b00, // offset 0x0: bit0 = GO (write-1, sticky, see header)
                      REG_STATUS = 2'b01, // offset 0x4: read-only mirror of GO, for PS-side polling/debug
                      REG_RESULT = 2'b10, // offset 0x8: RISC-V writes its PASS/FAIL code here, PS reads it (see header)
                      REG_CACHE  = 2'b11; // offset 0xC: bit0 busy, bit1 done, bit2 error, bit3 rejected

    assign S_AXI_BRESP = 2'b00; // OKAY, always -- no invalid-address/permission concept worth reporting here
    assign S_AXI_RRESP = 2'b00;

    reg        go_reg;
    reg [31:0] result_reg;
    reg        cache_done_latched;
    reg        cache_reject_latched;
    assign core_go = go_reg;

    // ------------------------------------------------------
    // Write channel: accept AW+W together (simplest legal AXI4-Lite
    // slave shape -- this block is never on a critical timing path,
    // no reason to pipeline address/data phases separately).
    // ------------------------------------------------------
    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            go_reg        <= 1'b0;
            result_reg    <= 32'b0;
            cache_flush_request <= 1'b0;
            cache_done_latched  <= 1'b0;
            cache_reject_latched<= 1'b0;
        end
        else begin
            // Default: only assert *READY for exactly the one cycle
            // the transfer is accepted (below), never held high.
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            cache_flush_request <= 1'b0;

            // Done is a pulse at the hierarchy boundary; retain it until
            // software submits the next accepted maintenance command.
            if (cache_flush_done)
                cache_done_latched <= 1'b1;

            if (S_AXI_AWVALID && S_AXI_WVALID && !S_AXI_BVALID) begin
                S_AXI_AWREADY <= 1'b1;
                S_AXI_WREADY  <= 1'b1;
                S_AXI_BVALID  <= 1'b1;
                case (S_AXI_AWADDR[3:2])
                    REG_CTRL: begin
                        // Sticky-OR, not a plain overwrite: once set, a
                        // later write of 0 must NOT clear it (see header:
                        // one-shot release, no software-visible way back
                        // into reset through this register).
                        if (S_AXI_WSTRB[0])
                            go_reg <= go_reg | S_AXI_WDATA[0];
                    end
                    REG_RESULT: begin
                        // Plain overwrite -- the RISC-V program can write
                        // this as many times as it wants (e.g. an initial
                        // "still running" sentinel, then a final PASS/FAIL
                        // code); only the LAST value before the PS reads
                        // it is what matters, no stickiness needed here
                        // unlike REG_CTRL.
                        if (S_AXI_WSTRB[0]) result_reg[7:0]   <= S_AXI_WDATA[7:0];
                        if (S_AXI_WSTRB[1]) result_reg[15:8]  <= S_AXI_WDATA[15:8];
                        if (S_AXI_WSTRB[2]) result_reg[23:16] <= S_AXI_WDATA[23:16];
                        if (S_AXI_WSTRB[3]) result_reg[31:24] <= S_AXI_WDATA[31:24];
                    end
                    REG_CACHE: begin
                        if (S_AXI_WSTRB[0] && S_AXI_WDATA[0]) begin
                            if (go_reg && !cache_flush_busy) begin
                                cache_flush_request  <= 1'b1;
                                cache_done_latched   <= 1'b0;
                                cache_reject_latched <= 1'b0;
                            end
                            else begin
                                cache_reject_latched <= 1'b1;
                            end
                        end
                    end
                    default: ; // REG_STATUS is read-only, writes to it are silently ignored
                endcase
            end
            else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------
    // Read channel
    // ------------------------------------------------------
    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_ARREADY <= 1'b0;
            S_AXI_RVALID  <= 1'b0;
            S_AXI_RDATA   <= 32'b0;
        end
        else begin
            S_AXI_ARREADY <= 1'b0;

            if (S_AXI_ARVALID && !S_AXI_RVALID) begin
                S_AXI_ARREADY <= 1'b1;
                S_AXI_RVALID  <= 1'b1;
                case (S_AXI_ARADDR[3:2])
                    REG_CTRL:   S_AXI_RDATA <= {31'b0, go_reg};
                    REG_STATUS: S_AXI_RDATA <= {31'b0, go_reg};
                    REG_RESULT: S_AXI_RDATA <= result_reg;
                    REG_CACHE:  S_AXI_RDATA <= {28'b0, cache_reject_latched,
                                                cache_flush_error,
                                                cache_done_latched,
                                                cache_flush_busy};
                    default:    S_AXI_RDATA <= 32'b0;
                endcase
            end
            else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

endmodule
