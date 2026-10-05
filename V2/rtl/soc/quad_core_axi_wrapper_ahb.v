`timescale 1ns / 1ps

// ============================================================
// quad_core_axi_wrapper_ahb
//
// NEW file, structurally identical to quad_core_axi_wrapper.v (that
// file is NOT modified -- same "new variant, not an edit" policy used
// throughout this session), except it wraps quad_core_soc_ahb.v
// instead of quad_core_soc.v. This exists because of the FINAL
// architecture decision recorded in Risc_V_new/README.md mục 4: the
// bus between the 4 cores and the rest of the system (the diagram's
// "HIGH-SPEED BUS (AHB)") is AHB-Lite -- quad_core_soc_ahb.v (mục
// -0.25.2) is therefore the chosen variant, not quad_core_soc.v. This
// wrapper is what makes that chosen variant reachable from real Vivado
// AXI4 IP (AXI Interconnect / a PS's HP port), exactly the same role
// quad_core_axi_wrapper.v plays for quad_core_soc.v.
//
// quad_core_soc_ahb.v's own external "CPU Memory Port" shape (clk/
// rst/Mmu_Flush/Cache_Flush/ResultW*/Fetch_PageFault*/Data_PageFault*/
// mem_req_valid/mem_we/mem_addr/mem_wdata/mem_rdata/mem_valid) is
// IDENTICAL to quad_core_soc.v's (deliberately -- see that file's own
// header: only the CORE<->BUS wiring inside changed, the box the rest
// of the system sees did not), so every AXI4 FSM/handshake line below
// is a byte-for-byte copy of quad_core_axi_wrapper.v's -- nothing
// about wrapping THIS particular SoC variant in AXI4 is any different.
// See that file's header for the full protocol-compliance rationale
// (hold *VALID until *READY, single outstanding transaction, RRESP/
// BRESP not inspected).
// ============================================================
module quad_core_axi_wrapper_ahb #(
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
    input  wire         Mmu_Flush,
    input  wire         Cache_Flush,

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
    wire [31:0] mem_rdata;
    wire        mem_valid;

    quad_core_soc_ahb #(
        .RESET_ADDR0(RESET_ADDR0), .RESET_ADDR1(RESET_ADDR1),
        .RESET_ADDR2(RESET_ADDR2), .RESET_ADDR3(RESET_ADDR3)
    ) soc (
        .clk(ACLK), .rst(core_rst),
        .Mmu_Flush(Mmu_Flush),
        .Cache_Flush(Cache_Flush),
        .ResultW0(ResultW0), .ResultW1(ResultW1), .ResultW2(ResultW2), .ResultW3(ResultW3),
        .Fetch_PageFault0(Fetch_PageFault0), .Fetch_PageFault1(Fetch_PageFault1),
        .Fetch_PageFault2(Fetch_PageFault2), .Fetch_PageFault3(Fetch_PageFault3),
        .Data_PageFault0(Data_PageFault0), .Data_PageFault1(Data_PageFault1),
        .Data_PageFault2(Data_PageFault2), .Data_PageFault3(Data_PageFault3),
        .mem_req_valid(mem_req_valid), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_valid(mem_valid)
    );

    // ------------------------------------------------------
    // Read channel (mem_we == 0) -- same "hold ARVALID until
    // ARREADY, then wait RVALID, RREADY always 1" pattern as
    // mmu_ip_wrapper.v / quad_core_axi_wrapper.v.
    // ------------------------------------------------------
    reg ar_done;
    always @(posedge ACLK) begin
        if (!ARESETN) ar_done <= 1'b0;
        else if (M_AXI_RVALID && M_AXI_RREADY) ar_done <= 1'b0;
        else if (M_AXI_ARVALID && M_AXI_ARREADY) ar_done <= 1'b1;
    end

    assign M_AXI_ARADDR  = mem_addr;
    assign M_AXI_ARVALID = mem_req_valid & ~mem_we & ~ar_done;
    assign M_AXI_RREADY  = 1'b1;
    assign mem_rdata      = M_AXI_RDATA;
    wire   read_done_pulse = M_AXI_RVALID;

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

    assign M_AXI_AWADDR  = mem_addr;
    assign M_AXI_AWVALID = mem_req_valid & mem_we & ~aw_done;
    assign M_AXI_WDATA   = mem_wdata;
    assign M_AXI_WSTRB   = 4'b1111; // always a full word -- see header
    assign M_AXI_WVALID  = mem_req_valid & mem_we & ~w_done;
    assign M_AXI_BREADY  = 1'b1;
    wire   write_done_pulse = M_AXI_BVALID;

    assign mem_valid = mem_we ? write_done_pulse : read_done_pulse;

endmodule
