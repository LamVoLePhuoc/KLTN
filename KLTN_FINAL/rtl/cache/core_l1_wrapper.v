`timescale 1ns / 1ps

`ifdef PPA_NO_MARK_DEBUG
`define KLTN_DEBUG_ATTR
`else
`define KLTN_DEBUG_ATTR (* mark_debug = "true" *)
`endif

// ============================================================
// core_l1_wrapper
//
// One "CORE N" box from the 4-CORE CPU WRAPPER diagram: RV32IMA plus
// private L1 I-Cache/D-Cache.  The active thesis scope uses one direct
// 32-bit physical address space; no TLB/PTW/address-translation MMU is
// instantiated in this hierarchy.  Shared cache management is handled
// below the four cores by cache_controller_mmu.
//
// physical_core_wrapper supplies the pipeline back-pressure needed by
// a real, multi-cycle cache. l1_icache/l1_dcache completion outputs
// directly become the instruction/data completion inputs of that
// wrapper. Error sidebands are preserved: a failed I$ fill becomes an
// instruction access fault and a failed D$ fill/RFO becomes the
// original load/store access fault. Failed lines are never installed.
//
// LR/SC note: l1_dcache's own INVALIDATE-type snoops (i.e. this
// core's D$ copy of some line was just invalidated because another
// core is writing it) are wired into the core's Snoop_Addr/Snoop_WE
// ports, which is what memory_stage.v's LR/SC reservation check
// already consumes. It fires only when coherence actually invalidates
// this core's line. Because the active design has one physical address
// domain, the reservation and snoop comparison use the same address.
//
// The legacy Mmu_Flush input and MMU parameters remain only to avoid a
// disruptive top-level pin change while existing Vivado block designs
// are regenerated. They have no functional effect in this hierarchy.
// ============================================================
module core_l1_wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_1000,
    parameter [31:0] HART_ID    = 32'd0,
    parameter        MESI_ENABLE = 0,
    // Deprecated compatibility parameters. They intentionally have no
    // effect now that address translation is outside the thesis scope.
    parameter        MMU_REGION_POLICY_ENABLE = 0,
    parameter        MMU_DEBUG_TRACE_ENABLE   = 0,
    parameter integer MMU_PTW_WATCHDOG_CYCLES = 0
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        Mmu_Flush,     // deprecated/no-op; kept for top-level pin compatibility
    input  wire        Cache_Flush,   // pulse: clean/invalidate D$, then invalidate I$

    // Cache-maintenance handshake.  Busy covers both an external
    // Cache_Flush and an architectural FENCE.I.  Done is a one-cycle
    // pulse after the I$ invalidate edge (or after a failed D$ clean),
    // and Error is sticky until reset.  System/DMA logic must wait for
    // Done and then inspect Error before touching coherent memory.
    output wire        Cache_Flush_Busy,
    output reg         Cache_Flush_Done,
    output wire        Cache_Flush_Error,

    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug,
    output wire        Fetch_PageFault,
    output wire        Data_PageFault,
    output wire [1:0]  Fetch_PageFault_Cause,
    output wire [1:0]  Data_PageFault_Cause,

    // ---- I$ miss port (to shared cache_controller_mmu) ----
    output wire         ibus_req_valid,
    input  wire         ibus_req_ready,
    output wire [31:0]  ibus_req_addr,
    input  wire         ibus_resp_valid,
    input  wire         ibus_resp_error,
    input  wire [255:0] ibus_resp_line,

    // ---- D$ request port (to shared cache_controller_mmu) ----
    output wire         dbus_req_valid,
    input  wire         dbus_req_ready,
    output wire [1:0]   dbus_req_type,
    output wire [31:0]  dbus_req_addr,
    output wire [255:0] dbus_req_line,
    input  wire         dbus_resp_valid,
    input  wire         dbus_resp_error,
    input  wire [255:0] dbus_resp_line,
    input  wire [1:0]   dbus_resp_state,

    // ---- D$ snoop port (from shared cache_controller_mmu) ----
    input  wire         dsnoop_valid,
    input  wire         dsnoop_type,
    input  wire [31:0]  dsnoop_addr,
    output wire         dsnoop_ack_valid,
    output wire         dsnoop_ack_hit,
    output wire         dsnoop_ack_dirty,
    output wire [255:0] dsnoop_ack_line
);

    wire [31:0] PCF;
    wire [31:0] InstrF;
    wire        Instr_ValidF;
    wire        Instr_ErrorF;

    wire [31:0] Mem_AddrM;
    wire [31:0] Mem_WriteDataM;
    wire        Mem_WriteEnM;
    wire        Mem_ReadEnM;
    wire [2:0]  MemOpM;
    wire        Mem_AmoRmwM;
    wire [4:0]  Mem_AmoOpM;
    wire [31:0] Mem_AmoOperandM;
    wire [31:0] Mem_ReadDataM;
    wire        Mem_DataValid;
    wire        Mem_DataError;
    `KLTN_DEBUG_ATTR wire Fetch_AccessFault;
    `KLTN_DEBUG_ATTR wire Data_AccessFault;

    wire [31:0] snoop_addr_to_core;
    wire        snoop_we_to_core;

    wire        fence_i_m;
    reg         cache_flush_seen;
    reg         fence_i_seen;
    reg         cache_flush_active;
    reg         cache_flush_queued;
    reg         dcache_flush_pulse;
    reg         icache_flush_pulse;
    reg         icache_flush_waiting;
    wire        dcache_flush_busy;
    wire        dcache_flush_done;
    wire        dcache_flush_error;
    wire        icache_flush_busy;
    wire        icache_flush_done;
    `KLTN_DEBUG_ATTR reg cache_maintenance_error;

    wire cache_flush_trigger = (Cache_Flush && !cache_flush_seen) ||
                               (fence_i_m && !fence_i_seen);
    // Keep the core frozen for the cycle in which I$ consumes its
    // invalidate pulse; otherwise it could retire one stale fetch on
    // the same edge that the valid bits are being cleared.
    wire cache_maintenance_stall = cache_flush_active | cache_flush_trigger |
                                   icache_flush_pulse | icache_flush_busy;

    assign Cache_Flush_Busy  = cache_maintenance_stall;
    assign Cache_Flush_Error = cache_maintenance_error;

    // FENCE.I and the external maintenance hook use the same ordered
    // sequence: freeze this in-order core, write back every Modified
    // D$ line, then invalidate I$.  A second edge received while the
    // walker is busy is remembered and starts another pass.
    always @(posedge clk) begin
        if (rst) begin
            cache_flush_seen   <= 1'b0;
            fence_i_seen       <= 1'b0;
            cache_flush_active <= 1'b0;
            cache_flush_queued <= 1'b0;
            dcache_flush_pulse <= 1'b0;
            icache_flush_pulse <= 1'b0;
            icache_flush_waiting <= 1'b0;
            cache_maintenance_error <= 1'b0;
            Cache_Flush_Done <= 1'b0;
        end
        else begin
            cache_flush_seen   <= Cache_Flush;
            fence_i_seen       <= fence_i_m;
            dcache_flush_pulse <= 1'b0;
            icache_flush_pulse <= 1'b0;
            Cache_Flush_Done   <= 1'b0;

            if (!cache_flush_active) begin
                if (cache_flush_trigger) begin
                    cache_flush_active <= 1'b1;
                    dcache_flush_pulse <= 1'b1;
                end
            end
            else begin
                if (cache_flush_trigger)
                    cache_flush_queued <= 1'b1;

                if (icache_flush_waiting) begin
                    if (icache_flush_done) begin
                        icache_flush_waiting <= 1'b0;
                        Cache_Flush_Done <= 1'b1;
                        if (cache_flush_queued || cache_flush_trigger) begin
                            cache_flush_queued <= 1'b0;
                            dcache_flush_pulse <= 1'b1;
                        end
                        else begin
                            cache_flush_active <= 1'b0;
                        end
                    end
                end
                else if (dcache_flush_error) begin
                    // Do not invalidate I$ after a failed D$ clean: that
                    // would falsely claim FENCE.I/maintenance completed.
                    // The dirty D$ line is retained; expose a sticky ILA
                    // diagnostic and release the core to avoid deadlock.
                    cache_maintenance_error <= 1'b1;
                    cache_flush_active <= 1'b0;
                    cache_flush_queued <= 1'b0;
                    icache_flush_waiting <= 1'b0;
                    Cache_Flush_Done <= 1'b1;
                end
                else if (dcache_flush_done) begin
                    icache_flush_pulse <= 1'b1;
                    icache_flush_waiting <= 1'b1;
                end
            end
        end
    end

    // Mmu_Flush and the three deprecated MMU parameters are preserved at
    // this wrapper boundary only so old block designs keep elaborating.
    // They do not reach the active core/cache datapath.
    wire unused_mmu_flush = Mmu_Flush;

    physical_core_wrapper #(
        .RESET_ADDR(RESET_ADDR),
        .HART_ID(HART_ID)
    ) physical_core (
        .clk                (clk),
        .rst                (rst),
        .Stall_Core_External(cache_maintenance_stall),

        .Snoop_Addr         (snoop_addr_to_core),
        .Snoop_WE           (snoop_we_to_core),

        .PCF                (PCF),
        .InstrF             (InstrF),
        .Instr_ValidF       (Instr_ValidF),
        .Instr_ErrorF       (Instr_ErrorF),

        .Mem_AddrM          (Mem_AddrM),
        .Mem_WriteDataM     (Mem_WriteDataM),
        .Mem_WriteEnM       (Mem_WriteEnM),
        .Mem_ReadEnM        (Mem_ReadEnM),
        .MemOpM             (MemOpM),
        .Mem_AmoRmwM        (Mem_AmoRmwM),
        .Mem_AmoOpM         (Mem_AmoOpM),
        .Mem_AmoOperandM    (Mem_AmoOperandM),
        .Mem_ReadDataM      (Mem_ReadDataM),
        .Mem_ReadDataValidM (Mem_DataValid),
        .Mem_WriteDoneM     (Mem_DataValid),
        .Mem_ReadErrorM     (Mem_DataError),
        .Mem_WriteErrorM    (Mem_DataError),

        .ResultW            (ResultW),
        .ALU_ResultE_Debug  (ALU_ResultE_Debug),

        .Fetch_AccessFault     (Fetch_AccessFault),
        .Data_AccessFault      (Data_AccessFault),
        .FenceI_M              (fence_i_m)
    );

    assign Fetch_PageFault       = 1'b0;
    assign Data_PageFault        = 1'b0;
    assign Fetch_PageFault_Cause = 2'b00;
    assign Data_PageFault_Cause  = 2'b00;

    l1_icache u_icache (
        .clk            (clk),
        .rst            (rst),
        .flush          (icache_flush_pulse),
        .flush_busy     (icache_flush_busy),
        .flush_done     (icache_flush_done),

        .cpu_addr       (PCF),
        .cpu_rdata      (InstrF),
        .cpu_valid      (Instr_ValidF),
        .cpu_error      (Instr_ErrorF),

        .bus_req_valid  (ibus_req_valid),
        .bus_req_ready  (ibus_req_ready),
        .bus_req_addr   (ibus_req_addr),
        .bus_resp_valid (ibus_resp_valid),
        .bus_resp_error (ibus_resp_error),
        .bus_resp_line  (ibus_resp_line)
    );

    l1_dcache #(.MESI_ENABLE(MESI_ENABLE)) u_dcache (
        .clk            (clk),
        .rst            (rst),
        .flush          (dcache_flush_pulse),
        .flush_busy     (dcache_flush_busy),
        .flush_done     (dcache_flush_done),

        .cpu_addr       (Mem_AddrM),
        .cpu_wdata      (Mem_WriteDataM),
        .cpu_we         (Mem_WriteEnM),
        .cpu_re         (Mem_ReadEnM),
        .cpu_memop      (MemOpM),
        .cpu_amo        (Mem_AmoRmwM),
        .cpu_amo_op     (Mem_AmoOpM),
        .cpu_amo_operand(Mem_AmoOperandM),
        .cpu_rdata      (Mem_ReadDataM),
        .cpu_valid      (Mem_DataValid),
        .cpu_error      (Mem_DataError),

        .bus_req_valid  (dbus_req_valid),
        .bus_req_ready  (dbus_req_ready),
        .bus_req_type   (dbus_req_type),
        .bus_req_addr   (dbus_req_addr),
        .bus_req_line   (dbus_req_line),
        .bus_resp_valid (dbus_resp_valid),
        .bus_resp_error (dbus_resp_error),
        .bus_resp_line  (dbus_resp_line),
        .bus_resp_state (dbus_resp_state),

        .snoop_valid     (dsnoop_valid),
        .snoop_type      (dsnoop_type),
        .snoop_addr      (dsnoop_addr),
        .snoop_ack_valid (dsnoop_ack_valid),
        .snoop_ack_hit   (dsnoop_ack_hit),
        .snoop_ack_dirty (dsnoop_ack_dirty),
        .snoop_ack_line  (dsnoop_ack_line),
        .flush_error     (dcache_flush_error)
    );

    // See header NOTE: fires on an invalidate-type snoop, not a
    // downgrade (downgrade keeps the line readable, no reservation
    // needs to break; RISC-V's LR/SC semantics only require the
    // reservation to break when another agent's WRITE could have
    // touched the location).
    assign snoop_addr_to_core = dsnoop_addr;
    assign snoop_we_to_core   = dsnoop_valid & ~dsnoop_type;

endmodule

`undef KLTN_DEBUG_ATTR
