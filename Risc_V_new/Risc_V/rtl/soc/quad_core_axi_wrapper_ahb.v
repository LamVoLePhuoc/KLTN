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
// mem_req_valid/mem_we/mem_addr/mem_wdata/mem_wstrb/mem_rdata/mem_valid) is
// IDENTICAL to quad_core_soc.v's (deliberately -- see that file's own
// header: only the CORE<->BUS wiring inside changed, the box the rest
// of the system sees did not), so every AXI4 FSM/handshake line below
// follows the same implementation as quad_core_axi_wrapper.v's -- nothing
// about wrapping THIS particular SoC variant in AXI4 is any different.
// See that file's header for the full protocol-compliance rationale
// (hold *VALID until *READY, single outstanding transaction). RRESP/
// BRESP errors are propagated through coherence, the internal AHB
// bridge and L1 to the originating core as an access fault.
// ============================================================
module quad_core_axi_wrapper_ahb #(
    parameter [31:0] RESET_ADDR0 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR1 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR2 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR3 = 32'h0000_1000,
    parameter        MESI_ENABLE = 1
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
    output wire         Cache_Flush_Busy,
    output wire         Cache_Flush_Done,
    output wire         Cache_Flush_Error,

    // ---------------- Debug ----------------
    output wire [31:0] ResultW0, output wire [31:0] ResultW1, output wire [31:0] ResultW2, output wire [31:0] ResultW3,
    output wire         Fetch_PageFault0, output wire Fetch_PageFault1, output wire Fetch_PageFault2, output wire Fetch_PageFault3,
    output wire         Data_PageFault0,  output wire Data_PageFault1,  output wire Data_PageFault2,  output wire Data_PageFault3,

    // ---------------- AXI4 master (combined read/write) ----------------
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI, PROTOCOL AXI4, ADDR_WIDTH 32, DATA_WIDTH 32, HAS_BURST 1, MAX_BURST_LENGTH 8" *)
    output wire [31:0] M_AXI_AWADDR,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWLEN" *)
    output wire [7:0]  M_AXI_AWLEN,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWSIZE" *)
    output wire [2:0]  M_AXI_AWSIZE,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI AWBURST" *)
    output wire [1:0]  M_AXI_AWBURST,
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
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI WLAST" *)
    output wire        M_AXI_WLAST,
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
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARLEN" *)
    output wire [7:0]  M_AXI_ARLEN,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARSIZE" *)
    output wire [2:0]  M_AXI_ARSIZE,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI ARBURST" *)
    output wire [1:0]  M_AXI_ARBURST,
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
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RLAST" *)
    input  wire        M_AXI_RLAST,
    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI RREADY" *)
    output wire        M_AXI_RREADY
);

    wire core_rst;
    reset_sync u_reset_sync (
        .clk(ACLK), .arst_n(ARESETN),
        .srst(core_rst), .srst_n()
    );

    wire        mem_req_valid;
    wire        mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire        mem_req_burst;
    wire [255:0] mem_wline;
    wire [31:0] mem_rdata;
    wire [255:0] mem_rline;
    wire        mem_valid;
    wire        mem_error;

    quad_core_soc_ahb #(
        .RESET_ADDR0(RESET_ADDR0), .RESET_ADDR1(RESET_ADDR1),
        .RESET_ADDR2(RESET_ADDR2), .RESET_ADDR3(RESET_ADDR3),
        .MESI_ENABLE(MESI_ENABLE), .MEM_BURST_ENABLE(1)
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
        .mem_req_burst(mem_req_burst), .mem_wline(mem_wline),
        .mem_rdata(mem_rdata), .mem_rline(mem_rline), .mem_valid(mem_valid), .mem_error(mem_error)
    );

    // One controller request is outstanding at a time. Cached requests carry
    // an entire 32-byte line and become an eight-beat AXI4 INCR burst. Device
    // requests retain the same state machine with LEN=0. VALID and every
    // payload remain stable under independent channel backpressure.
    reg        req_pending;
    reg        req_we;
    reg        req_burst;
    reg [31:0] req_addr;
    reg [31:0] req_wdata;
    reg [3:0]  req_wstrb;
    reg [255:0] req_wline;
    reg [255:0] read_line_buf;
    reg [2:0]   read_beat;
    reg [2:0]   write_beat;
    reg         read_error_seen;
    reg         ar_done;
    reg         aw_done;
    reg         w_done;

    always @(posedge ACLK) begin
        if (core_rst) begin
            req_pending <= 1'b0;
            req_we      <= 1'b0;
            req_burst   <= 1'b0;
            req_addr    <= 32'b0;
            req_wdata   <= 32'b0;
            req_wstrb   <= 4'b0;
            req_wline   <= 256'b0;
            read_line_buf <= 256'b0;
            read_beat   <= 3'b0;
            write_beat  <= 3'b0;
            read_error_seen <= 1'b0;
            ar_done     <= 1'b0;
            aw_done     <= 1'b0;
            w_done      <= 1'b0;
        end
        else begin
            if (mem_req_valid && !req_pending) begin
                req_pending <= 1'b1;
                req_we      <= mem_we;
                req_burst   <= mem_req_burst;
                req_addr    <= mem_addr;
                req_wdata   <= mem_wdata;
                req_wstrb   <= mem_wstrb;
                req_wline   <= mem_wline;
                read_beat   <= 3'b0;
                write_beat  <= 3'b0;
                read_error_seen <= 1'b0;
                ar_done     <= 1'b0;
                aw_done     <= 1'b0;
                w_done      <= 1'b0;
            end

            if (M_AXI_ARVALID && M_AXI_ARREADY)
                ar_done <= 1'b1;

            if (M_AXI_RVALID && M_AXI_RREADY) begin
                read_line_buf[read_beat*32 +: 32] <= M_AXI_RDATA;
                read_error_seen <= read_error_seen | M_AXI_RRESP[1];
                if (M_AXI_RLAST) begin
                    req_pending <= 1'b0;
                    ar_done     <= 1'b0;
                    read_beat   <= 3'b0;
                end
                else begin
                    read_beat <= read_beat + 3'd1;
                end
            end

            if (M_AXI_AWVALID && M_AXI_AWREADY)
                aw_done <= 1'b1;

            if (M_AXI_WVALID && M_AXI_WREADY) begin
                if (M_AXI_WLAST)
                    w_done <= 1'b1;
                else
                    write_beat <= write_beat + 3'd1;
            end

            if (M_AXI_BVALID && M_AXI_BREADY) begin
                req_pending <= 1'b0;
                aw_done     <= 1'b0;
                w_done      <= 1'b0;
                write_beat  <= 3'b0;
            end
        end
    end

    assign M_AXI_ARADDR  = req_addr;
    assign M_AXI_ARLEN   = req_burst ? 8'd7 : 8'd0;
    assign M_AXI_ARSIZE  = 3'b010;
    assign M_AXI_ARBURST = 2'b01;
    assign M_AXI_ARVALID = req_pending & ~req_we & ~ar_done;
    assign M_AXI_RREADY  = req_pending & ~req_we & ar_done;

    assign M_AXI_AWADDR  = req_addr;
    assign M_AXI_AWLEN   = req_burst ? 8'd7 : 8'd0;
    assign M_AXI_AWSIZE  = 3'b010;
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWVALID = req_pending & req_we & ~aw_done;
    assign M_AXI_WDATA   = req_burst ? req_wline[write_beat*32 +: 32] :
                                       req_wdata;
    assign M_AXI_WSTRB   = req_burst ? 4'b1111 : req_wstrb;
    assign M_AXI_WVALID  = req_pending & req_we & ~w_done;
    assign M_AXI_WLAST   = req_burst ? (write_beat == 3'd7) : 1'b1;
    assign M_AXI_BREADY  = req_pending & req_we & aw_done & w_done;

    wire read_beat_pulse = M_AXI_RVALID && M_AXI_RREADY;
    wire read_done_pulse = read_beat_pulse && M_AXI_RLAST;
    wire   write_done_pulse = M_AXI_BVALID && M_AXI_BREADY;

    reg [255:0] completed_read_line;
    always @(*) begin
        completed_read_line = read_line_buf;
        completed_read_line[read_beat*32 +: 32] = M_AXI_RDATA;
    end

    assign mem_rdata = M_AXI_RDATA;
    assign mem_rline = completed_read_line;
    assign mem_valid = req_we ? write_done_pulse : read_done_pulse;
    assign mem_error = req_we ? (write_done_pulse & M_AXI_BRESP[1]) :
                                (read_done_pulse &
                                 (read_error_seen | M_AXI_RRESP[1] |
                                  (req_burst ? (read_beat != 3'd7) :
                                               (read_beat != 3'd0))));

endmodule
