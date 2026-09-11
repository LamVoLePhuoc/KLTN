`timescale 1ns / 1ps

// ============================================================
// quad_core_soc_ahb
//
// Same system as quad_core_soc.v (4x core_l1_wrapper + one shared
// coherence_manager: L2 + MESI directory + arbiter), but with each
// core's I$ and D$ line-fill/writeback port reaching coherence_manager
// through a LITERAL AHB-Lite link (ahb_lite_l1_adapter.v as the
// master side, ahb_lite_l1_slave_adapter.v as the slave side) instead
// of the direct custom bus_req/bus_resp wires quad_core_soc.v uses.
//
// This is a NEW, separate top-level variant -- quad_core_soc.v itself
// is untouched (still the direct-wire variant; still what
// quad_core_axi_wrapper.v / build_soc_4core_trial.tcl use today).
// Reasons for a new file rather than editing quad_core_soc.v in
// place:
//   - quad_core_soc.v's direct wiring has already been reasoned
//     through carefully and matches tb_coherence.v's assumptions
//     (that testbench drives l1_dcache/coherence_manager directly,
//     not through this file, but the SIGNAL SHAPES it exercises are
//     exactly coherence_manager.v's native dreq/dresp/dsnoop ports --
//     see ahb_lite_l1_slave_adapter.v's header for why those shapes
//     are preserved unchanged on the far side of the bridge).
//   - Splicing 8 new adapter pairs into an already-reviewed file
//     multiplies the surface area that has to be re-traced by hand
//     with no simulator available; a separate file keeps the two
//     variants independently reviewable, and quad_core_soc.v keeps
//     working exactly as before regardless of what happens here.
//   - Matches this session's established pattern (see Risc_V_new/
//     README.md's "file cũ vs file mới" policy) of adding new
//     integration variants instead of overwriting reviewed ones.
//
// TOPOLOGY: 8 independent point-to-point AHB-Lite links (I$ and D$,
// x4 cores), NOT one shared multi-master AHB-Lite bus. A real AHB-Lite
// bus with >1 master needs its own address-phase arbiter (that is
// what ahb3lite_interconnect-master_reference/ implements, and why it
// was reviewed but not instantiated -- see ahb_lite_l1_adapter.v's
// header: wrong license, missing submodule, multi-layer topology
// overkill for this). Building a second, redundant arbiter here would
// be pointless: coherence_manager.v's own fixed-priority 8-source
// arbiter (see its header) ALREADY does the real cross-core
// arbitration, immediately on the other side of the 8 slave adapters.
// One dedicated point-to-point link per core per cache is standard
// practice for exactly this situation (e.g. an AHB-Lite "layer" per
// master in a real multi-layer interconnect is functionally the same
// idea) and needs no extra arbitration logic of its own.
//
// WHAT DOES / DOES NOT GO THROUGH THE AHB-LITE BRIDGE: only the line-
// fill/writeback request/response path (bus_req/bus_resp <->
// dreq/dresp). The D$ snoop side-channel (dsnoop_valid/type/addr +
// dsnoop_ack_*) connects core_l1_wrapper <-> coherence_manager
// DIRECTLY, exactly as in quad_core_soc.v -- plain AHB-Lite has no
// standard vehicle for a slave-initiated "please invalidate this
// line" request (that needs ACE or a vendor sideband bus, well beyond
// AHB-Lite), and coherence_manager.v's snoop mechanism is already
// independently reasoned through; routing it through a protocol that
// cannot actually express it would not make the design more correct,
// only more complicated. This matches ahb_lite_l1_adapter.v's own
// documented scope (line-fill/writeback traffic only).
//
// KNOWN COST vs quad_core_soc.v: see ahb_lite_l1_slave_adapter.v's
// header for the MESI-state-over-AHB limitation (every fill is
// reported as S regardless of what was actually granted, so a first
// local write after a fill costs an extra RFO round trip it would not
// have needed with the direct wiring). This is the price of putting a
// literal, protocol-compliant AHB-Lite link on that path; use
// quad_core_soc.v instead if that cost matters more than having a
// literal AHB-Lite boundary in the design.
// ============================================================
module quad_core_soc_ahb #(
    parameter [31:0] RESET_ADDR0 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR1 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR2 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR3 = 32'h0000_1000
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        Mmu_Flush,
    input  wire        Cache_Flush,

    output wire [31:0] ResultW0, output wire [31:0] ResultW1, output wire [31:0] ResultW2, output wire [31:0] ResultW3,
    output wire         Fetch_PageFault0, output wire Fetch_PageFault1, output wire Fetch_PageFault2, output wire Fetch_PageFault3,
    output wire         Data_PageFault0,  output wire Data_PageFault1,  output wire Data_PageFault2,  output wire Data_PageFault3,

    // ---- CPU Memory Port (single word, real handshake -- see coherence_manager.v) ----
    output wire         mem_req_valid,
    output wire         mem_we,
    output wire [31:0]  mem_addr,
    output wire [31:0]  mem_wdata,
    input  wire [31:0]  mem_rdata,
    input  wire         mem_valid
);

    wire HRESETn = ~rst; // AHB-Lite convention is active-LOW; every adapter instance below takes this

    // ------------------------------------------------------
    // Per-core cache miss ports (core_l1_wrapper side, unchanged
    // shape/names from quad_core_soc.v)
    // ------------------------------------------------------
    wire         ibus_req_valid   [0:3];
    wire [31:0]  ibus_req_addr    [0:3];
    wire         ibus_resp_valid  [0:3];
    wire [255:0] ibus_resp_line   [0:3];

    wire         dbus_req_valid   [0:3];
    wire [1:0]   dbus_req_type    [0:3];
    wire [31:0]  dbus_req_addr    [0:3];
    wire [255:0] dbus_req_line    [0:3];
    wire         dbus_resp_valid  [0:3];
    wire [255:0] dbus_resp_line   [0:3];
    wire [1:0]   dbus_resp_state  [0:3];

    wire         dsnoop_valid     [0:3];
    wire         dsnoop_type      [0:3];
    wire [31:0]  dsnoop_addr      [0:3];
    wire         dsnoop_ack_valid [0:3];
    wire         dsnoop_ack_hit   [0:3];
    wire         dsnoop_ack_dirty [0:3];
    wire [255:0] dsnoop_ack_line  [0:3];

    wire [31:0] alu_dbg_unused0, alu_dbg_unused1, alu_dbg_unused2, alu_dbg_unused3;
    wire [1:0]  fpc_unused0, fpc_unused1, fpc_unused2, fpc_unused3;
    wire [1:0]  dpc_unused0, dpc_unused1, dpc_unused2, dpc_unused3;

    // ------------------------------------------------------
    // AHB-Lite link wires, per core, I$ and D$ each -- point-to-point
    // (see header: no shared-bus arbiter needed here). HSIZE/HBURST/
    // HPROT/HMASTLOCK are left unconnected at every adapter instance
    // below: the slave adapter has no matching input for them (it
    // always does fixed word/SINGLE transfers by construction, the
    // same fixed shape the master always drives), so there is nothing
    // for them to connect to.
    // ------------------------------------------------------
    wire [31:0] i_haddr   [0:3];
    wire        i_hwrite  [0:3];
    wire [1:0]  i_htrans  [0:3];
    wire [31:0] i_hwdata  [0:3];
    wire [31:0] i_hrdata  [0:3];
    wire        i_hready  [0:3];
    wire [1:0]  i_hresp   [0:3];

    wire [31:0] d_haddr   [0:3];
    wire        d_hwrite  [0:3];
    wire [1:0]  d_htrans  [0:3];
    wire [31:0] d_hwdata  [0:3];
    wire [31:0] d_hrdata  [0:3];
    wire        d_hready  [0:3];
    wire [1:0]  d_hresp   [0:3];

    // ------------------------------------------------------
    // Post-bridge request/response wires (coherence_manager side --
    // exactly the shape its cN_ireq_*/cN_iresp_*/cN_dreq_*/cN_dresp_*
    // ports already expect, unchanged).
    // ------------------------------------------------------
    wire         ireq_valid_w  [0:3];
    wire [31:0]  ireq_addr_w   [0:3];
    wire         iresp_valid_w [0:3];
    wire [255:0] iresp_line_w  [0:3];

    wire         dreq_valid_w  [0:3];
    wire [1:0]   dreq_type_w   [0:3];
    wire [31:0]  dreq_addr_w   [0:3];
    wire [255:0] dreq_line_w   [0:3];
    wire         dresp_valid_w [0:3];
    wire [255:0] dresp_line_w  [0:3];
    wire [1:0]   dresp_state_w [0:3];

    // ------------------------------------------------------
    // Core 0
    // ------------------------------------------------------
    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR0)) core0 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(Cache_Flush),
        .ResultW(ResultW0), .ALU_ResultE_Debug(alu_dbg_unused0),
        .Fetch_PageFault(Fetch_PageFault0), .Data_PageFault(Data_PageFault0),
        .Fetch_PageFault_Cause(fpc_unused0), .Data_PageFault_Cause(dpc_unused0),
        .ibus_req_valid(ibus_req_valid[0]), .ibus_req_addr(ibus_req_addr[0]),
        .ibus_resp_valid(ibus_resp_valid[0]), .ibus_resp_line(ibus_resp_line[0]),
        .dbus_req_valid(dbus_req_valid[0]), .dbus_req_type(dbus_req_type[0]),
        .dbus_req_addr(dbus_req_addr[0]), .dbus_req_line(dbus_req_line[0]),
        .dbus_resp_valid(dbus_resp_valid[0]), .dbus_resp_line(dbus_resp_line[0]), .dbus_resp_state(dbus_resp_state[0]),
        .dsnoop_valid(dsnoop_valid[0]), .dsnoop_type(dsnoop_type[0]), .dsnoop_addr(dsnoop_addr[0]),
        .dsnoop_ack_valid(dsnoop_ack_valid[0]), .dsnoop_ack_hit(dsnoop_ack_hit[0]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[0]), .dsnoop_ack_line(dsnoop_ack_line[0])
    );

    ahb_lite_l1_adapter u0_i_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn),
        .bus_req_valid(ibus_req_valid[0]), .bus_req_type(2'b00),
        .bus_req_addr(ibus_req_addr[0]), .bus_req_line(256'b0),
        .bus_resp_valid(ibus_resp_valid[0]), .bus_resp_line(ibus_resp_line[0]), .bus_resp_state(),
        .HADDR(i_haddr[0]), .HWRITE(i_hwrite[0]), .HSIZE(), .HTRANS(i_htrans[0]),
        .HWDATA(i_hwdata[0]), .HBURST(), .HPROT(), .HMASTLOCK(),
        .HRDATA(i_hrdata[0]), .HREADY(i_hready[0]), .HRESP(i_hresp[0])
    );
    ahb_lite_l1_slave_adapter u0_i_ahb_s (
        .HCLK(clk), .HRESETn(HRESETn),
        .HADDR(i_haddr[0]), .HWRITE(i_hwrite[0]), .HTRANS(i_htrans[0]), .HWDATA(i_hwdata[0]),
        .HREADYOUT(i_hready[0]), .HRDATA(i_hrdata[0]), .HRESP(i_hresp[0]),
        .dreq_valid(ireq_valid_w[0]), .dreq_type(), .dreq_addr(ireq_addr_w[0]), .dreq_line(),
        .dresp_valid(iresp_valid_w[0]), .dresp_line(iresp_line_w[0]), .dresp_state(2'b00)
    );

    ahb_lite_l1_adapter u0_d_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn),
        .bus_req_valid(dbus_req_valid[0]), .bus_req_type(dbus_req_type[0]),
        .bus_req_addr(dbus_req_addr[0]), .bus_req_line(dbus_req_line[0]),
        .bus_resp_valid(dbus_resp_valid[0]), .bus_resp_line(dbus_resp_line[0]), .bus_resp_state(dbus_resp_state[0]),
        .HADDR(d_haddr[0]), .HWRITE(d_hwrite[0]), .HSIZE(), .HTRANS(d_htrans[0]),
        .HWDATA(d_hwdata[0]), .HBURST(), .HPROT(), .HMASTLOCK(),
        .HRDATA(d_hrdata[0]), .HREADY(d_hready[0]), .HRESP(d_hresp[0])
    );
    ahb_lite_l1_slave_adapter u0_d_ahb_s (
        .HCLK(clk), .HRESETn(HRESETn),
        .HADDR(d_haddr[0]), .HWRITE(d_hwrite[0]), .HTRANS(d_htrans[0]), .HWDATA(d_hwdata[0]),
        .HREADYOUT(d_hready[0]), .HRDATA(d_hrdata[0]), .HRESP(d_hresp[0]),
        .dreq_valid(dreq_valid_w[0]), .dreq_type(dreq_type_w[0]),
        .dreq_addr(dreq_addr_w[0]), .dreq_line(dreq_line_w[0]),
        .dresp_valid(dresp_valid_w[0]), .dresp_line(dresp_line_w[0]), .dresp_state(dresp_state_w[0])
    );

    // ------------------------------------------------------
    // Core 1
    // ------------------------------------------------------
    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR1)) core1 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(Cache_Flush),
        .ResultW(ResultW1), .ALU_ResultE_Debug(alu_dbg_unused1),
        .Fetch_PageFault(Fetch_PageFault1), .Data_PageFault(Data_PageFault1),
        .Fetch_PageFault_Cause(fpc_unused1), .Data_PageFault_Cause(dpc_unused1),
        .ibus_req_valid(ibus_req_valid[1]), .ibus_req_addr(ibus_req_addr[1]),
        .ibus_resp_valid(ibus_resp_valid[1]), .ibus_resp_line(ibus_resp_line[1]),
        .dbus_req_valid(dbus_req_valid[1]), .dbus_req_type(dbus_req_type[1]),
        .dbus_req_addr(dbus_req_addr[1]), .dbus_req_line(dbus_req_line[1]),
        .dbus_resp_valid(dbus_resp_valid[1]), .dbus_resp_line(dbus_resp_line[1]), .dbus_resp_state(dbus_resp_state[1]),
        .dsnoop_valid(dsnoop_valid[1]), .dsnoop_type(dsnoop_type[1]), .dsnoop_addr(dsnoop_addr[1]),
        .dsnoop_ack_valid(dsnoop_ack_valid[1]), .dsnoop_ack_hit(dsnoop_ack_hit[1]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[1]), .dsnoop_ack_line(dsnoop_ack_line[1])
    );

    ahb_lite_l1_adapter u1_i_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn),
        .bus_req_valid(ibus_req_valid[1]), .bus_req_type(2'b00),
        .bus_req_addr(ibus_req_addr[1]), .bus_req_line(256'b0),
        .bus_resp_valid(ibus_resp_valid[1]), .bus_resp_line(ibus_resp_line[1]), .bus_resp_state(),
        .HADDR(i_haddr[1]), .HWRITE(i_hwrite[1]), .HSIZE(), .HTRANS(i_htrans[1]),
        .HWDATA(i_hwdata[1]), .HBURST(), .HPROT(), .HMASTLOCK(),
        .HRDATA(i_hrdata[1]), .HREADY(i_hready[1]), .HRESP(i_hresp[1])
    );
    ahb_lite_l1_slave_adapter u1_i_ahb_s (
        .HCLK(clk), .HRESETn(HRESETn),
        .HADDR(i_haddr[1]), .HWRITE(i_hwrite[1]), .HTRANS(i_htrans[1]), .HWDATA(i_hwdata[1]),
        .HREADYOUT(i_hready[1]), .HRDATA(i_hrdata[1]), .HRESP(i_hresp[1]),
        .dreq_valid(ireq_valid_w[1]), .dreq_type(), .dreq_addr(ireq_addr_w[1]), .dreq_line(),
        .dresp_valid(iresp_valid_w[1]), .dresp_line(iresp_line_w[1]), .dresp_state(2'b00)
    );

    ahb_lite_l1_adapter u1_d_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn),
        .bus_req_valid(dbus_req_valid[1]), .bus_req_type(dbus_req_type[1]),
        .bus_req_addr(dbus_req_addr[1]), .bus_req_line(dbus_req_line[1]),
        .bus_resp_valid(dbus_resp_valid[1]), .bus_resp_line(dbus_resp_line[1]), .bus_resp_state(dbus_resp_state[1]),
        .HADDR(d_haddr[1]), .HWRITE(d_hwrite[1]), .HSIZE(), .HTRANS(d_htrans[1]),
        .HWDATA(d_hwdata[1]), .HBURST(), .HPROT(), .HMASTLOCK(),
        .HRDATA(d_hrdata[1]), .HREADY(d_hready[1]), .HRESP(d_hresp[1])
    );
    ahb_lite_l1_slave_adapter u1_d_ahb_s (
        .HCLK(clk), .HRESETn(HRESETn),
        .HADDR(d_haddr[1]), .HWRITE(d_hwrite[1]), .HTRANS(d_htrans[1]), .HWDATA(d_hwdata[1]),
        .HREADYOUT(d_hready[1]), .HRDATA(d_hrdata[1]), .HRESP(d_hresp[1]),
        .dreq_valid(dreq_valid_w[1]), .dreq_type(dreq_type_w[1]),
        .dreq_addr(dreq_addr_w[1]), .dreq_line(dreq_line_w[1]),
        .dresp_valid(dresp_valid_w[1]), .dresp_line(dresp_line_w[1]), .dresp_state(dresp_state_w[1])
    );

    // ------------------------------------------------------
    // Core 2
    // ------------------------------------------------------
    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR2)) core2 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(Cache_Flush),
        .ResultW(ResultW2), .ALU_ResultE_Debug(alu_dbg_unused2),
        .Fetch_PageFault(Fetch_PageFault2), .Data_PageFault(Data_PageFault2),
        .Fetch_PageFault_Cause(fpc_unused2), .Data_PageFault_Cause(dpc_unused2),
        .ibus_req_valid(ibus_req_valid[2]), .ibus_req_addr(ibus_req_addr[2]),
        .ibus_resp_valid(ibus_resp_valid[2]), .ibus_resp_line(ibus_resp_line[2]),
        .dbus_req_valid(dbus_req_valid[2]), .dbus_req_type(dbus_req_type[2]),
        .dbus_req_addr(dbus_req_addr[2]), .dbus_req_line(dbus_req_line[2]),
        .dbus_resp_valid(dbus_resp_valid[2]), .dbus_resp_line(dbus_resp_line[2]), .dbus_resp_state(dbus_resp_state[2]),
        .dsnoop_valid(dsnoop_valid[2]), .dsnoop_type(dsnoop_type[2]), .dsnoop_addr(dsnoop_addr[2]),
        .dsnoop_ack_valid(dsnoop_ack_valid[2]), .dsnoop_ack_hit(dsnoop_ack_hit[2]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[2]), .dsnoop_ack_line(dsnoop_ack_line[2])
    );

    ahb_lite_l1_adapter u2_i_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn),
        .bus_req_valid(ibus_req_valid[2]), .bus_req_type(2'b00),
        .bus_req_addr(ibus_req_addr[2]), .bus_req_line(256'b0),
        .bus_resp_valid(ibus_resp_valid[2]), .bus_resp_line(ibus_resp_line[2]), .bus_resp_state(),
        .HADDR(i_haddr[2]), .HWRITE(i_hwrite[2]), .HSIZE(), .HTRANS(i_htrans[2]),
        .HWDATA(i_hwdata[2]), .HBURST(), .HPROT(), .HMASTLOCK(),
        .HRDATA(i_hrdata[2]), .HREADY(i_hready[2]), .HRESP(i_hresp[2])
    );
    ahb_lite_l1_slave_adapter u2_i_ahb_s (
        .HCLK(clk), .HRESETn(HRESETn),
        .HADDR(i_haddr[2]), .HWRITE(i_hwrite[2]), .HTRANS(i_htrans[2]), .HWDATA(i_hwdata[2]),
        .HREADYOUT(i_hready[2]), .HRDATA(i_hrdata[2]), .HRESP(i_hresp[2]),
        .dreq_valid(ireq_valid_w[2]), .dreq_type(), .dreq_addr(ireq_addr_w[2]), .dreq_line(),
        .dresp_valid(iresp_valid_w[2]), .dresp_line(iresp_line_w[2]), .dresp_state(2'b00)
    );

    ahb_lite_l1_adapter u2_d_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn),
        .bus_req_valid(dbus_req_valid[2]), .bus_req_type(dbus_req_type[2]),
        .bus_req_addr(dbus_req_addr[2]), .bus_req_line(dbus_req_line[2]),
        .bus_resp_valid(dbus_resp_valid[2]), .bus_resp_line(dbus_resp_line[2]), .bus_resp_state(dbus_resp_state[2]),
        .HADDR(d_haddr[2]), .HWRITE(d_hwrite[2]), .HSIZE(), .HTRANS(d_htrans[2]),
        .HWDATA(d_hwdata[2]), .HBURST(), .HPROT(), .HMASTLOCK(),
        .HRDATA(d_hrdata[2]), .HREADY(d_hready[2]), .HRESP(d_hresp[2])
    );
    ahb_lite_l1_slave_adapter u2_d_ahb_s (
        .HCLK(clk), .HRESETn(HRESETn),
        .HADDR(d_haddr[2]), .HWRITE(d_hwrite[2]), .HTRANS(d_htrans[2]), .HWDATA(d_hwdata[2]),
        .HREADYOUT(d_hready[2]), .HRDATA(d_hrdata[2]), .HRESP(d_hresp[2]),
        .dreq_valid(dreq_valid_w[2]), .dreq_type(dreq_type_w[2]),
        .dreq_addr(dreq_addr_w[2]), .dreq_line(dreq_line_w[2]),
        .dresp_valid(dresp_valid_w[2]), .dresp_line(dresp_line_w[2]), .dresp_state(dresp_state_w[2])
    );

    // ------------------------------------------------------
    // Core 3
    // ------------------------------------------------------
    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR3)) core3 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(Cache_Flush),
        .ResultW(ResultW3), .ALU_ResultE_Debug(alu_dbg_unused3),
        .Fetch_PageFault(Fetch_PageFault3), .Data_PageFault(Data_PageFault3),
        .Fetch_PageFault_Cause(fpc_unused3), .Data_PageFault_Cause(dpc_unused3),
        .ibus_req_valid(ibus_req_valid[3]), .ibus_req_addr(ibus_req_addr[3]),
        .ibus_resp_valid(ibus_resp_valid[3]), .ibus_resp_line(ibus_resp_line[3]),
        .dbus_req_valid(dbus_req_valid[3]), .dbus_req_type(dbus_req_type[3]),
        .dbus_req_addr(dbus_req_addr[3]), .dbus_req_line(dbus_req_line[3]),
        .dbus_resp_valid(dbus_resp_valid[3]), .dbus_resp_line(dbus_resp_line[3]), .dbus_resp_state(dbus_resp_state[3]),
        .dsnoop_valid(dsnoop_valid[3]), .dsnoop_type(dsnoop_type[3]), .dsnoop_addr(dsnoop_addr[3]),
        .dsnoop_ack_valid(dsnoop_ack_valid[3]), .dsnoop_ack_hit(dsnoop_ack_hit[3]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[3]), .dsnoop_ack_line(dsnoop_ack_line[3])
    );

    ahb_lite_l1_adapter u3_i_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn),
        .bus_req_valid(ibus_req_valid[3]), .bus_req_type(2'b00),
        .bus_req_addr(ibus_req_addr[3]), .bus_req_line(256'b0),
        .bus_resp_valid(ibus_resp_valid[3]), .bus_resp_line(ibus_resp_line[3]), .bus_resp_state(),
        .HADDR(i_haddr[3]), .HWRITE(i_hwrite[3]), .HSIZE(), .HTRANS(i_htrans[3]),
        .HWDATA(i_hwdata[3]), .HBURST(), .HPROT(), .HMASTLOCK(),
        .HRDATA(i_hrdata[3]), .HREADY(i_hready[3]), .HRESP(i_hresp[3])
    );
    ahb_lite_l1_slave_adapter u3_i_ahb_s (
        .HCLK(clk), .HRESETn(HRESETn),
        .HADDR(i_haddr[3]), .HWRITE(i_hwrite[3]), .HTRANS(i_htrans[3]), .HWDATA(i_hwdata[3]),
        .HREADYOUT(i_hready[3]), .HRDATA(i_hrdata[3]), .HRESP(i_hresp[3]),
        .dreq_valid(ireq_valid_w[3]), .dreq_type(), .dreq_addr(ireq_addr_w[3]), .dreq_line(),
        .dresp_valid(iresp_valid_w[3]), .dresp_line(iresp_line_w[3]), .dresp_state(2'b00)
    );

    ahb_lite_l1_adapter u3_d_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn),
        .bus_req_valid(dbus_req_valid[3]), .bus_req_type(dbus_req_type[3]),
        .bus_req_addr(dbus_req_addr[3]), .bus_req_line(dbus_req_line[3]),
        .bus_resp_valid(dbus_resp_valid[3]), .bus_resp_line(dbus_resp_line[3]), .bus_resp_state(dbus_resp_state[3]),
        .HADDR(d_haddr[3]), .HWRITE(d_hwrite[3]), .HSIZE(), .HTRANS(d_htrans[3]),
        .HWDATA(d_hwdata[3]), .HBURST(), .HPROT(), .HMASTLOCK(),
        .HRDATA(d_hrdata[3]), .HREADY(d_hready[3]), .HRESP(d_hresp[3])
    );
    ahb_lite_l1_slave_adapter u3_d_ahb_s (
        .HCLK(clk), .HRESETn(HRESETn),
        .HADDR(d_haddr[3]), .HWRITE(d_hwrite[3]), .HTRANS(d_htrans[3]), .HWDATA(d_hwdata[3]),
        .HREADYOUT(d_hready[3]), .HRDATA(d_hrdata[3]), .HRESP(d_hresp[3]),
        .dreq_valid(dreq_valid_w[3]), .dreq_type(dreq_type_w[3]),
        .dreq_addr(dreq_addr_w[3]), .dreq_line(dreq_line_w[3]),
        .dresp_valid(dresp_valid_w[3]), .dresp_line(dresp_line_w[3]), .dresp_state(dresp_state_w[3])
    );

    // ------------------------------------------------------
    // Shared L2 + MESI directory + arbiter. Same instantiation as
    // quad_core_soc.v, except the dreq/dresp/ireq/iresp connections
    // now come from the far side of the AHB-Lite bridge above instead
    // of directly from core_l1_wrapper -- dsnoop_* still connects
    // directly to each core (see header: not bridged).
    // ------------------------------------------------------
    coherence_manager u_coherence_manager (
        .clk(clk), .rst(rst),

        .c0_dreq_valid(dreq_valid_w[0]), .c0_dreq_type(dreq_type_w[0]), .c0_dreq_addr(dreq_addr_w[0]), .c0_dreq_line(dreq_line_w[0]),
        .c0_dresp_valid(dresp_valid_w[0]), .c0_dresp_line(dresp_line_w[0]), .c0_dresp_state(dresp_state_w[0]),
        .c0_dsnoop_valid(dsnoop_valid[0]), .c0_dsnoop_type(dsnoop_type[0]), .c0_dsnoop_addr(dsnoop_addr[0]),
        .c0_dsnoop_ack_valid(dsnoop_ack_valid[0]), .c0_dsnoop_ack_hit(dsnoop_ack_hit[0]),
        .c0_dsnoop_ack_dirty(dsnoop_ack_dirty[0]), .c0_dsnoop_ack_line(dsnoop_ack_line[0]),
        .c0_ireq_valid(ireq_valid_w[0]), .c0_ireq_addr(ireq_addr_w[0]),
        .c0_iresp_valid(iresp_valid_w[0]), .c0_iresp_line(iresp_line_w[0]),

        .c1_dreq_valid(dreq_valid_w[1]), .c1_dreq_type(dreq_type_w[1]), .c1_dreq_addr(dreq_addr_w[1]), .c1_dreq_line(dreq_line_w[1]),
        .c1_dresp_valid(dresp_valid_w[1]), .c1_dresp_line(dresp_line_w[1]), .c1_dresp_state(dresp_state_w[1]),
        .c1_dsnoop_valid(dsnoop_valid[1]), .c1_dsnoop_type(dsnoop_type[1]), .c1_dsnoop_addr(dsnoop_addr[1]),
        .c1_dsnoop_ack_valid(dsnoop_ack_valid[1]), .c1_dsnoop_ack_hit(dsnoop_ack_hit[1]),
        .c1_dsnoop_ack_dirty(dsnoop_ack_dirty[1]), .c1_dsnoop_ack_line(dsnoop_ack_line[1]),
        .c1_ireq_valid(ireq_valid_w[1]), .c1_ireq_addr(ireq_addr_w[1]),
        .c1_iresp_valid(iresp_valid_w[1]), .c1_iresp_line(iresp_line_w[1]),

        .c2_dreq_valid(dreq_valid_w[2]), .c2_dreq_type(dreq_type_w[2]), .c2_dreq_addr(dreq_addr_w[2]), .c2_dreq_line(dreq_line_w[2]),
        .c2_dresp_valid(dresp_valid_w[2]), .c2_dresp_line(dresp_line_w[2]), .c2_dresp_state(dresp_state_w[2]),
        .c2_dsnoop_valid(dsnoop_valid[2]), .c2_dsnoop_type(dsnoop_type[2]), .c2_dsnoop_addr(dsnoop_addr[2]),
        .c2_dsnoop_ack_valid(dsnoop_ack_valid[2]), .c2_dsnoop_ack_hit(dsnoop_ack_hit[2]),
        .c2_dsnoop_ack_dirty(dsnoop_ack_dirty[2]), .c2_dsnoop_ack_line(dsnoop_ack_line[2]),
        .c2_ireq_valid(ireq_valid_w[2]), .c2_ireq_addr(ireq_addr_w[2]),
        .c2_iresp_valid(iresp_valid_w[2]), .c2_iresp_line(iresp_line_w[2]),

        .c3_dreq_valid(dreq_valid_w[3]), .c3_dreq_type(dreq_type_w[3]), .c3_dreq_addr(dreq_addr_w[3]), .c3_dreq_line(dreq_line_w[3]),
        .c3_dresp_valid(dresp_valid_w[3]), .c3_dresp_line(dresp_line_w[3]), .c3_dresp_state(dresp_state_w[3]),
        .c3_dsnoop_valid(dsnoop_valid[3]), .c3_dsnoop_type(dsnoop_type[3]), .c3_dsnoop_addr(dsnoop_addr[3]),
        .c3_dsnoop_ack_valid(dsnoop_ack_valid[3]), .c3_dsnoop_ack_hit(dsnoop_ack_hit[3]),
        .c3_dsnoop_ack_dirty(dsnoop_ack_dirty[3]), .c3_dsnoop_ack_line(dsnoop_ack_line[3]),
        .c3_ireq_valid(ireq_valid_w[3]), .c3_ireq_addr(ireq_addr_w[3]),
        .c3_iresp_valid(iresp_valid_w[3]), .c3_iresp_line(iresp_line_w[3]),

        .mem_req_valid(mem_req_valid), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_valid(mem_valid)
    );

endmodule
