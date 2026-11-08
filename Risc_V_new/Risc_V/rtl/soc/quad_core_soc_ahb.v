`timescale 1ns / 1ps

// ============================================================
// quad_core_soc_ahb
//
// Same system as quad_core_soc.v (4x core_l1_wrapper + one shared
// cache_controller_mmu beside a shared L2), but with each core's I$
// and D$ line-fill/writeback/uncached port reaching the controller
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
//     (that testbench drives l1_dcache/cache_controller_mmu directly,
//     not through this file, but the SIGNAL SHAPES it exercises are
//     exactly the controller's native dreq/dresp/dsnoop ports --
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
// TOPOLOGY: one shared, eight-master AHB-Lite bus.  D$0..D$3 are
// masters 0..3 and I$0..I$3 are masters 4..7.  The standalone
// ahb_lite_arbiter_8m1s owns round-robin selection and holds a grant
// across the complete eight-word cache-line transaction.  The shared
// slave adapter then presents one pre-arbitrated request plus its source
// ID to cache_controller_mmu.  The controller's legacy internal arbiter
// remains available only for the direct-wire and unit-test variants.
//
// WHAT DOES / DOES NOT GO THROUGH THE AHB-LITE BRIDGE: the line-
// fill/writeback and uncached/MMIO request/response path (bus_req/bus_resp <->
// dreq/dresp). The D$ snoop side-channel (dsnoop_valid/type/addr +
// dsnoop_ack_*) connects core_l1_wrapper <-> cache_controller_mmu
// DIRECTLY, exactly as in quad_core_soc.v -- plain AHB-Lite has no
// standard vehicle for a slave-initiated "please invalidate this
// line" request (that needs ACE or a vendor sideband bus, well beyond
// AHB-Lite), and the controller's snoop mechanism is already
// independently reasoned through; routing it through a protocol that
// cannot actually express it would not make the design more correct,
// only more complicated. This matches ahb_lite_l1_adapter.v's own
// documented scope (request/response traffic only).
//
// MSI maps directly onto this bridge: every read fill is S, and an
// RFO/upgrade is marked with HMASTLOCK so the slave reconstructs the
// ownership request before forwarding it to cache_controller_mmu.
// ============================================================
module quad_core_soc_ahb #(
    parameter [31:0] RESET_ADDR0 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR1 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR2 = 32'h0000_1000,
    parameter [31:0] RESET_ADDR3 = 32'h0000_1000,
    parameter        CACHE_DEBUG_TRACE_ENABLE = 0
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        Mmu_Flush,
    input  wire        Cache_Flush,
    output wire        Cache_Flush_Busy,
    output wire        Cache_Flush_Done,
    output wire        Cache_Flush_Error,

    output wire [31:0] ResultW0, output wire [31:0] ResultW1, output wire [31:0] ResultW2, output wire [31:0] ResultW3,
    output wire         Fetch_PageFault0, output wire Fetch_PageFault1, output wire Fetch_PageFault2, output wire Fetch_PageFault3,
    output wire         Data_PageFault0,  output wire Data_PageFault1,  output wire Data_PageFault2,  output wire Data_PageFault3,

    // ---- CPU Memory Port (single word, real handshake -- see cache_controller_mmu.v) ----
    output wire         mem_req_valid,
    output wire         mem_we,
    output wire [31:0]  mem_addr,
    output wire [31:0]  mem_wdata,
    output wire [3:0]   mem_wstrb,
    input  wire [31:0]  mem_rdata,
    input  wire         mem_valid,
    input  wire         mem_error
);

    wire HRESETn = ~rst; // AHB-Lite convention is active-LOW; every adapter instance below takes this

    // ------------------------------------------------------
    // Per-core cache miss ports (core_l1_wrapper side, unchanged
    // shape/names from quad_core_soc.v)
    // ------------------------------------------------------
    wire         ibus_req_valid   [0:3];
    wire [31:0]  ibus_req_addr    [0:3];
    wire         ibus_resp_valid  [0:3];
    wire         ibus_resp_error  [0:3];
    wire [255:0] ibus_resp_line   [0:3];

    wire         dbus_req_valid   [0:3];
    wire [1:0]   dbus_req_type    [0:3];
    wire [31:0]  dbus_req_addr    [0:3];
    wire [255:0] dbus_req_line    [0:3];
    wire         dbus_resp_valid  [0:3];
    wire         dbus_resp_error  [0:3];
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

    (* mark_debug = "true" *) wire [31:0] cache_perf_total_requests;
    (* mark_debug = "true" *) wire [31:0] cache_perf_d_bus_reads;
    (* mark_debug = "true" *) wire [31:0] cache_perf_d_rfos;
    (* mark_debug = "true" *) wire [31:0] cache_perf_d_writebacks;
    (* mark_debug = "true" *) wire [31:0] cache_perf_i_reads;
    (* mark_debug = "true" *) wire [31:0] cache_perf_l2_hits;
    (* mark_debug = "true" *) wire [31:0] cache_perf_l2_misses;
    (* mark_debug = "true" *) wire [31:0] cache_perf_snoop_requests;
    (* mark_debug = "true" *) wire [31:0] cache_perf_mem_read_words;
    (* mark_debug = "true" *) wire [31:0] cache_perf_mem_write_words;
    (* mark_debug = "true" *) wire [31:0] cache_perf_busy_cycles;
    (* mark_debug = "true" *) wire        cache_protocol_error;
    (* mark_debug = "true" *) wire        cache_timeout_error;
    (* mark_debug = "true" *) wire        cache_memory_error;
    (* mark_debug = "true" *) wire [95:0] cache_debug_trace_entry0;
    (* mark_debug = "true" *) wire [4:0]  cache_debug_trace_count;
    (* mark_debug = "true" *) wire [3:0]  cache_debug_trace_write_index;
    (* mark_debug = "true" *) wire [3:0]  cache_debug_controller_state;

    // Explicit controller <-> shared-L2 control/status boundary.
    wire         l2_cmd_valid;
    wire         l2_cmd_we;
    wire [31:0]  l2_cmd_addr;
    wire [1:0]   l2_cmd_way;
    wire [255:0] l2_cmd_wdata;
    wire         l2_cmd_w_valid;
    wire         l2_cmd_w_dirty;
    wire [3:0]   l2_cmd_w_sharers;
    wire         l2_resp_valid;
    wire         l2_resp_hit;
    wire [1:0]   l2_resp_way;
    wire [14:0]  l2_resp_victim_tag;
    wire         l2_resp_victim_valid;
    wire         l2_resp_victim_dirty;
    wire [3:0]   l2_resp_victim_sharers;
    wire [255:0] l2_resp_line;
    wire [3:0]   l2_resp_sharers;
    wire         l2_maint_valid;
    wire [11:0]  l2_maint_set;
    wire [1:0]   l2_maint_way;
    wire         l2_maint_invalidate;
    wire         l2_maint_ready;
    wire         l2_maint_resp_valid;
    wire         l2_maint_line_valid;
    wire         l2_maint_line_dirty;
    wire [14:0]  l2_maint_line_tag;
    wire [255:0] l2_maint_line_data;

    // ------------------------------------------------------
    // Per-master AHB-Lite wires feeding the shared round-robin arbiter. HSIZE and
    // HPROT[3] are connected so the D$ can transport byte/half/word
    // uncached MMIO while HMASTLOCK preserves RFO/upgrade semantics.
    // ------------------------------------------------------
    wire [31:0] i_haddr   [0:3];
    wire        i_hwrite  [0:3];
    wire [1:0]  i_htrans  [0:3];
    wire [31:0] i_hwdata  [0:3];
    wire [31:0] i_hrdata  [0:3];
    wire        i_hready  [0:3];
    wire [1:0]  i_hresp   [0:3];
    wire        i_hmastlock [0:3];
    wire [2:0]  i_hsize   [0:3];
    wire [3:0]  i_hprot   [0:3];
    wire        i_req_active [0:3];

    wire [31:0] d_haddr   [0:3];
    wire        d_hwrite  [0:3];
    wire [1:0]  d_htrans  [0:3];
    wire [31:0] d_hwdata  [0:3];
    wire [31:0] d_hrdata  [0:3];
    wire        d_hready  [0:3];
    wire [1:0]  d_hresp   [0:3];
    wire        d_hmastlock [0:3];
    wire [2:0]  d_hsize   [0:3];
    wire [3:0]  d_hprot   [0:3];
    wire        d_req_active [0:3];

    // Flattened eight-master AHB bus. Master IDs are 0..3 D$, 4..7 I$.
    wire [255:0] ahb_m_haddr;
    wire [7:0]   ahb_m_hwrite;
    wire [23:0]  ahb_m_hsize;
    wire [15:0]  ahb_m_htrans;
    wire [255:0] ahb_m_hwdata;
    wire [31:0]  ahb_m_hprot;
    wire [7:0]   ahb_m_hmastlock;
    wire [7:0]   ahb_m_req_active;
    wire [7:0]   ahb_m_hgrant;
    wire [7:0]   ahb_m_hready;
    wire [255:0] ahb_m_hrdata;
    wire [15:0]  ahb_m_hresp;

    wire [31:0] shared_haddr;
    wire        shared_hwrite;
    wire [2:0]  shared_hsize;
    wire [1:0]  shared_htrans;
    wire [31:0] shared_hwdata;
    wire [3:0]  shared_hprot;
    wire        shared_hmastlock;
    wire        shared_req_active;
    wire        shared_hready;
    wire [31:0] shared_hrdata;
    wire [1:0]  shared_hresp;
    wire        ahb_grant_valid;
    wire [2:0]  ahb_grant_source;

    wire         shared_req_valid;
    wire [1:0]   shared_req_type;
    wire [31:0]  shared_req_addr;
    wire [255:0] shared_req_line;
    wire         shared_req_ready;
    reg          shared_resp_valid;
    reg          shared_resp_error;
    reg [255:0]  shared_resp_line;
    reg [1:0]    shared_resp_state;

    // ------------------------------------------------------
    // Post-bridge request/response wires (cache-controller side --
    // exactly the shape its cN_ireq_*/cN_iresp_*/cN_dreq_*/cN_dresp_*
    // ports already expect, unchanged).
    // ------------------------------------------------------
    wire         ireq_valid_w  [0:3];
    wire [31:0]  ireq_addr_w   [0:3];
    wire         iresp_valid_w [0:3];
    wire         iresp_error_w [0:3];
    wire [255:0] iresp_line_w  [0:3];

    wire         dreq_valid_w  [0:3];
    wire [1:0]   dreq_type_w   [0:3];
    wire [31:0]  dreq_addr_w   [0:3];
    wire [255:0] dreq_line_w   [0:3];
    wire         dresp_valid_w [0:3];
    wire         dresp_error_w [0:3];
    wire [255:0] dresp_line_w  [0:3];
    wire [1:0]   dresp_state_w [0:3];
    wire [3:0]   cache_flush_core_busy;
    wire [3:0]   cache_flush_core_done;
    wire [3:0]   cache_flush_core_error;
    wire         l1_flush_request;
    wire         l1_flush_busy;
    wire         l1_flush_done;
    wire         l1_flush_error;
    wire         l2_flush_request;
    wire         l2_flush_busy;
    wire         l2_flush_done;
    wire         l2_flush_error;

    cache_maintenance_tracker u_cache_maintenance_tracker (
        .clk(clk), .rst(rst), .request(l1_flush_request),
        .core_busy(cache_flush_core_busy),
        .core_done(cache_flush_core_done),
        .core_error(cache_flush_core_error),
        .busy(l1_flush_busy), .done(l1_flush_done),
        .error(l1_flush_error)
    );

    system_cache_maintenance u_system_cache_maintenance (
        .clk(clk), .rst(rst), .request(Cache_Flush),
        .l1_request(l1_flush_request), .l1_busy(l1_flush_busy),
        .l1_done(l1_flush_done), .l1_error(l1_flush_error),
        .l2_request(l2_flush_request), .l2_busy(l2_flush_busy),
        .l2_done(l2_flush_done), .l2_error(l2_flush_error),
        .busy(Cache_Flush_Busy), .done(Cache_Flush_Done),
        .error(Cache_Flush_Error)
    );

    // ------------------------------------------------------
    // Core 0
    // ------------------------------------------------------
    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR0), .HART_ID(32'd0)) core0 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(l1_flush_request),
        .Cache_Flush_Busy(cache_flush_core_busy[0]), .Cache_Flush_Done(cache_flush_core_done[0]), .Cache_Flush_Error(cache_flush_core_error[0]),
        .ResultW(ResultW0), .ALU_ResultE_Debug(alu_dbg_unused0),
        .Fetch_PageFault(Fetch_PageFault0), .Data_PageFault(Data_PageFault0),
        .Fetch_PageFault_Cause(fpc_unused0), .Data_PageFault_Cause(dpc_unused0),
        .ibus_req_valid(ibus_req_valid[0]), .ibus_req_ready(1'b0), .ibus_req_addr(ibus_req_addr[0]),
        .ibus_resp_valid(ibus_resp_valid[0]), .ibus_resp_error(ibus_resp_error[0]), .ibus_resp_line(ibus_resp_line[0]),
        .dbus_req_valid(dbus_req_valid[0]), .dbus_req_ready(1'b0), .dbus_req_type(dbus_req_type[0]),
        .dbus_req_addr(dbus_req_addr[0]), .dbus_req_line(dbus_req_line[0]),
        .dbus_resp_valid(dbus_resp_valid[0]), .dbus_resp_error(dbus_resp_error[0]), .dbus_resp_line(dbus_resp_line[0]), .dbus_resp_state(dbus_resp_state[0]),
        .dsnoop_valid(dsnoop_valid[0]), .dsnoop_type(dsnoop_type[0]), .dsnoop_addr(dsnoop_addr[0]),
        .dsnoop_ack_valid(dsnoop_ack_valid[0]), .dsnoop_ack_hit(dsnoop_ack_hit[0]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[0]), .dsnoop_ack_line(dsnoop_ack_line[0])
    );

    ahb_lite_l1_adapter u0_i_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn), .HGRANT(ahb_m_hgrant[4]),
        .bus_req_valid(ibus_req_valid[0]), .bus_req_type(2'b00),
        .bus_req_addr(ibus_req_addr[0]), .bus_req_line(256'b0),
        .bus_resp_valid(ibus_resp_valid[0]), .bus_resp_error(ibus_resp_error[0]), .bus_resp_line(ibus_resp_line[0]), .bus_resp_state(),
        .HADDR(i_haddr[0]), .HWRITE(i_hwrite[0]), .HSIZE(i_hsize[0]), .HTRANS(i_htrans[0]),
        .HWDATA(i_hwdata[0]), .HBURST(), .HPROT(i_hprot[0]), .HMASTLOCK(i_hmastlock[0]),
        .HRDATA(i_hrdata[0]), .HREADY(i_hready[0]), .HRESP(i_hresp[0]),
        .REQ_ACTIVE(i_req_active[0])
    );
    ahb_lite_l1_adapter u0_d_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn), .HGRANT(ahb_m_hgrant[0]),
        .bus_req_valid(dbus_req_valid[0]), .bus_req_type(dbus_req_type[0]),
        .bus_req_addr(dbus_req_addr[0]), .bus_req_line(dbus_req_line[0]),
        .bus_resp_valid(dbus_resp_valid[0]), .bus_resp_error(dbus_resp_error[0]), .bus_resp_line(dbus_resp_line[0]), .bus_resp_state(dbus_resp_state[0]),
        .HADDR(d_haddr[0]), .HWRITE(d_hwrite[0]), .HSIZE(d_hsize[0]), .HTRANS(d_htrans[0]),
        .HWDATA(d_hwdata[0]), .HBURST(), .HPROT(d_hprot[0]), .HMASTLOCK(d_hmastlock[0]),
        .HRDATA(d_hrdata[0]), .HREADY(d_hready[0]), .HRESP(d_hresp[0]),
        .REQ_ACTIVE(d_req_active[0])
    );

    // ------------------------------------------------------
    // Core 1
    // ------------------------------------------------------
    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR1), .HART_ID(32'd1)) core1 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(l1_flush_request),
        .Cache_Flush_Busy(cache_flush_core_busy[1]), .Cache_Flush_Done(cache_flush_core_done[1]), .Cache_Flush_Error(cache_flush_core_error[1]),
        .ResultW(ResultW1), .ALU_ResultE_Debug(alu_dbg_unused1),
        .Fetch_PageFault(Fetch_PageFault1), .Data_PageFault(Data_PageFault1),
        .Fetch_PageFault_Cause(fpc_unused1), .Data_PageFault_Cause(dpc_unused1),
        .ibus_req_valid(ibus_req_valid[1]), .ibus_req_ready(1'b0), .ibus_req_addr(ibus_req_addr[1]),
        .ibus_resp_valid(ibus_resp_valid[1]), .ibus_resp_error(ibus_resp_error[1]), .ibus_resp_line(ibus_resp_line[1]),
        .dbus_req_valid(dbus_req_valid[1]), .dbus_req_ready(1'b0), .dbus_req_type(dbus_req_type[1]),
        .dbus_req_addr(dbus_req_addr[1]), .dbus_req_line(dbus_req_line[1]),
        .dbus_resp_valid(dbus_resp_valid[1]), .dbus_resp_error(dbus_resp_error[1]), .dbus_resp_line(dbus_resp_line[1]), .dbus_resp_state(dbus_resp_state[1]),
        .dsnoop_valid(dsnoop_valid[1]), .dsnoop_type(dsnoop_type[1]), .dsnoop_addr(dsnoop_addr[1]),
        .dsnoop_ack_valid(dsnoop_ack_valid[1]), .dsnoop_ack_hit(dsnoop_ack_hit[1]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[1]), .dsnoop_ack_line(dsnoop_ack_line[1])
    );

    ahb_lite_l1_adapter u1_i_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn), .HGRANT(ahb_m_hgrant[5]),
        .bus_req_valid(ibus_req_valid[1]), .bus_req_type(2'b00),
        .bus_req_addr(ibus_req_addr[1]), .bus_req_line(256'b0),
        .bus_resp_valid(ibus_resp_valid[1]), .bus_resp_error(ibus_resp_error[1]), .bus_resp_line(ibus_resp_line[1]), .bus_resp_state(),
        .HADDR(i_haddr[1]), .HWRITE(i_hwrite[1]), .HSIZE(i_hsize[1]), .HTRANS(i_htrans[1]),
        .HWDATA(i_hwdata[1]), .HBURST(), .HPROT(i_hprot[1]), .HMASTLOCK(i_hmastlock[1]),
        .HRDATA(i_hrdata[1]), .HREADY(i_hready[1]), .HRESP(i_hresp[1]),
        .REQ_ACTIVE(i_req_active[1])
    );
    ahb_lite_l1_adapter u1_d_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn), .HGRANT(ahb_m_hgrant[1]),
        .bus_req_valid(dbus_req_valid[1]), .bus_req_type(dbus_req_type[1]),
        .bus_req_addr(dbus_req_addr[1]), .bus_req_line(dbus_req_line[1]),
        .bus_resp_valid(dbus_resp_valid[1]), .bus_resp_error(dbus_resp_error[1]), .bus_resp_line(dbus_resp_line[1]), .bus_resp_state(dbus_resp_state[1]),
        .HADDR(d_haddr[1]), .HWRITE(d_hwrite[1]), .HSIZE(d_hsize[1]), .HTRANS(d_htrans[1]),
        .HWDATA(d_hwdata[1]), .HBURST(), .HPROT(d_hprot[1]), .HMASTLOCK(d_hmastlock[1]),
        .HRDATA(d_hrdata[1]), .HREADY(d_hready[1]), .HRESP(d_hresp[1]),
        .REQ_ACTIVE(d_req_active[1])
    );

    // ------------------------------------------------------
    // Core 2
    // ------------------------------------------------------
    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR2), .HART_ID(32'd2)) core2 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(l1_flush_request),
        .Cache_Flush_Busy(cache_flush_core_busy[2]), .Cache_Flush_Done(cache_flush_core_done[2]), .Cache_Flush_Error(cache_flush_core_error[2]),
        .ResultW(ResultW2), .ALU_ResultE_Debug(alu_dbg_unused2),
        .Fetch_PageFault(Fetch_PageFault2), .Data_PageFault(Data_PageFault2),
        .Fetch_PageFault_Cause(fpc_unused2), .Data_PageFault_Cause(dpc_unused2),
        .ibus_req_valid(ibus_req_valid[2]), .ibus_req_ready(1'b0), .ibus_req_addr(ibus_req_addr[2]),
        .ibus_resp_valid(ibus_resp_valid[2]), .ibus_resp_error(ibus_resp_error[2]), .ibus_resp_line(ibus_resp_line[2]),
        .dbus_req_valid(dbus_req_valid[2]), .dbus_req_ready(1'b0), .dbus_req_type(dbus_req_type[2]),
        .dbus_req_addr(dbus_req_addr[2]), .dbus_req_line(dbus_req_line[2]),
        .dbus_resp_valid(dbus_resp_valid[2]), .dbus_resp_error(dbus_resp_error[2]), .dbus_resp_line(dbus_resp_line[2]), .dbus_resp_state(dbus_resp_state[2]),
        .dsnoop_valid(dsnoop_valid[2]), .dsnoop_type(dsnoop_type[2]), .dsnoop_addr(dsnoop_addr[2]),
        .dsnoop_ack_valid(dsnoop_ack_valid[2]), .dsnoop_ack_hit(dsnoop_ack_hit[2]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[2]), .dsnoop_ack_line(dsnoop_ack_line[2])
    );

    ahb_lite_l1_adapter u2_i_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn), .HGRANT(ahb_m_hgrant[6]),
        .bus_req_valid(ibus_req_valid[2]), .bus_req_type(2'b00),
        .bus_req_addr(ibus_req_addr[2]), .bus_req_line(256'b0),
        .bus_resp_valid(ibus_resp_valid[2]), .bus_resp_error(ibus_resp_error[2]), .bus_resp_line(ibus_resp_line[2]), .bus_resp_state(),
        .HADDR(i_haddr[2]), .HWRITE(i_hwrite[2]), .HSIZE(i_hsize[2]), .HTRANS(i_htrans[2]),
        .HWDATA(i_hwdata[2]), .HBURST(), .HPROT(i_hprot[2]), .HMASTLOCK(i_hmastlock[2]),
        .HRDATA(i_hrdata[2]), .HREADY(i_hready[2]), .HRESP(i_hresp[2]),
        .REQ_ACTIVE(i_req_active[2])
    );
    ahb_lite_l1_adapter u2_d_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn), .HGRANT(ahb_m_hgrant[2]),
        .bus_req_valid(dbus_req_valid[2]), .bus_req_type(dbus_req_type[2]),
        .bus_req_addr(dbus_req_addr[2]), .bus_req_line(dbus_req_line[2]),
        .bus_resp_valid(dbus_resp_valid[2]), .bus_resp_error(dbus_resp_error[2]), .bus_resp_line(dbus_resp_line[2]), .bus_resp_state(dbus_resp_state[2]),
        .HADDR(d_haddr[2]), .HWRITE(d_hwrite[2]), .HSIZE(d_hsize[2]), .HTRANS(d_htrans[2]),
        .HWDATA(d_hwdata[2]), .HBURST(), .HPROT(d_hprot[2]), .HMASTLOCK(d_hmastlock[2]),
        .HRDATA(d_hrdata[2]), .HREADY(d_hready[2]), .HRESP(d_hresp[2]),
        .REQ_ACTIVE(d_req_active[2])
    );

    // ------------------------------------------------------
    // Core 3
    // ------------------------------------------------------
    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR3), .HART_ID(32'd3)) core3 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(l1_flush_request),
        .Cache_Flush_Busy(cache_flush_core_busy[3]), .Cache_Flush_Done(cache_flush_core_done[3]), .Cache_Flush_Error(cache_flush_core_error[3]),
        .ResultW(ResultW3), .ALU_ResultE_Debug(alu_dbg_unused3),
        .Fetch_PageFault(Fetch_PageFault3), .Data_PageFault(Data_PageFault3),
        .Fetch_PageFault_Cause(fpc_unused3), .Data_PageFault_Cause(dpc_unused3),
        .ibus_req_valid(ibus_req_valid[3]), .ibus_req_ready(1'b0), .ibus_req_addr(ibus_req_addr[3]),
        .ibus_resp_valid(ibus_resp_valid[3]), .ibus_resp_error(ibus_resp_error[3]), .ibus_resp_line(ibus_resp_line[3]),
        .dbus_req_valid(dbus_req_valid[3]), .dbus_req_ready(1'b0), .dbus_req_type(dbus_req_type[3]),
        .dbus_req_addr(dbus_req_addr[3]), .dbus_req_line(dbus_req_line[3]),
        .dbus_resp_valid(dbus_resp_valid[3]), .dbus_resp_error(dbus_resp_error[3]), .dbus_resp_line(dbus_resp_line[3]), .dbus_resp_state(dbus_resp_state[3]),
        .dsnoop_valid(dsnoop_valid[3]), .dsnoop_type(dsnoop_type[3]), .dsnoop_addr(dsnoop_addr[3]),
        .dsnoop_ack_valid(dsnoop_ack_valid[3]), .dsnoop_ack_hit(dsnoop_ack_hit[3]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[3]), .dsnoop_ack_line(dsnoop_ack_line[3])
    );

    ahb_lite_l1_adapter u3_i_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn), .HGRANT(ahb_m_hgrant[7]),
        .bus_req_valid(ibus_req_valid[3]), .bus_req_type(2'b00),
        .bus_req_addr(ibus_req_addr[3]), .bus_req_line(256'b0),
        .bus_resp_valid(ibus_resp_valid[3]), .bus_resp_error(ibus_resp_error[3]), .bus_resp_line(ibus_resp_line[3]), .bus_resp_state(),
        .HADDR(i_haddr[3]), .HWRITE(i_hwrite[3]), .HSIZE(i_hsize[3]), .HTRANS(i_htrans[3]),
        .HWDATA(i_hwdata[3]), .HBURST(), .HPROT(i_hprot[3]), .HMASTLOCK(i_hmastlock[3]),
        .HRDATA(i_hrdata[3]), .HREADY(i_hready[3]), .HRESP(i_hresp[3]),
        .REQ_ACTIVE(i_req_active[3])
    );
    ahb_lite_l1_adapter u3_d_ahb_m (
        .HCLK(clk), .HRESETn(HRESETn), .HGRANT(ahb_m_hgrant[3]),
        .bus_req_valid(dbus_req_valid[3]), .bus_req_type(dbus_req_type[3]),
        .bus_req_addr(dbus_req_addr[3]), .bus_req_line(dbus_req_line[3]),
        .bus_resp_valid(dbus_resp_valid[3]), .bus_resp_error(dbus_resp_error[3]), .bus_resp_line(dbus_resp_line[3]), .bus_resp_state(dbus_resp_state[3]),
        .HADDR(d_haddr[3]), .HWRITE(d_hwrite[3]), .HSIZE(d_hsize[3]), .HTRANS(d_htrans[3]),
        .HWDATA(d_hwdata[3]), .HBURST(), .HPROT(d_hprot[3]), .HMASTLOCK(d_hmastlock[3]),
        .HRDATA(d_hrdata[3]), .HREADY(d_hready[3]), .HRESP(d_hresp[3]),
        .REQ_ACTIVE(d_req_active[3])
    );

    // ------------------------------------------------------
    // One physical AHB-Lite layer shared by all eight cache masters.
    // ------------------------------------------------------
    assign ahb_m_haddr       = {i_haddr[3], i_haddr[2], i_haddr[1], i_haddr[0],
                                d_haddr[3], d_haddr[2], d_haddr[1], d_haddr[0]};
    assign ahb_m_hwrite      = {i_hwrite[3], i_hwrite[2], i_hwrite[1], i_hwrite[0],
                                d_hwrite[3], d_hwrite[2], d_hwrite[1], d_hwrite[0]};
    assign ahb_m_hsize       = {i_hsize[3], i_hsize[2], i_hsize[1], i_hsize[0],
                                d_hsize[3], d_hsize[2], d_hsize[1], d_hsize[0]};
    assign ahb_m_htrans      = {i_htrans[3], i_htrans[2], i_htrans[1], i_htrans[0],
                                d_htrans[3], d_htrans[2], d_htrans[1], d_htrans[0]};
    assign ahb_m_hwdata      = {i_hwdata[3], i_hwdata[2], i_hwdata[1], i_hwdata[0],
                                d_hwdata[3], d_hwdata[2], d_hwdata[1], d_hwdata[0]};
    assign ahb_m_hprot       = {i_hprot[3], i_hprot[2], i_hprot[1], i_hprot[0],
                                d_hprot[3], d_hprot[2], d_hprot[1], d_hprot[0]};
    assign ahb_m_hmastlock   = {i_hmastlock[3], i_hmastlock[2], i_hmastlock[1], i_hmastlock[0],
                                d_hmastlock[3], d_hmastlock[2], d_hmastlock[1], d_hmastlock[0]};
    assign ahb_m_req_active  = {i_req_active[3], i_req_active[2], i_req_active[1], i_req_active[0],
                                d_req_active[3], d_req_active[2], d_req_active[1], d_req_active[0]};

    assign d_hready[0] = ahb_m_hready[0]; assign d_hready[1] = ahb_m_hready[1];
    assign d_hready[2] = ahb_m_hready[2]; assign d_hready[3] = ahb_m_hready[3];
    assign i_hready[0] = ahb_m_hready[4]; assign i_hready[1] = ahb_m_hready[5];
    assign i_hready[2] = ahb_m_hready[6]; assign i_hready[3] = ahb_m_hready[7];
    assign d_hrdata[0] = ahb_m_hrdata[0*32 +: 32]; assign d_hrdata[1] = ahb_m_hrdata[1*32 +: 32];
    assign d_hrdata[2] = ahb_m_hrdata[2*32 +: 32]; assign d_hrdata[3] = ahb_m_hrdata[3*32 +: 32];
    assign i_hrdata[0] = ahb_m_hrdata[4*32 +: 32]; assign i_hrdata[1] = ahb_m_hrdata[5*32 +: 32];
    assign i_hrdata[2] = ahb_m_hrdata[6*32 +: 32]; assign i_hrdata[3] = ahb_m_hrdata[7*32 +: 32];
    assign d_hresp[0] = ahb_m_hresp[0*2 +: 2]; assign d_hresp[1] = ahb_m_hresp[1*2 +: 2];
    assign d_hresp[2] = ahb_m_hresp[2*2 +: 2]; assign d_hresp[3] = ahb_m_hresp[3*2 +: 2];
    assign i_hresp[0] = ahb_m_hresp[4*2 +: 2]; assign i_hresp[1] = ahb_m_hresp[5*2 +: 2];
    assign i_hresp[2] = ahb_m_hresp[6*2 +: 2]; assign i_hresp[3] = ahb_m_hresp[7*2 +: 2];

    ahb_lite_arbiter_8m1s u_ahb_arbiter (
        .HCLK(clk), .HRESETn(HRESETn),
        .M_REQ_ACTIVE(ahb_m_req_active), .M_HADDR(ahb_m_haddr),
        .M_HWRITE(ahb_m_hwrite), .M_HSIZE(ahb_m_hsize),
        .M_HTRANS(ahb_m_htrans), .M_HWDATA(ahb_m_hwdata),
        .M_HPROT(ahb_m_hprot), .M_HMASTLOCK(ahb_m_hmastlock),
        .M_HGRANT(ahb_m_hgrant), .M_HREADY(ahb_m_hready),
        .M_HRDATA(ahb_m_hrdata), .M_HRESP(ahb_m_hresp),
        .S_HADDR(shared_haddr), .S_HWRITE(shared_hwrite),
        .S_HSIZE(shared_hsize), .S_HTRANS(shared_htrans),
        .S_HWDATA(shared_hwdata), .S_HPROT(shared_hprot),
        .S_HMASTLOCK(shared_hmastlock), .S_REQ_ACTIVE(shared_req_active),
        .S_HREADY(shared_hready), .S_HRDATA(shared_hrdata), .S_HRESP(shared_hresp),
        .GRANT_VALID(ahb_grant_valid), .GRANT_SOURCE(ahb_grant_source)
    );

    ahb_lite_l1_slave_adapter u_shared_ahb_s (
        .HCLK(clk), .HRESETn(HRESETn),
        .HADDR(shared_haddr), .HWRITE(shared_hwrite), .HTRANS(shared_htrans),
        .HWDATA(shared_hwdata), .HMASTLOCK(shared_hmastlock),
        .HSIZE(shared_hsize), .HPROT(shared_hprot), .REQ_ACTIVE(shared_req_active),
        .HREADYOUT(shared_hready), .HRDATA(shared_hrdata), .HRESP(shared_hresp),
        .dreq_valid(shared_req_valid), .dreq_type(shared_req_type),
        .dreq_addr(shared_req_addr), .dreq_line(shared_req_line),
        .dresp_valid(shared_resp_valid), .dresp_error(shared_resp_error),
        .dresp_line(shared_resp_line), .dresp_state(shared_resp_state)
    );

    always @(*) begin
        shared_resp_valid = 1'b0;
        shared_resp_error = 1'b0;
        shared_resp_line  = 256'b0;
        shared_resp_state = 2'b00;
        case (ahb_grant_source)
            3'd0: begin shared_resp_valid=dresp_valid_w[0]; shared_resp_error=dresp_error_w[0]; shared_resp_line=dresp_line_w[0]; shared_resp_state=dresp_state_w[0]; end
            3'd1: begin shared_resp_valid=dresp_valid_w[1]; shared_resp_error=dresp_error_w[1]; shared_resp_line=dresp_line_w[1]; shared_resp_state=dresp_state_w[1]; end
            3'd2: begin shared_resp_valid=dresp_valid_w[2]; shared_resp_error=dresp_error_w[2]; shared_resp_line=dresp_line_w[2]; shared_resp_state=dresp_state_w[2]; end
            3'd3: begin shared_resp_valid=dresp_valid_w[3]; shared_resp_error=dresp_error_w[3]; shared_resp_line=dresp_line_w[3]; shared_resp_state=dresp_state_w[3]; end
            3'd4: begin shared_resp_valid=iresp_valid_w[0]; shared_resp_error=iresp_error_w[0]; shared_resp_line=iresp_line_w[0]; shared_resp_state=2'b01; end
            3'd5: begin shared_resp_valid=iresp_valid_w[1]; shared_resp_error=iresp_error_w[1]; shared_resp_line=iresp_line_w[1]; shared_resp_state=2'b01; end
            3'd6: begin shared_resp_valid=iresp_valid_w[2]; shared_resp_error=iresp_error_w[2]; shared_resp_line=iresp_line_w[2]; shared_resp_state=2'b01; end
            3'd7: begin shared_resp_valid=iresp_valid_w[3]; shared_resp_error=iresp_error_w[3]; shared_resp_line=iresp_line_w[3]; shared_resp_state=2'b01; end
        endcase
    end

    // ------------------------------------------------------
    // Shared L2 + MSI directory + arbiter. Same instantiation as
    // quad_core_soc.v, except the dreq/dresp/ireq/iresp connections
    // now come from the far side of the AHB-Lite bridge above instead
    // of directly from core_l1_wrapper -- dsnoop_* still connects
    // directly to each core (see header: not bridged).
    // ------------------------------------------------------
    cache_controller_mmu #(
        .DEBUG_TRACE_ENABLE(CACHE_DEBUG_TRACE_ENABLE),
        .REQUEST_QUEUE_ENABLE(0),
        .EXTERNAL_REQUEST_ARBITER(1)
    ) u_cache_controller_mmu (
        .clk(clk), .rst(rst),

        .c0_dreq_valid(1'b0), .c0_dreq_type(2'b0), .c0_dreq_addr(32'b0), .c0_dreq_line(256'b0),
        .c0_dresp_valid(dresp_valid_w[0]), .c0_dresp_error(dresp_error_w[0]), .c0_dresp_line(dresp_line_w[0]), .c0_dresp_state(dresp_state_w[0]),
        .c0_dsnoop_valid(dsnoop_valid[0]), .c0_dsnoop_type(dsnoop_type[0]), .c0_dsnoop_addr(dsnoop_addr[0]),
        .c0_dsnoop_ack_valid(dsnoop_ack_valid[0]), .c0_dsnoop_ack_hit(dsnoop_ack_hit[0]),
        .c0_dsnoop_ack_dirty(dsnoop_ack_dirty[0]), .c0_dsnoop_ack_line(dsnoop_ack_line[0]),
        .c0_ireq_valid(1'b0), .c0_ireq_addr(32'b0),
        .c0_iresp_valid(iresp_valid_w[0]), .c0_iresp_error(iresp_error_w[0]), .c0_iresp_line(iresp_line_w[0]),

        .c1_dreq_valid(1'b0), .c1_dreq_type(2'b0), .c1_dreq_addr(32'b0), .c1_dreq_line(256'b0),
        .c1_dresp_valid(dresp_valid_w[1]), .c1_dresp_error(dresp_error_w[1]), .c1_dresp_line(dresp_line_w[1]), .c1_dresp_state(dresp_state_w[1]),
        .c1_dsnoop_valid(dsnoop_valid[1]), .c1_dsnoop_type(dsnoop_type[1]), .c1_dsnoop_addr(dsnoop_addr[1]),
        .c1_dsnoop_ack_valid(dsnoop_ack_valid[1]), .c1_dsnoop_ack_hit(dsnoop_ack_hit[1]),
        .c1_dsnoop_ack_dirty(dsnoop_ack_dirty[1]), .c1_dsnoop_ack_line(dsnoop_ack_line[1]),
        .c1_ireq_valid(1'b0), .c1_ireq_addr(32'b0),
        .c1_iresp_valid(iresp_valid_w[1]), .c1_iresp_error(iresp_error_w[1]), .c1_iresp_line(iresp_line_w[1]),

        .c2_dreq_valid(1'b0), .c2_dreq_type(2'b0), .c2_dreq_addr(32'b0), .c2_dreq_line(256'b0),
        .c2_dresp_valid(dresp_valid_w[2]), .c2_dresp_error(dresp_error_w[2]), .c2_dresp_line(dresp_line_w[2]), .c2_dresp_state(dresp_state_w[2]),
        .c2_dsnoop_valid(dsnoop_valid[2]), .c2_dsnoop_type(dsnoop_type[2]), .c2_dsnoop_addr(dsnoop_addr[2]),
        .c2_dsnoop_ack_valid(dsnoop_ack_valid[2]), .c2_dsnoop_ack_hit(dsnoop_ack_hit[2]),
        .c2_dsnoop_ack_dirty(dsnoop_ack_dirty[2]), .c2_dsnoop_ack_line(dsnoop_ack_line[2]),
        .c2_ireq_valid(1'b0), .c2_ireq_addr(32'b0),
        .c2_iresp_valid(iresp_valid_w[2]), .c2_iresp_error(iresp_error_w[2]), .c2_iresp_line(iresp_line_w[2]),

        .c3_dreq_valid(1'b0), .c3_dreq_type(2'b0), .c3_dreq_addr(32'b0), .c3_dreq_line(256'b0),
        .c3_dresp_valid(dresp_valid_w[3]), .c3_dresp_error(dresp_error_w[3]), .c3_dresp_line(dresp_line_w[3]), .c3_dresp_state(dresp_state_w[3]),
        .c3_dsnoop_valid(dsnoop_valid[3]), .c3_dsnoop_type(dsnoop_type[3]), .c3_dsnoop_addr(dsnoop_addr[3]),
        .c3_dsnoop_ack_valid(dsnoop_ack_valid[3]), .c3_dsnoop_ack_hit(dsnoop_ack_hit[3]),
        .c3_dsnoop_ack_dirty(dsnoop_ack_dirty[3]), .c3_dsnoop_ack_line(dsnoop_ack_line[3]),
        .c3_ireq_valid(1'b0), .c3_ireq_addr(32'b0),
        .c3_iresp_valid(iresp_valid_w[3]), .c3_iresp_error(iresp_error_w[3]), .c3_iresp_line(iresp_line_w[3]),

        .ext_req_valid(shared_req_valid), .ext_req_ready(shared_req_ready),
        .ext_req_source(ahb_grant_source), .ext_req_type(shared_req_type),
        .ext_req_addr(shared_req_addr), .ext_req_line(shared_req_line),

        .mem_req_valid(mem_req_valid), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata), .mem_valid(mem_valid), .mem_error(mem_error),
        .perf_total_requests(cache_perf_total_requests), .perf_d_bus_reads(cache_perf_d_bus_reads),
        .perf_d_rfos(cache_perf_d_rfos), .perf_d_writebacks(cache_perf_d_writebacks),
        .perf_i_reads(cache_perf_i_reads), .perf_l2_hits(cache_perf_l2_hits),
        .perf_l2_misses(cache_perf_l2_misses), .perf_snoop_requests(cache_perf_snoop_requests),
        .perf_mem_read_words(cache_perf_mem_read_words), .perf_mem_write_words(cache_perf_mem_write_words),
        .perf_busy_cycles(cache_perf_busy_cycles), .protocol_error(cache_protocol_error),
        .timeout_error(cache_timeout_error), .memory_error(cache_memory_error),
        .debug_trace_rd_index(4'b0), .debug_trace_rd_data(cache_debug_trace_entry0),
        .debug_trace_count(cache_debug_trace_count),
        .debug_trace_write_index(cache_debug_trace_write_index),
        .debug_controller_state(cache_debug_controller_state),
        .cache_flush_req(l2_flush_request), .cache_flush_busy(l2_flush_busy),
        .cache_flush_done(l2_flush_done), .cache_flush_error(l2_flush_error),
        .l2_cmd_valid_o(l2_cmd_valid), .l2_cmd_we_o(l2_cmd_we),
        .l2_cmd_addr_o(l2_cmd_addr), .l2_cmd_way_o(l2_cmd_way),
        .l2_cmd_wdata_o(l2_cmd_wdata), .l2_cmd_w_valid_o(l2_cmd_w_valid),
        .l2_cmd_w_dirty_o(l2_cmd_w_dirty), .l2_cmd_w_sharers_o(l2_cmd_w_sharers),
        .l2_resp_valid_i(l2_resp_valid), .l2_resp_hit_i(l2_resp_hit),
        .l2_resp_way_i(l2_resp_way), .l2_resp_victim_tag_i(l2_resp_victim_tag),
        .l2_resp_victim_valid_i(l2_resp_victim_valid),
        .l2_resp_victim_dirty_i(l2_resp_victim_dirty),
        .l2_resp_victim_sharers_i(l2_resp_victim_sharers),
        .l2_resp_line_i(l2_resp_line), .l2_resp_sharers_i(l2_resp_sharers),
        .l2_maint_valid_o(l2_maint_valid), .l2_maint_set_o(l2_maint_set),
        .l2_maint_way_o(l2_maint_way), .l2_maint_invalidate_o(l2_maint_invalidate),
        .l2_maint_ready_i(l2_maint_ready), .l2_maint_resp_valid_i(l2_maint_resp_valid),
        .l2_maint_line_valid_i(l2_maint_line_valid),
        .l2_maint_line_dirty_i(l2_maint_line_dirty), .l2_maint_line_tag_i(l2_maint_line_tag),
        .l2_maint_line_data_i(l2_maint_line_data)
    );

    l2_cache u_shared_l2 (
        .clk(clk), .rst(rst),
        .cmd_valid(l2_cmd_valid), .cmd_we(l2_cmd_we),
        .cmd_addr(l2_cmd_addr), .cmd_way(l2_cmd_way),
        .cmd_wdata(l2_cmd_wdata), .cmd_w_valid(l2_cmd_w_valid),
        .cmd_w_dirty(l2_cmd_w_dirty), .cmd_w_sharers(l2_cmd_w_sharers),
        .maint_valid(l2_maint_valid), .maint_set(l2_maint_set),
        .maint_way(l2_maint_way), .maint_invalidate(l2_maint_invalidate),
        .maint_ready(l2_maint_ready), .maint_resp_valid(l2_maint_resp_valid),
        .maint_line_valid(l2_maint_line_valid),
        .maint_line_dirty(l2_maint_line_dirty), .maint_line_tag(l2_maint_line_tag),
        .maint_line_data(l2_maint_line_data),
        .resp_valid(l2_resp_valid), .resp_hit(l2_resp_hit),
        .resp_way(l2_resp_way), .resp_victim_tag(l2_resp_victim_tag),
        .resp_victim_valid(l2_resp_victim_valid),
        .resp_victim_dirty(l2_resp_victim_dirty),
        .resp_victim_sharers(l2_resp_victim_sharers),
        .resp_line(l2_resp_line), .resp_sharers(l2_resp_sharers)
    );

endmodule
