`timescale 1ns / 1ps

// ============================================================
// quad_core_axi_wrapper
//
// Real AXI4 master wrapper around quad_core_soc.v's single "CPU
// MEMORY PORT" (coherence_manager.v's mem_req_valid/mem_we/mem_addr/
// mem_wdata/mem_rdata/mem_valid) -- the counterpart of
// mmu_ip_wrapper.v for the full 4-core system. Drop this into a
// Vivado IP Integrator block design and hook it to AXI Interconnect
// + AXI BRAM Controller / Zynq PS7 HP port, per
// Risc_V_new/scripts/build_soc_4core_trial.tcl.
//
// One combined read/write AXI4 master, not split IMEM/DMEM like
// mmu_ip_wrapper.v -- by the time traffic reaches this port, it has
// already gone through coherence_manager.v's single arbiter, so
// instruction and data misses/writebacks are already serialized
// onto the one mem_* port coherence_manager.v exposes.
//
// Cached writebacks use WSTRB=4'b1111.  Uncached/MMIO SB/SH/SW
// requests bypass L1/L2 and carry their architectural byte strobes
// through coherence_manager's mem_wstrb sideband.
//
// Same protocol-compliance rationale as mmu_ip_wrapper.v: hold
// *VALID until the matching *READY, single outstanding transaction,
// RRESP/BRESP[1] are sampled with the matching completion and carried
// through L2/coherence/L1 to the originating core. A failed line fill
// is never installed; it becomes an instruction/load/store access fault.
// ============================================================
module quad_core_axi_wrapper #(
    parameter [31:0] RESET_ADDR0 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR1 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR2 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR3 = 32'h0000_1000
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF M_AXI, ASSOCIATED_RESET ARESETN" *)
    input  wire        ACLK,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETN RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        ARESETN,

    // ---------------- MMU control (tie off via Constant IP) ----------------
    // Mmu_Enable/Satp_PPN0..3 no longer exist here: each core's own
    // satp CSR is now the real source of truth (quad_core_soc.v's
    // header, core_l1_wrapper.v's header). Mmu_Flush remains -- a
    // real external hook, OR'd with each core's own sfence.vma flush.
    input  wire         Mmu_Flush,
    input  wire         Cache_Flush,
    output wire         Cache_Flush_Busy,
    output wire         Cache_Flush_Done,
    output wire         Cache_Flush_Error,

    // ---------------- Debug ----------------
    output wire [31:0] ResultW0, output wire [31:0] ResultW1, output wire [31:0] ResultW2, output wire [31:0] ResultW3,
    output wire         Fetch_PageFault0, output wire Fetch_PageFault1, output wire Fetch_PageFault2, output wire Fetch_PageFault3,
    output wire         Data_PageFault0,  output wire Data_PageFault1,  output wire Data_PageFault2,  output wire Data_PageFault3,

    // ---------------- AXI4 master (combined read/write) ----------------
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

    wire core_rst = ~ARESETN;

    wire        mem_req_valid;
    wire        mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;
    wire        mem_valid;
    wire        mem_error;

    quad_core_soc #(
        .RESET_ADDR0(RESET_ADDR0), .RESET_ADDR1(RESET_ADDR1),
        .RESET_ADDR2(RESET_ADDR2), .RESET_ADDR3(RESET_ADDR3)
    ) soc (
        .clk(ACLK), .rst(core_rst),
        .Mmu_Flush(Mmu_Flush),
        .Cache_Flush(Cache_Flush),
        .Cache_Flush_Busy(Cache_Flush_Busy), .Cache_Flush_Done(Cache_Flush_Done), .Cache_Flush_Error(Cache_Flush_Error),
        .ResultW0(ResultW0), .ResultW1(ResultW1), .ResultW2(ResultW2), .ResultW3(ResultW3),
        .Fetch_PageFault0(Fetch_PageFault0), .Fetch_PageFault1(Fetch_PageFault1),
        .Fetch_PageFault2(Fetch_PageFault2), .Fetch_PageFault3(Fetch_PageFault3),
        .Data_PageFault0(Data_PageFault0), .Data_PageFault1(Data_PageFault1),
        .Data_PageFault2(Data_PageFault2), .Data_PageFault3(Data_PageFault3),
        .mem_req_valid(mem_req_valid), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata), .mem_valid(mem_valid), .mem_error(mem_error)
    );

    // ------------------------------------------------------
    // Read channel (mem_we == 0) -- same "hold ARVALID until
    // ARREADY, then wait RVALID, RREADY always 1" pattern as
    // mmu_ip_wrapper.v.
    // ------------------------------------------------------
    // coherence_manager emits a one-cycle request pulse, then waits for
    // mem_valid.  Latch that pulse so AXI *VALID remains asserted until
    // the corresponding *READY handshake, including under backpressure.
    reg        req_pending;
    reg        req_we;
    reg [31:0] req_addr;
    reg [31:0] req_wdata;
    reg [3:0]  req_wstrb;
    reg ar_done;
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            req_pending <= 1'b0;
            req_we      <= 1'b0;
            req_addr    <= 32'b0;
            req_wdata   <= 32'b0;
            req_wstrb   <= 4'b0;
            ar_done     <= 1'b0;
        end
        else begin
            if (mem_req_valid && !req_pending) begin
                req_pending <= 1'b1;
                req_we      <= mem_we;
                req_addr    <= mem_addr;
                req_wdata   <= mem_wdata;
                req_wstrb   <= mem_wstrb;
            end
            if (M_AXI_RVALID && M_AXI_RREADY) begin
                req_pending <= 1'b0;
                ar_done     <= 1'b0;
            end
            else if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                ar_done <= 1'b1;
            end
            if (M_AXI_BVALID && M_AXI_BREADY)
                req_pending <= 1'b0;
        end
    end

    assign M_AXI_ARADDR  = req_addr;
    assign M_AXI_ARVALID = req_pending & ~req_we & ~ar_done;
    assign M_AXI_RREADY  = req_pending & ~req_we;
    assign mem_rdata      = M_AXI_RDATA;
    wire   read_done_pulse = M_AXI_RVALID && M_AXI_RREADY;

    // ------------------------------------------------------
    // Write channel (mem_we == 1) -- AWREADY/WREADY tracked
    // independently (AXI4 allows them on different cycles), both
    // held until accepted, then wait BVALID (BREADY always 1).
    // ------------------------------------------------------
    reg aw_done, w_done;
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
        end
        else if (M_AXI_BVALID && M_AXI_BREADY) begin
            aw_done <= 1'b0;
            w_done  <= 1'b0;
        end
        else begin
            if (M_AXI_AWVALID && M_AXI_AWREADY) aw_done <= 1'b1;
            if (M_AXI_WVALID  && M_AXI_WREADY)  w_done  <= 1'b1;
        end
    end

    assign M_AXI_AWADDR  = req_addr;
    assign M_AXI_AWVALID = req_pending & req_we & ~aw_done;
    assign M_AXI_WDATA   = req_wdata;
    assign M_AXI_WSTRB   = req_wstrb;
    assign M_AXI_WVALID  = req_pending & req_we & ~w_done;
    assign M_AXI_BREADY  = req_pending & req_we;
    wire   write_done_pulse = M_AXI_BVALID && M_AXI_BREADY;

    assign mem_valid = req_we ? write_done_pulse : read_done_pulse;
    assign mem_error = req_we ? (write_done_pulse & M_AXI_BRESP[1]) :
                                (read_done_pulse  & M_AXI_RRESP[1]);

endmodule
