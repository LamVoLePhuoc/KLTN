`timescale 1ns / 1ps

// Fault-injection test: external memory deliberately never answers an
// L2 miss.  The CM must keep the atomic transaction intact but raise
// its sticky timeout/protocol diagnostics.
module tb_coherence_watchdog;
    reg clk, rst;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg c0_req;
    wire mem_req_valid, mem_we;
    wire [31:0] mem_addr, mem_wdata;
    wire protocol_error, timeout_error;

    coherence_manager #(
        .WATCHDOG_LIMIT(8)
    ) dut (
        .clk(clk), .rst(rst),

        .c0_dreq_valid(c0_req), .c0_dreq_type(2'b00), .c0_dreq_addr(32'h0002_0000), .c0_dreq_line(256'b0),
        .c0_dresp_valid(), .c0_dresp_error(), .c0_dresp_line(), .c0_dresp_state(),
        .c0_dsnoop_valid(), .c0_dsnoop_type(), .c0_dsnoop_addr(),
        .c0_dsnoop_ack_valid(1'b0), .c0_dsnoop_ack_hit(1'b0),
        .c0_dsnoop_ack_dirty(1'b0), .c0_dsnoop_ack_line(256'b0),
        .c0_ireq_valid(1'b0), .c0_ireq_addr(32'b0), .c0_iresp_valid(), .c0_iresp_error(), .c0_iresp_line(),

        .c1_dreq_valid(1'b0), .c1_dreq_type(2'b0), .c1_dreq_addr(32'b0), .c1_dreq_line(256'b0),
        .c1_dresp_valid(), .c1_dresp_error(), .c1_dresp_line(), .c1_dresp_state(),
        .c1_dsnoop_valid(), .c1_dsnoop_type(), .c1_dsnoop_addr(),
        .c1_dsnoop_ack_valid(1'b0), .c1_dsnoop_ack_hit(1'b0),
        .c1_dsnoop_ack_dirty(1'b0), .c1_dsnoop_ack_line(256'b0),
        .c1_ireq_valid(1'b0), .c1_ireq_addr(32'b0), .c1_iresp_valid(), .c1_iresp_error(), .c1_iresp_line(),

        .c2_dreq_valid(1'b0), .c2_dreq_type(2'b0), .c2_dreq_addr(32'b0), .c2_dreq_line(256'b0),
        .c2_dresp_valid(), .c2_dresp_error(), .c2_dresp_line(), .c2_dresp_state(),
        .c2_dsnoop_valid(), .c2_dsnoop_type(), .c2_dsnoop_addr(),
        .c2_dsnoop_ack_valid(1'b0), .c2_dsnoop_ack_hit(1'b0),
        .c2_dsnoop_ack_dirty(1'b0), .c2_dsnoop_ack_line(256'b0),
        .c2_ireq_valid(1'b0), .c2_ireq_addr(32'b0), .c2_iresp_valid(), .c2_iresp_error(), .c2_iresp_line(),

        .c3_dreq_valid(1'b0), .c3_dreq_type(2'b0), .c3_dreq_addr(32'b0), .c3_dreq_line(256'b0),
        .c3_dresp_valid(), .c3_dresp_error(), .c3_dresp_line(), .c3_dresp_state(),
        .c3_dsnoop_valid(), .c3_dsnoop_type(), .c3_dsnoop_addr(),
        .c3_dsnoop_ack_valid(1'b0), .c3_dsnoop_ack_hit(1'b0),
        .c3_dsnoop_ack_dirty(1'b0), .c3_dsnoop_ack_line(256'b0),
        .c3_ireq_valid(1'b0), .c3_ireq_addr(32'b0), .c3_iresp_valid(), .c3_iresp_error(), .c3_iresp_line(),

        .mem_req_valid(mem_req_valid), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(32'b0), .mem_valid(1'b0), .mem_error(1'b0),
        .perf_total_requests(), .perf_d_bus_reads(), .perf_d_rfos(), .perf_d_writebacks(),
        .perf_i_reads(), .perf_l2_hits(), .perf_l2_misses(), .perf_snoop_requests(),
        .perf_mem_read_words(), .perf_mem_write_words(), .perf_busy_cycles(),
        .protocol_error(protocol_error), .timeout_error(timeout_error), .memory_error(),
        .debug_trace_rd_index(4'b0), .debug_trace_rd_data(), .debug_trace_count(),
        .debug_trace_write_index(), .debug_controller_state()
    );

    integer cycles;
    initial begin
        rst = 1'b1;
        c0_req = 1'b0;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(negedge clk);
        c0_req = 1'b1;

        cycles = 0;
        while (!timeout_error && cycles < 100) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (timeout_error && protocol_error)
            $display("CACHE_WATCHDOG_TB: PASS");
        else
            $display("CACHE_WATCHDOG_TB: FAIL timeout=%b protocol=%b", timeout_error, protocol_error);
        $finish;
    end
endmodule
