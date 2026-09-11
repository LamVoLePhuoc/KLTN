`timescale 1ns / 1ps

// ============================================================
// mmu_ip_wrapper
//
// Real AXI4 master wrapper around mmu_core_wrapper (= one RV32IMA
// core + per-core MMU), meant to be dropped into a Vivado IP
// Integrator block design as an RTL module reference and hooked up
// to stock AXI4 IP (AXI Interconnect, AXI BRAM Controller, AXI DMA,
// AXI INTC, ...) per the target architecture diagram's AXI4 system
// bus segment. This is the MMU-integrated counterpart of the
// existing RV32_IP_Wrapper.v (which wraps the plain RV32IMA core,
// no MMU) -- same IMEM/DMEM master split, but:
//
//   1. It drives Instr_ValidF / Mem_ReadDataValidM / Mem_WriteDoneM
//      into mmu_core_wrapper from REAL AXI response timing (RVALID/
//      BVALID), instead of assuming a same-cycle combinational
//      memory. That is what makes it safe to connect to real,
//      multi-cycle-latency Vivado IP -- see the "Multi-cycle
//      memory" note in mmu_core_wrapper.v and the "CAUTION" history
//      in mmu_top.v (now resolved: ptw_mem_valid is threaded all
//      the way from here).
//   2. It reuses the same load_unit/store_unit byte-lane helpers
//      RV32_IP_Wrapper.v uses, fed by Mem_AddrM[1:0]/MemOpM -- this
//      also transparently handles the PTW's own page-table reads,
//      since mmu_core_wrapper always presents MemOpM=3'b010 (word)
//      while walking, and load_unit's LW case is a pure passthrough
//      of raw_data (see load_unit.v) -- no separate PTW data path
//      needed here.
//
// AXI4 protocol notes (single outstanding transaction per channel,
// no bursting/pipelining -- matches how the core issues one access
// at a time anyway):
//   - Each address channel (AR/AW) holds *VALID asserted, combinationally
//     driven from "core wants this access and hasn't seen it complete
//     yet", until the matching *READY fires once.
//   - RREADY/BREADY are held at 1 always (single-beat, unbuffered
//     master -- always ready to accept the response the moment it
//     arrives).
//   - RRESP/BRESP are not inspected (SLVERR/DECERR are treated the
//     same as OKAY, i.e. "the transaction completed"): this core has
//     no trap/exception unit to report a real bus error into yet,
//     matching mmu_core_wrapper's existing "no trap unit" limitation
//     for page faults. Fine for a first architecture trial-fit; not
//     fine to leave silently unfixed once bus errors need to mean
//     something.
//   - Mmu_Enable/Satp_PPN/Mmu_Flush and Snoop_Addr/Snoop_WE are not
//     exposed as AXI-Lite registers here (out of scope for this
//     trial) -- Mmu_Enable/Satp_PPN/Mmu_Flush are plain input ports
//     (tie off with a Constant IP in the block design); Snoop_Addr/
//     Snoop_WE are tied to 0 internally (no sibling core yet).
// ============================================================
module mmu_ip_wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_1000
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXI_IMEM:M_AXI_DMEM, ASSOCIATED_RESET ARESETN" *)
    input  wire        ACLK,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        ARESETN,

    // ---------------- MMU control (tie off via Constant IP) ----------------
    input  wire         Mmu_Enable,
    input  wire [19:0]  Satp_PPN,
    input  wire         Mmu_Flush,

    // ---------------- IMEM AXI4 READ-ONLY MASTER ----------------
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_IMEM ARADDR" *)
    output wire [31:0] M_AXI_IMEM_ARADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_IMEM ARVALID" *)
    output wire        M_AXI_IMEM_ARVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_IMEM ARREADY" *)
    input  wire        M_AXI_IMEM_ARREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_IMEM RDATA" *)
    input  wire [31:0] M_AXI_IMEM_RDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_IMEM RRESP" *)
    input  wire [1:0]  M_AXI_IMEM_RRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_IMEM RVALID" *)
    input  wire        M_AXI_IMEM_RVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_IMEM RREADY" *)
    output wire        M_AXI_IMEM_RREADY,

    // ---------------- DMEM AXI4 READ/WRITE MASTER ----------------
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM AWADDR" *)
    output wire [31:0] M_AXI_DMEM_AWADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM AWVALID" *)
    output wire        M_AXI_DMEM_AWVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM AWREADY" *)
    input  wire        M_AXI_DMEM_AWREADY,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM WDATA" *)
    output wire [31:0] M_AXI_DMEM_WDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM WSTRB" *)
    output wire [3:0]  M_AXI_DMEM_WSTRB,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM WVALID" *)
    output wire        M_AXI_DMEM_WVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM WREADY" *)
    input  wire        M_AXI_DMEM_WREADY,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM BRESP" *)
    input  wire [1:0]  M_AXI_DMEM_BRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM BVALID" *)
    input  wire        M_AXI_DMEM_BVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM BREADY" *)
    output wire        M_AXI_DMEM_BREADY,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM ARADDR" *)
    output wire [31:0] M_AXI_DMEM_ARADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM ARVALID" *)
    output wire        M_AXI_DMEM_ARVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM ARREADY" *)
    input  wire        M_AXI_DMEM_ARREADY,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM RDATA" *)
    input  wire [31:0] M_AXI_DMEM_RDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM RRESP" *)
    input  wire [1:0]  M_AXI_DMEM_RRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM RVALID" *)
    input  wire        M_AXI_DMEM_RVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_DMEM RREADY" *)
    output wire        M_AXI_DMEM_RREADY,

    // ---------------- Debug / status ----------------
    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug,
    output wire        Fetch_PageFault,
    output wire        Data_PageFault,
    output wire [1:0]  Fetch_PageFault_Cause,
    output wire [1:0]  Data_PageFault_Cause
);

    wire core_rst = ~ARESETN;

    // =========================================================
    // Core-side signals (physical-address domain)
    // =========================================================
    wire [31:0] PCF;
    wire [31:0] InstrF;
    wire        Instr_ValidF;

    wire [31:0] Mem_AddrM;
    wire [31:0] Mem_WriteDataM;
    wire        Mem_WriteEnM;
    wire        Mem_ReadEnM;
    wire [2:0]  MemOpM;
    wire [31:0] Mem_ReadDataM;
    wire        Mem_ReadDataValidM;
    wire        Mem_WriteDoneM;

    mmu_core_wrapper #(
        .RESET_ADDR(RESET_ADDR)
    ) dut (
        .clk                (ACLK),
        .rst                (core_rst),
        .Stall_Core_External(1'b0),

        .Mmu_Enable         (Mmu_Enable),
        .Satp_PPN           (Satp_PPN),
        .Mmu_Flush          (Mmu_Flush),

        .Snoop_Addr         (32'b0),
        .Snoop_WE           (1'b0),

        .PCF                (PCF),
        .InstrF             (InstrF),
        .Instr_ValidF       (Instr_ValidF),

        .Mem_AddrM          (Mem_AddrM),
        .Mem_WriteDataM     (Mem_WriteDataM),
        .Mem_WriteEnM       (Mem_WriteEnM),
        .Mem_ReadEnM        (Mem_ReadEnM),
        .MemOpM             (MemOpM),
        .Mem_ReadDataM      (Mem_ReadDataM),
        .Mem_ReadDataValidM (Mem_ReadDataValidM),
        .Mem_WriteDoneM     (Mem_WriteDoneM),

        .ResultW            (ResultW),
        .ALU_ResultE_Debug  (ALU_ResultE_Debug),

        .Fetch_PageFault       (Fetch_PageFault),
        .Data_PageFault        (Data_PageFault),
        .Fetch_PageFault_Cause (Fetch_PageFault_Cause),
        .Data_PageFault_Cause  (Data_PageFault_Cause)
    );

    // =========================================================
    // IMEM read channel (instruction fetch)
    //
    // ARVALID stays asserted (address held stable at PCF, since the
    // core is frozen on a miss/wait via mem_stall) until ARREADY
    // fires once; RREADY is always 1, so RVALID alone means "this
    // beat is accepted this cycle" -- that IS Instr_ValidF.
    // =========================================================
    reg imem_ar_done;

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            imem_ar_done <= 1'b0;
        end
        else if (M_AXI_IMEM_RVALID && M_AXI_IMEM_RREADY) begin
            imem_ar_done <= 1'b0;
        end
        else if (M_AXI_IMEM_ARVALID && M_AXI_IMEM_ARREADY) begin
            imem_ar_done <= 1'b1;
        end
    end

    assign M_AXI_IMEM_ARADDR  = PCF;
    assign M_AXI_IMEM_ARVALID = ~imem_ar_done;
    assign M_AXI_IMEM_RREADY  = 1'b1;
    assign Instr_ValidF       = M_AXI_IMEM_RVALID;
    assign InstrF              = M_AXI_IMEM_RDATA;

    // =========================================================
    // DMEM read channel (core loads + PTW page-table reads, shared
    // -- see mmu_core_wrapper.v's mmu_busy mux)
    // =========================================================
    reg dmem_ar_done;

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            dmem_ar_done <= 1'b0;
        end
        else if (M_AXI_DMEM_RVALID && M_AXI_DMEM_RREADY) begin
            dmem_ar_done <= 1'b0;
        end
        else if (M_AXI_DMEM_ARVALID && M_AXI_DMEM_ARREADY) begin
            dmem_ar_done <= 1'b1;
        end
    end

    assign M_AXI_DMEM_ARADDR  = Mem_AddrM;
    assign M_AXI_DMEM_ARVALID = Mem_ReadEnM & ~dmem_ar_done;
    assign M_AXI_DMEM_RREADY  = 1'b1;
    assign Mem_ReadDataValidM = M_AXI_DMEM_RVALID;

    load_unit u_load_unit (
        .raw_data    (M_AXI_DMEM_RDATA),
        .addr_offset (Mem_AddrM[1:0]),
        .mem_op      (MemOpM),
        .load_data   (Mem_ReadDataM)
    );

    // =========================================================
    // DMEM write channel (core stores only -- the PTW never
    // writes). Single-outstanding: latch address/data/strobe the
    // cycle Mem_WriteEnM first appears, hold AWVALID/WVALID until
    // BVALID retires it.
    // =========================================================
    wire [31:0] store_axi_wdata;
    wire [3:0]  store_axi_wstrb;

    store_unit u_store_unit (
        .store_data  (Mem_WriteDataM),
        .addr_offset (Mem_AddrM[1:0]),
        .mem_op      (MemOpM),
        .axi_wdata   (store_axi_wdata),
        .axi_wstrb   (store_axi_wstrb)
    );

    reg        store_pending;
    reg [31:0] store_addr_reg;
    reg [31:0] store_wdata_reg;
    reg [3:0]  store_wstrb_reg;

    assign M_AXI_DMEM_AWADDR  = store_addr_reg;
    assign M_AXI_DMEM_AWVALID = store_pending;
    assign M_AXI_DMEM_WDATA   = store_wdata_reg;
    assign M_AXI_DMEM_WSTRB   = store_wstrb_reg;
    assign M_AXI_DMEM_WVALID  = store_pending;
    assign M_AXI_DMEM_BREADY  = 1'b1;
    assign Mem_WriteDoneM     = store_pending & M_AXI_DMEM_BVALID;

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            store_pending   <= 1'b0;
            store_addr_reg  <= 32'b0;
            store_wdata_reg <= 32'b0;
            store_wstrb_reg <= 4'b0000;
        end
        else begin
            if (store_pending) begin
                if (M_AXI_DMEM_BVALID) begin
                    store_pending <= 1'b0;
                end
            end
            else if (Mem_WriteEnM) begin
                store_pending   <= 1'b1;
                store_addr_reg  <= Mem_AddrM;
                store_wdata_reg <= store_axi_wdata;
                store_wstrb_reg <= store_axi_wstrb;
            end
        end
    end

endmodule
