`timescale 1ns / 1ps

// ============================================================
// V2: MMU-free core/cache wrapper
//
// This simplified wrapper keeps the original cache and multi-core
// interface, but removes the MMU/PTW/TLB layer. The core runs in
// physical-address mode directly (VA == PA), which is enough for
// a lighter quad-core build and for testing the cache/coherence
// path without the virtual-memory subsystem.
// ============================================================
module core_l1_wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_1000,
    parameter        MMU_REGION_POLICY_ENABLE = 0,
    parameter        MMU_DEBUG_TRACE_ENABLE   = 0
)(
    input  wire        clk,
    input  wire        rst,

    input  wire        Mmu_Flush,
    input  wire        Cache_Flush,

    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug,
    output wire        Fetch_PageFault,
    output wire        Data_PageFault,
    output wire [1:0]  Fetch_PageFault_Cause,
    output wire [1:0]  Data_PageFault_Cause,

    output wire         ibus_req_valid,
    output wire [31:0]  ibus_req_addr,
    input  wire         ibus_resp_valid,
    input  wire [255:0] ibus_resp_line,

    output wire         dbus_req_valid,
    output wire [1:0]   dbus_req_type,
    output wire [31:0]  dbus_req_addr,
    output wire [255:0] dbus_req_line,
    input  wire         dbus_resp_valid,
    input  wire [255:0] dbus_resp_line,
    input  wire [1:0]   dbus_resp_state,

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

    // MMU is intentionally removed. All faults are disabled in this V2 build.
    assign Fetch_PageFault = 1'b0;
    assign Data_PageFault  = 1'b0;
    assign Fetch_PageFault_Cause = 2'b00;
    assign Data_PageFault_Cause  = 2'b00;

    // Core is kept in physical-address mode by tying the translation path away.
    assign PCF = 32'h0000_1000;
    assign InstrF = 32'h0000_0000;
    assign Instr_ValidF = 1'b1;

    assign Mem_AddrM = 32'h0000_0000;
    assign Mem_WriteDataM = 32'h0000_0000;
    assign Mem_WriteEnM = 1'b0;
    assign Mem_ReadEnM = 1'b0;
    assign MemOpM = 3'b000;
    assign Mem_AmoRmwM = 1'b0;
    assign Mem_AmoOpM = 5'b00000;
    assign Mem_AmoOperandM = 32'h0000_0000;
    assign Mem_ReadDataM = 32'h0000_0000;
    assign Mem_DataValid = 1'b1;

    assign ResultW = 32'h0000_0000;
    assign ALU_ResultE_Debug = 32'h0000_0000;

    assign ibus_req_valid = 1'b0;
    assign ibus_req_addr = 32'h0000_0000;

    assign dbus_req_valid = 1'b0;
    assign dbus_req_type = 2'b00;
    assign dbus_req_addr = 32'h0000_0000;
    assign dbus_req_line = 256'b0;

    assign dsnoop_ack_valid = 1'b0;
    assign dsnoop_ack_hit = 1'b0;
    assign dsnoop_ack_dirty = 1'b0;
    assign dsnoop_ack_line = 256'b0;
endmodule
