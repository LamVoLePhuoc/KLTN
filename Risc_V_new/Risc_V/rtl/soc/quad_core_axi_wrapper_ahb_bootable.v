`timescale 1ns / 1ps

// ============================================================
// quad_core_axi_wrapper_ahb_bootable
//
// NEW top-level variant, structurally identical to
// quad_core_axi_wrapper_bootable.v (that file is NOT modified -- same
// "new variant, not an edit" policy used throughout this session)
// except it wraps quad_core_axi_wrapper_ahb.v (the AHB-Lite SoC
// variant) instead of quad_core_axi_wrapper.v (the direct-wire
// variant). This is the ACTUAL top-level scripts/build_soc_zu5ev_boot.tcl
// instantiates as cpu0, per the FINAL architecture decision recorded
// in Risc_V_new/README.md mục 4: AHB-Lite is the chosen bus between
// the 4 cores and the rest of the system, so the real boot-capable
// build should demonstrate THAT variant end to end, not the earlier
// direct-wire one.
//
// Everything else is identical to quad_core_axi_wrapper_bootable.v --
// see that file's header for the full reasoning on why boot_ctrl.v's
// reset-gating has to happen at exactly this level (it is the one
// point where a single signal reaches every core's reset input
// through the whole SoC's reset tree, regardless of which SoC variant
// -- direct-wire or AHB-Lite -- sits underneath).
// ============================================================
module quad_core_axi_wrapper_ahb_bootable #(
    parameter [31:0] RESET_ADDR0 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR1 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR2 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR3 = 32'h0000_1000
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXI:S_AXI_BOOT, ASSOCIATED_RESET ARESETN" *)
    input  wire        ACLK,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        ARESETN,

    // ---------------- MMU control (tie off via Constant IP) ----------------
    input  wire         Mmu_Flush,
    input  wire         Cache_Flush,
    output wire         Cache_Flush_Busy,
    output wire         Cache_Flush_Done,
    output wire         Cache_Flush_Error,

    // ---------------- Debug ----------------
    output wire [31:0] ResultW0, output wire [31:0] ResultW1, output wire [31:0] ResultW2, output wire [31:0] ResultW3,
    output wire         Fetch_PageFault0, output wire Fetch_PageFault1, output wire Fetch_PageFault2, output wire Fetch_PageFault3,
    output wire         Data_PageFault0,  output wire Data_PageFault1,  output wire Data_PageFault2,  output wire Data_PageFault3,

    // ---------------- boot_ctrl's AXI4-Lite slave (PS GP master writes here) ----------------
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT AWADDR" *)
    input  wire [3:0]  S_AXI_BOOT_AWADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT AWVALID" *)
    input  wire        S_AXI_BOOT_AWVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT AWREADY" *)
    output wire        S_AXI_BOOT_AWREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT WDATA" *)
    input  wire [31:0] S_AXI_BOOT_WDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT WSTRB" *)
    input  wire [3:0]  S_AXI_BOOT_WSTRB,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT WVALID" *)
    input  wire        S_AXI_BOOT_WVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT WREADY" *)
    output wire        S_AXI_BOOT_WREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT BRESP" *)
    output wire [1:0]  S_AXI_BOOT_BRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT BVALID" *)
    output wire        S_AXI_BOOT_BVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT BREADY" *)
    input  wire        S_AXI_BOOT_BREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT ARADDR" *)
    input  wire [3:0]  S_AXI_BOOT_ARADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT ARVALID" *)
    input  wire        S_AXI_BOOT_ARVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT ARREADY" *)
    output wire        S_AXI_BOOT_ARREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT RDATA" *)
    output wire [31:0] S_AXI_BOOT_RDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT RRESP" *)
    output wire [1:0]  S_AXI_BOOT_RRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT RVALID" *)
    output wire        S_AXI_BOOT_RVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI_BOOT RREADY" *)
    input  wire        S_AXI_BOOT_RREADY,

    // ---------------- AXI4 master (combined read/write, to DRAM) ----------------
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
    output wire [31:0] M_AXI_AWADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWVALID" *)
    output wire        M_AXI_AWVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWREADY" *)
    input  wire        M_AXI_AWREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WDATA" *)
    output wire [31:0] M_AXI_WDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WSTRB" *)
    output wire [3:0]  M_AXI_WSTRB,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WVALID" *)
    output wire        M_AXI_WVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WREADY" *)
    input  wire        M_AXI_WREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BRESP" *)
    input  wire [1:0]  M_AXI_BRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BVALID" *)
    input  wire        M_AXI_BVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI BREADY" *)
    output wire        M_AXI_BREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARADDR" *)
    output wire [31:0] M_AXI_ARADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARVALID" *)
    output wire        M_AXI_ARVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARREADY" *)
    input  wire        M_AXI_ARREADY,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RDATA" *)
    input  wire [31:0] M_AXI_RDATA,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RRESP" *)
    input  wire [1:0]  M_AXI_RRESP,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RVALID" *)
    input  wire        M_AXI_RVALID,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
    output wire        M_AXI_RREADY
);

    wire core_go;
    wire boot_cache_flush_request;
    wire cache_flush_request = Cache_Flush | boot_cache_flush_request;
    wire gated_ARESETN = ARESETN & core_go;

    boot_ctrl u_boot_ctrl (
        .S_AXI_ACLK(ACLK), .S_AXI_ARESETN(ARESETN), // raw, ungated -- see boot_ctrl.v's header

        .S_AXI_AWADDR(S_AXI_BOOT_AWADDR), .S_AXI_AWVALID(S_AXI_BOOT_AWVALID), .S_AXI_AWREADY(S_AXI_BOOT_AWREADY),
        .S_AXI_WDATA(S_AXI_BOOT_WDATA), .S_AXI_WSTRB(S_AXI_BOOT_WSTRB), .S_AXI_WVALID(S_AXI_BOOT_WVALID), .S_AXI_WREADY(S_AXI_BOOT_WREADY),
        .S_AXI_BRESP(S_AXI_BOOT_BRESP), .S_AXI_BVALID(S_AXI_BOOT_BVALID), .S_AXI_BREADY(S_AXI_BOOT_BREADY),
        .S_AXI_ARADDR(S_AXI_BOOT_ARADDR), .S_AXI_ARVALID(S_AXI_BOOT_ARVALID), .S_AXI_ARREADY(S_AXI_BOOT_ARREADY),
        .S_AXI_RDATA(S_AXI_BOOT_RDATA), .S_AXI_RRESP(S_AXI_BOOT_RRESP), .S_AXI_RVALID(S_AXI_BOOT_RVALID), .S_AXI_RREADY(S_AXI_BOOT_RREADY),

        .core_go(core_go),
        .cache_flush_busy(Cache_Flush_Busy),
        .cache_flush_done(Cache_Flush_Done),
        .cache_flush_error(Cache_Flush_Error),
        .cache_flush_request(boot_cache_flush_request)
    );

    quad_core_axi_wrapper_ahb #(
        .RESET_ADDR0(RESET_ADDR0), .RESET_ADDR1(RESET_ADDR1),
        .RESET_ADDR2(RESET_ADDR2), .RESET_ADDR3(RESET_ADDR3)
    ) u_soc (
        .ACLK(ACLK), .ARESETN(gated_ARESETN),

        .Mmu_Flush(Mmu_Flush), .Cache_Flush(cache_flush_request),
        .Cache_Flush_Busy(Cache_Flush_Busy), .Cache_Flush_Done(Cache_Flush_Done), .Cache_Flush_Error(Cache_Flush_Error),

        .ResultW0(ResultW0), .ResultW1(ResultW1), .ResultW2(ResultW2), .ResultW3(ResultW3),
        .Fetch_PageFault0(Fetch_PageFault0), .Fetch_PageFault1(Fetch_PageFault1),
        .Fetch_PageFault2(Fetch_PageFault2), .Fetch_PageFault3(Fetch_PageFault3),
        .Data_PageFault0(Data_PageFault0), .Data_PageFault1(Data_PageFault1),
        .Data_PageFault2(Data_PageFault2), .Data_PageFault3(Data_PageFault3),

        .M_AXI_AWADDR(M_AXI_AWADDR), .M_AXI_AWVALID(M_AXI_AWVALID), .M_AXI_AWREADY(M_AXI_AWREADY),
        .M_AXI_WDATA(M_AXI_WDATA), .M_AXI_WSTRB(M_AXI_WSTRB), .M_AXI_WVALID(M_AXI_WVALID), .M_AXI_WREADY(M_AXI_WREADY),
        .M_AXI_BRESP(M_AXI_BRESP), .M_AXI_BVALID(M_AXI_BVALID), .M_AXI_BREADY(M_AXI_BREADY),
        .M_AXI_ARADDR(M_AXI_ARADDR), .M_AXI_ARVALID(M_AXI_ARVALID), .M_AXI_ARREADY(M_AXI_ARREADY),
        .M_AXI_RDATA(M_AXI_RDATA), .M_AXI_RRESP(M_AXI_RRESP), .M_AXI_RVALID(M_AXI_RVALID), .M_AXI_RREADY(M_AXI_RREADY)
    );

endmodule
