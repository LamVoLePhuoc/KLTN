`timescale 1ns / 1ps

// ============================================================
// quad_core_soc
//
// The full "4-CORE CPU WRAPPER" box from the architecture diagram:
// 4x core_l1_wrapper (RV32IMA + per-core Sv32 translation + private
// L1 I$/D$) feeding one shared cache_controller_mmu.  The controller
// and l2_cache are peer instances: policy/control stays in the former,
// data/tag/directory storage stays in the latter.  This is the new
// "MMU as cache controller" boundary requested for the architecture,
// with a single flat physical
// memory port out (the diagram's "CPU MEMORY PORT") for whatever
// sits on the AXI4 system bus side. See quad_core_axi_wrapper.v for
// the real AXI4 handshake around that port.
//
// Each core's satp CSR (software-written, see csr_trap_unit.v) is now
// the one real source of truth for MMU enable + page-table root --
// core_l1_wrapper.v instantiates its MMU with MMU_CTRL_FROM_CSR=1, so
// there is no external Mmu_Enable/Satp_PPN0..3 pin here any more (an
// earlier version of this file had them, before the satp-CSR-to-MMU
// feedback loop was wired up -- see Risc_V_new/README.md). Mmu_Flush
// remains external
// (OR'd with each core's own sfence.vma-triggered flush): harmless to
// share one flush pulse across all 4 cores since an extra TLB
// invalidate only costs a refill, never a correctness bug. Boot
// addresses are parameterized per core (RESET_ADDR0..3) so each can
// be pointed at a distinct program region, unlike
// RV32IMA_DualCore_Wrapper.v's two cores (which share one hardcoded
// default -- see Risc_V_new/README.md's "Sổ rủi ro" #3).
// ============================================================
module quad_core_soc #(
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

    // ------------------------------------------------------
    // Per-core bus wiring (I$ req/resp, D$ req/resp, D$ snoop)
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
    wire [3:0]  cache_flush_core_busy;
    wire [3:0]  cache_flush_core_done;
    wire [3:0]  cache_flush_core_error;

    cache_maintenance_tracker u_cache_maintenance_tracker (
        .clk(clk), .rst(rst), .request(Cache_Flush),
        .core_busy(cache_flush_core_busy),
        .core_done(cache_flush_core_done),
        .core_error(cache_flush_core_error),
        .busy(Cache_Flush_Busy), .done(Cache_Flush_Done),
        .error(Cache_Flush_Error)
    );

    // Kept internal to preserve the stable board-facing port list,
    // but marked for direct ILA probing during cache bring-up.
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

    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR0)) core0 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(Cache_Flush),
        .Cache_Flush_Busy(cache_flush_core_busy[0]), .Cache_Flush_Done(cache_flush_core_done[0]), .Cache_Flush_Error(cache_flush_core_error[0]),
        .ResultW(ResultW0), .ALU_ResultE_Debug(alu_dbg_unused0),
        .Fetch_PageFault(Fetch_PageFault0), .Data_PageFault(Data_PageFault0),
        .Fetch_PageFault_Cause(fpc_unused0), .Data_PageFault_Cause(dpc_unused0),
        .ibus_req_valid(ibus_req_valid[0]), .ibus_req_addr(ibus_req_addr[0]),
        .ibus_resp_valid(ibus_resp_valid[0]), .ibus_resp_error(ibus_resp_error[0]), .ibus_resp_line(ibus_resp_line[0]),
        .dbus_req_valid(dbus_req_valid[0]), .dbus_req_type(dbus_req_type[0]),
        .dbus_req_addr(dbus_req_addr[0]), .dbus_req_line(dbus_req_line[0]),
        .dbus_resp_valid(dbus_resp_valid[0]), .dbus_resp_error(dbus_resp_error[0]), .dbus_resp_line(dbus_resp_line[0]), .dbus_resp_state(dbus_resp_state[0]),
        .dsnoop_valid(dsnoop_valid[0]), .dsnoop_type(dsnoop_type[0]), .dsnoop_addr(dsnoop_addr[0]),
        .dsnoop_ack_valid(dsnoop_ack_valid[0]), .dsnoop_ack_hit(dsnoop_ack_hit[0]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[0]), .dsnoop_ack_line(dsnoop_ack_line[0])
    );

    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR1)) core1 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(Cache_Flush),
        .Cache_Flush_Busy(cache_flush_core_busy[1]), .Cache_Flush_Done(cache_flush_core_done[1]), .Cache_Flush_Error(cache_flush_core_error[1]),
        .ResultW(ResultW1), .ALU_ResultE_Debug(alu_dbg_unused1),
        .Fetch_PageFault(Fetch_PageFault1), .Data_PageFault(Data_PageFault1),
        .Fetch_PageFault_Cause(fpc_unused1), .Data_PageFault_Cause(dpc_unused1),
        .ibus_req_valid(ibus_req_valid[1]), .ibus_req_addr(ibus_req_addr[1]),
        .ibus_resp_valid(ibus_resp_valid[1]), .ibus_resp_error(ibus_resp_error[1]), .ibus_resp_line(ibus_resp_line[1]),
        .dbus_req_valid(dbus_req_valid[1]), .dbus_req_type(dbus_req_type[1]),
        .dbus_req_addr(dbus_req_addr[1]), .dbus_req_line(dbus_req_line[1]),
        .dbus_resp_valid(dbus_resp_valid[1]), .dbus_resp_error(dbus_resp_error[1]), .dbus_resp_line(dbus_resp_line[1]), .dbus_resp_state(dbus_resp_state[1]),
        .dsnoop_valid(dsnoop_valid[1]), .dsnoop_type(dsnoop_type[1]), .dsnoop_addr(dsnoop_addr[1]),
        .dsnoop_ack_valid(dsnoop_ack_valid[1]), .dsnoop_ack_hit(dsnoop_ack_hit[1]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[1]), .dsnoop_ack_line(dsnoop_ack_line[1])
    );

    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR2)) core2 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(Cache_Flush),
        .Cache_Flush_Busy(cache_flush_core_busy[2]), .Cache_Flush_Done(cache_flush_core_done[2]), .Cache_Flush_Error(cache_flush_core_error[2]),
        .ResultW(ResultW2), .ALU_ResultE_Debug(alu_dbg_unused2),
        .Fetch_PageFault(Fetch_PageFault2), .Data_PageFault(Data_PageFault2),
        .Fetch_PageFault_Cause(fpc_unused2), .Data_PageFault_Cause(dpc_unused2),
        .ibus_req_valid(ibus_req_valid[2]), .ibus_req_addr(ibus_req_addr[2]),
        .ibus_resp_valid(ibus_resp_valid[2]), .ibus_resp_error(ibus_resp_error[2]), .ibus_resp_line(ibus_resp_line[2]),
        .dbus_req_valid(dbus_req_valid[2]), .dbus_req_type(dbus_req_type[2]),
        .dbus_req_addr(dbus_req_addr[2]), .dbus_req_line(dbus_req_line[2]),
        .dbus_resp_valid(dbus_resp_valid[2]), .dbus_resp_error(dbus_resp_error[2]), .dbus_resp_line(dbus_resp_line[2]), .dbus_resp_state(dbus_resp_state[2]),
        .dsnoop_valid(dsnoop_valid[2]), .dsnoop_type(dsnoop_type[2]), .dsnoop_addr(dsnoop_addr[2]),
        .dsnoop_ack_valid(dsnoop_ack_valid[2]), .dsnoop_ack_hit(dsnoop_ack_hit[2]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[2]), .dsnoop_ack_line(dsnoop_ack_line[2])
    );

    core_l1_wrapper #(.RESET_ADDR(RESET_ADDR3)) core3 (
        .clk(clk), .rst(rst),
        .Mmu_Flush(Mmu_Flush), .Cache_Flush(Cache_Flush),
        .Cache_Flush_Busy(cache_flush_core_busy[3]), .Cache_Flush_Done(cache_flush_core_done[3]), .Cache_Flush_Error(cache_flush_core_error[3]),
        .ResultW(ResultW3), .ALU_ResultE_Debug(alu_dbg_unused3),
        .Fetch_PageFault(Fetch_PageFault3), .Data_PageFault(Data_PageFault3),
        .Fetch_PageFault_Cause(fpc_unused3), .Data_PageFault_Cause(dpc_unused3),
        .ibus_req_valid(ibus_req_valid[3]), .ibus_req_addr(ibus_req_addr[3]),
        .ibus_resp_valid(ibus_resp_valid[3]), .ibus_resp_error(ibus_resp_error[3]), .ibus_resp_line(ibus_resp_line[3]),
        .dbus_req_valid(dbus_req_valid[3]), .dbus_req_type(dbus_req_type[3]),
        .dbus_req_addr(dbus_req_addr[3]), .dbus_req_line(dbus_req_line[3]),
        .dbus_resp_valid(dbus_resp_valid[3]), .dbus_resp_error(dbus_resp_error[3]), .dbus_resp_line(dbus_resp_line[3]), .dbus_resp_state(dbus_resp_state[3]),
        .dsnoop_valid(dsnoop_valid[3]), .dsnoop_type(dsnoop_type[3]), .dsnoop_addr(dsnoop_addr[3]),
        .dsnoop_ack_valid(dsnoop_ack_valid[3]), .dsnoop_ack_hit(dsnoop_ack_hit[3]),
        .dsnoop_ack_dirty(dsnoop_ack_dirty[3]), .dsnoop_ack_line(dsnoop_ack_line[3])
    );

    cache_controller_mmu #(
        .DEBUG_TRACE_ENABLE(CACHE_DEBUG_TRACE_ENABLE)
    ) u_cache_controller_mmu (
        .clk(clk), .rst(rst),

        .c0_dreq_valid(dbus_req_valid[0]), .c0_dreq_type(dbus_req_type[0]), .c0_dreq_addr(dbus_req_addr[0]), .c0_dreq_line(dbus_req_line[0]),
        .c0_dresp_valid(dbus_resp_valid[0]), .c0_dresp_error(dbus_resp_error[0]), .c0_dresp_line(dbus_resp_line[0]), .c0_dresp_state(dbus_resp_state[0]),
        .c0_dsnoop_valid(dsnoop_valid[0]), .c0_dsnoop_type(dsnoop_type[0]), .c0_dsnoop_addr(dsnoop_addr[0]),
        .c0_dsnoop_ack_valid(dsnoop_ack_valid[0]), .c0_dsnoop_ack_hit(dsnoop_ack_hit[0]),
        .c0_dsnoop_ack_dirty(dsnoop_ack_dirty[0]), .c0_dsnoop_ack_line(dsnoop_ack_line[0]),
        .c0_ireq_valid(ibus_req_valid[0]), .c0_ireq_addr(ibus_req_addr[0]),
        .c0_iresp_valid(ibus_resp_valid[0]), .c0_iresp_error(ibus_resp_error[0]), .c0_iresp_line(ibus_resp_line[0]),

        .c1_dreq_valid(dbus_req_valid[1]), .c1_dreq_type(dbus_req_type[1]), .c1_dreq_addr(dbus_req_addr[1]), .c1_dreq_line(dbus_req_line[1]),
        .c1_dresp_valid(dbus_resp_valid[1]), .c1_dresp_error(dbus_resp_error[1]), .c1_dresp_line(dbus_resp_line[1]), .c1_dresp_state(dbus_resp_state[1]),
        .c1_dsnoop_valid(dsnoop_valid[1]), .c1_dsnoop_type(dsnoop_type[1]), .c1_dsnoop_addr(dsnoop_addr[1]),
        .c1_dsnoop_ack_valid(dsnoop_ack_valid[1]), .c1_dsnoop_ack_hit(dsnoop_ack_hit[1]),
        .c1_dsnoop_ack_dirty(dsnoop_ack_dirty[1]), .c1_dsnoop_ack_line(dsnoop_ack_line[1]),
        .c1_ireq_valid(ibus_req_valid[1]), .c1_ireq_addr(ibus_req_addr[1]),
        .c1_iresp_valid(ibus_resp_valid[1]), .c1_iresp_error(ibus_resp_error[1]), .c1_iresp_line(ibus_resp_line[1]),

        .c2_dreq_valid(dbus_req_valid[2]), .c2_dreq_type(dbus_req_type[2]), .c2_dreq_addr(dbus_req_addr[2]), .c2_dreq_line(dbus_req_line[2]),
        .c2_dresp_valid(dbus_resp_valid[2]), .c2_dresp_error(dbus_resp_error[2]), .c2_dresp_line(dbus_resp_line[2]), .c2_dresp_state(dbus_resp_state[2]),
        .c2_dsnoop_valid(dsnoop_valid[2]), .c2_dsnoop_type(dsnoop_type[2]), .c2_dsnoop_addr(dsnoop_addr[2]),
        .c2_dsnoop_ack_valid(dsnoop_ack_valid[2]), .c2_dsnoop_ack_hit(dsnoop_ack_hit[2]),
        .c2_dsnoop_ack_dirty(dsnoop_ack_dirty[2]), .c2_dsnoop_ack_line(dsnoop_ack_line[2]),
        .c2_ireq_valid(ibus_req_valid[2]), .c2_ireq_addr(ibus_req_addr[2]),
        .c2_iresp_valid(ibus_resp_valid[2]), .c2_iresp_error(ibus_resp_error[2]), .c2_iresp_line(ibus_resp_line[2]),

        .c3_dreq_valid(dbus_req_valid[3]), .c3_dreq_type(dbus_req_type[3]), .c3_dreq_addr(dbus_req_addr[3]), .c3_dreq_line(dbus_req_line[3]),
        .c3_dresp_valid(dbus_resp_valid[3]), .c3_dresp_error(dbus_resp_error[3]), .c3_dresp_line(dbus_resp_line[3]), .c3_dresp_state(dbus_resp_state[3]),
        .c3_dsnoop_valid(dsnoop_valid[3]), .c3_dsnoop_type(dsnoop_type[3]), .c3_dsnoop_addr(dsnoop_addr[3]),
        .c3_dsnoop_ack_valid(dsnoop_ack_valid[3]), .c3_dsnoop_ack_hit(dsnoop_ack_hit[3]),
        .c3_dsnoop_ack_dirty(dsnoop_ack_dirty[3]), .c3_dsnoop_ack_line(dsnoop_ack_line[3]),
        .c3_ireq_valid(ibus_req_valid[3]), .c3_ireq_addr(ibus_req_addr[3]),
        .c3_iresp_valid(ibus_resp_valid[3]), .c3_iresp_error(ibus_resp_error[3]), .c3_iresp_line(ibus_resp_line[3]),

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
        .l2_cmd_valid_o(l2_cmd_valid), .l2_cmd_we_o(l2_cmd_we),
        .l2_cmd_addr_o(l2_cmd_addr), .l2_cmd_way_o(l2_cmd_way),
        .l2_cmd_wdata_o(l2_cmd_wdata), .l2_cmd_w_valid_o(l2_cmd_w_valid),
        .l2_cmd_w_dirty_o(l2_cmd_w_dirty), .l2_cmd_w_sharers_o(l2_cmd_w_sharers),
        .l2_resp_valid_i(l2_resp_valid), .l2_resp_hit_i(l2_resp_hit),
        .l2_resp_way_i(l2_resp_way), .l2_resp_victim_tag_i(l2_resp_victim_tag),
        .l2_resp_victim_valid_i(l2_resp_victim_valid),
        .l2_resp_victim_dirty_i(l2_resp_victim_dirty),
        .l2_resp_victim_sharers_i(l2_resp_victim_sharers),
        .l2_resp_line_i(l2_resp_line), .l2_resp_sharers_i(l2_resp_sharers)
    );

    l2_cache u_shared_l2 (
        .clk(clk), .rst(rst),
        .cmd_valid(l2_cmd_valid), .cmd_we(l2_cmd_we),
        .cmd_addr(l2_cmd_addr), .cmd_way(l2_cmd_way),
        .cmd_wdata(l2_cmd_wdata), .cmd_w_valid(l2_cmd_w_valid),
        .cmd_w_dirty(l2_cmd_w_dirty), .cmd_w_sharers(l2_cmd_w_sharers),
        .resp_valid(l2_resp_valid), .resp_hit(l2_resp_hit),
        .resp_way(l2_resp_way), .resp_victim_tag(l2_resp_victim_tag),
        .resp_victim_valid(l2_resp_victim_valid),
        .resp_victim_dirty(l2_resp_victim_dirty),
        .resp_victim_sharers(l2_resp_victim_sharers),
        .resp_line(l2_resp_line), .resp_sharers(l2_resp_sharers)
    );

endmodule
