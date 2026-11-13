`timescale 1ns / 1ps

// Synthesis-only shell used by the hierarchical full-SoC PPA flow.  Each
// instance is replaced after parent synthesis by a HART_ID-specific OOC DCP.
(* black_box = "yes", syn_black_box = 1 *)
module core_l1_wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_1000,
    parameter [31:0] HART_ID = 32'd0,
    parameter MESI_ENABLE = 0,
    parameter MMU_REGION_POLICY_ENABLE = 0,
    parameter MMU_DEBUG_TRACE_ENABLE = 0,
    parameter integer MMU_PTW_WATCHDOG_CYCLES = 0
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         Mmu_Flush,
    input  wire         Cache_Flush,
    output wire         Cache_Flush_Busy,
    output wire         Cache_Flush_Done,
    output wire         Cache_Flush_Error,
    output wire [31:0]  ResultW,
    output wire [31:0]  ALU_ResultE_Debug,
    output wire         Fetch_PageFault,
    output wire         Data_PageFault,
    output wire [1:0]   Fetch_PageFault_Cause,
    output wire [1:0]   Data_PageFault_Cause,
    output wire         ibus_req_valid,
    input  wire         ibus_req_ready,
    output wire [31:0]  ibus_req_addr,
    input  wire         ibus_resp_valid,
    input  wire         ibus_resp_error,
    input  wire [255:0] ibus_resp_line,
    output wire         dbus_req_valid,
    input  wire         dbus_req_ready,
    output wire [1:0]   dbus_req_type,
    output wire [31:0]  dbus_req_addr,
    output wire [255:0] dbus_req_line,
    input  wire         dbus_resp_valid,
    input  wire         dbus_resp_error,
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
endmodule
