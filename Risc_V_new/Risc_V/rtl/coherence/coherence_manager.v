`timescale 1ns / 1ps

// Backward-compatible facade for legacy unit tests and integrations.
// The cache/coherence FSM is owned by cache_controller_mmu; this wrapper
// only selects the legacy internal-L2 configuration.
module coherence_manager #(
    parameter LINE_WORDS = 8,
    parameter PERF_COUNTER_ENABLE = 1,
    parameter DEBUG_TRACE_ENABLE = 0,
    parameter integer WATCHDOG_LIMIT = 1024
)(
    input wire clk, input wire rst,
    input wire c0_dreq_valid, input wire [1:0] c0_dreq_type, input wire [31:0] c0_dreq_addr, input wire [255:0] c0_dreq_line,
    output wire c0_dresp_valid, output wire c0_dresp_error, output wire [255:0] c0_dresp_line, output wire [1:0] c0_dresp_state,
    output wire c0_dsnoop_valid, output wire c0_dsnoop_type, output wire [31:0] c0_dsnoop_addr,
    input wire c0_dsnoop_ack_valid, input wire c0_dsnoop_ack_hit, input wire c0_dsnoop_ack_dirty, input wire [255:0] c0_dsnoop_ack_line,
    input wire c0_ireq_valid, input wire [31:0] c0_ireq_addr,
    output wire c0_iresp_valid, output wire c0_iresp_error, output wire [255:0] c0_iresp_line,
    input wire c1_dreq_valid, input wire [1:0] c1_dreq_type, input wire [31:0] c1_dreq_addr, input wire [255:0] c1_dreq_line,
    output wire c1_dresp_valid, output wire c1_dresp_error, output wire [255:0] c1_dresp_line, output wire [1:0] c1_dresp_state,
    output wire c1_dsnoop_valid, output wire c1_dsnoop_type, output wire [31:0] c1_dsnoop_addr,
    input wire c1_dsnoop_ack_valid, input wire c1_dsnoop_ack_hit, input wire c1_dsnoop_ack_dirty, input wire [255:0] c1_dsnoop_ack_line,
    input wire c1_ireq_valid, input wire [31:0] c1_ireq_addr,
    output wire c1_iresp_valid, output wire c1_iresp_error, output wire [255:0] c1_iresp_line,
    input wire c2_dreq_valid, input wire [1:0] c2_dreq_type, input wire [31:0] c2_dreq_addr, input wire [255:0] c2_dreq_line,
    output wire c2_dresp_valid, output wire c2_dresp_error, output wire [255:0] c2_dresp_line, output wire [1:0] c2_dresp_state,
    output wire c2_dsnoop_valid, output wire c2_dsnoop_type, output wire [31:0] c2_dsnoop_addr,
    input wire c2_dsnoop_ack_valid, input wire c2_dsnoop_ack_hit, input wire c2_dsnoop_ack_dirty, input wire [255:0] c2_dsnoop_ack_line,
    input wire c2_ireq_valid, input wire [31:0] c2_ireq_addr,
    output wire c2_iresp_valid, output wire c2_iresp_error, output wire [255:0] c2_iresp_line,
    input wire c3_dreq_valid, input wire [1:0] c3_dreq_type, input wire [31:0] c3_dreq_addr, input wire [255:0] c3_dreq_line,
    output wire c3_dresp_valid, output wire c3_dresp_error, output wire [255:0] c3_dresp_line, output wire [1:0] c3_dresp_state,
    output wire c3_dsnoop_valid, output wire c3_dsnoop_type, output wire [31:0] c3_dsnoop_addr,
    input wire c3_dsnoop_ack_valid, input wire c3_dsnoop_ack_hit, input wire c3_dsnoop_ack_dirty, input wire [255:0] c3_dsnoop_ack_line,
    input wire c3_ireq_valid, input wire [31:0] c3_ireq_addr,
    output wire c3_iresp_valid, output wire c3_iresp_error, output wire [255:0] c3_iresp_line,
    output wire mem_req_valid, output wire mem_we, output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata, output wire [3:0] mem_wstrb,
    input wire [31:0] mem_rdata, input wire mem_valid, input wire mem_error,
    output wire [31:0] perf_total_requests, output wire [31:0] perf_d_bus_reads,
    output wire [31:0] perf_d_rfos, output wire [31:0] perf_d_writebacks,
    output wire [31:0] perf_i_reads, output wire [31:0] perf_l2_hits,
    output wire [31:0] perf_l2_misses, output wire [31:0] perf_snoop_requests,
    output wire [31:0] perf_mem_read_words, output wire [31:0] perf_mem_write_words,
    output wire [31:0] perf_busy_cycles, output wire protocol_error,
    output wire timeout_error, output wire memory_error,
    input wire [3:0] debug_trace_rd_index, output wire [95:0] debug_trace_rd_data,
    output wire [4:0] debug_trace_count, output wire [3:0] debug_trace_write_index,
    output wire [3:0] debug_controller_state
);
    cache_controller_mmu #(
        .LINE_WORDS(LINE_WORDS), .PERF_COUNTER_ENABLE(PERF_COUNTER_ENABLE),
        .DEBUG_TRACE_ENABLE(DEBUG_TRACE_ENABLE), .WATCHDOG_LIMIT(WATCHDOG_LIMIT),
        .EXTERNAL_L2(0), .REQUEST_QUEUE_ENABLE(0)
    ) u_cache_controller_mmu (
        .c0_dreq_ready(), .c0_ireq_ready(),
        .c1_dreq_ready(), .c1_ireq_ready(),
        .c2_dreq_ready(), .c2_ireq_ready(),
        .c3_dreq_ready(), .c3_ireq_ready(),
        .l2_cmd_valid_o(), .l2_cmd_we_o(), .l2_cmd_addr_o(), .l2_cmd_way_o(),
        .l2_cmd_wdata_o(), .l2_cmd_w_valid_o(), .l2_cmd_w_dirty_o(),
        .l2_cmd_w_sharers_o(), .l2_resp_valid_i(1'b0), .l2_resp_hit_i(1'b0),
        .l2_resp_way_i(2'b0), .l2_resp_victim_tag_i(15'b0),
        .l2_resp_victim_valid_i(1'b0), .l2_resp_victim_dirty_i(1'b0),
        .l2_resp_victim_sharers_i(4'b0), .l2_resp_line_i(256'b0),
        .l2_resp_sharers_i(4'b0), .*
    );
endmodule
