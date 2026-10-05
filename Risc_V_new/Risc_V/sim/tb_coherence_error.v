`timescale 1ns / 1ps

// Error-path regression for the serialized L2/coherence engine. It proves
// requester attribution, no-fill-on-error, and dirty-victim preservation.
module tb_coherence_error;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst;
    integer errors;
    integer mem_reads;

    reg c0_dreq_valid;
    reg [1:0] c0_dreq_type;
    reg [31:0] c0_dreq_addr;
    reg [255:0] c0_dreq_line;
    wire c0_dresp_valid, c0_dresp_error;
    wire [255:0] c0_dresp_line;
    wire [1:0] c0_dresp_state;

    reg c0_ireq_valid;
    reg [31:0] c0_ireq_addr;
    wire c0_iresp_valid, c0_iresp_error;
    wire [255:0] c0_iresp_line;

    wire mem_req_valid, mem_we;
    wire [31:0] mem_addr, mem_wdata;
    reg [31:0] mem_rdata;
    reg mem_valid, mem_error;
    reg inject_error;
    reg [31:0] error_addr;
    wire memory_error;

    reg [31:0] memory [0:262143];
    integer k;

    coherence_manager dut (
        .clk(clk), .rst(rst),
        .c0_dreq_valid(c0_dreq_valid), .c0_dreq_type(c0_dreq_type),
        .c0_dreq_addr(c0_dreq_addr), .c0_dreq_line(c0_dreq_line),
        .c0_dresp_valid(c0_dresp_valid), .c0_dresp_error(c0_dresp_error),
        .c0_dresp_line(c0_dresp_line), .c0_dresp_state(c0_dresp_state),
        .c0_dsnoop_valid(), .c0_dsnoop_type(), .c0_dsnoop_addr(),
        .c0_dsnoop_ack_valid(1'b0), .c0_dsnoop_ack_hit(1'b0),
        .c0_dsnoop_ack_dirty(1'b0), .c0_dsnoop_ack_line(256'b0),
        .c0_ireq_valid(c0_ireq_valid), .c0_ireq_addr(c0_ireq_addr),
        .c0_iresp_valid(c0_iresp_valid), .c0_iresp_error(c0_iresp_error),
        .c0_iresp_line(c0_iresp_line),

        .c1_dreq_valid(1'b0), .c1_dreq_type(2'b0), .c1_dreq_addr(32'b0), .c1_dreq_line(256'b0),
        .c1_dresp_valid(), .c1_dresp_error(), .c1_dresp_line(), .c1_dresp_state(),
        .c1_dsnoop_valid(), .c1_dsnoop_type(), .c1_dsnoop_addr(),
        .c1_dsnoop_ack_valid(1'b0), .c1_dsnoop_ack_hit(1'b0), .c1_dsnoop_ack_dirty(1'b0), .c1_dsnoop_ack_line(256'b0),
        .c1_ireq_valid(1'b0), .c1_ireq_addr(32'b0), .c1_iresp_valid(), .c1_iresp_error(), .c1_iresp_line(),

        .c2_dreq_valid(1'b0), .c2_dreq_type(2'b0), .c2_dreq_addr(32'b0), .c2_dreq_line(256'b0),
        .c2_dresp_valid(), .c2_dresp_error(), .c2_dresp_line(), .c2_dresp_state(),
        .c2_dsnoop_valid(), .c2_dsnoop_type(), .c2_dsnoop_addr(),
        .c2_dsnoop_ack_valid(1'b0), .c2_dsnoop_ack_hit(1'b0), .c2_dsnoop_ack_dirty(1'b0), .c2_dsnoop_ack_line(256'b0),
        .c2_ireq_valid(1'b0), .c2_ireq_addr(32'b0), .c2_iresp_valid(), .c2_iresp_error(), .c2_iresp_line(),

        .c3_dreq_valid(1'b0), .c3_dreq_type(2'b0), .c3_dreq_addr(32'b0), .c3_dreq_line(256'b0),
        .c3_dresp_valid(), .c3_dresp_error(), .c3_dresp_line(), .c3_dresp_state(),
        .c3_dsnoop_valid(), .c3_dsnoop_type(), .c3_dsnoop_addr(),
        .c3_dsnoop_ack_valid(1'b0), .c3_dsnoop_ack_hit(1'b0), .c3_dsnoop_ack_dirty(1'b0), .c3_dsnoop_ack_line(256'b0),
        .c3_ireq_valid(1'b0), .c3_ireq_addr(32'b0), .c3_iresp_valid(), .c3_iresp_error(), .c3_iresp_line(),

        .mem_req_valid(mem_req_valid), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
        .mem_valid(mem_valid), .mem_error(mem_error),
        .perf_total_requests(), .perf_d_bus_reads(), .perf_d_rfos(), .perf_d_writebacks(),
        .perf_i_reads(), .perf_l2_hits(), .perf_l2_misses(), .perf_snoop_requests(),
        .perf_mem_read_words(), .perf_mem_write_words(), .perf_busy_cycles(),
        .protocol_error(), .timeout_error(), .memory_error(memory_error),
        .debug_trace_rd_index(4'b0), .debug_trace_rd_data(), .debug_trace_count(),
        .debug_trace_write_index(), .debug_controller_state()
    );

    always @(posedge clk) begin
        if (rst) begin
            mem_valid <= 1'b0;
            mem_error <= 1'b0;
            mem_rdata <= 32'b0;
            mem_reads <= 0;
        end
        else begin
            mem_valid <= mem_req_valid;
            mem_error <= mem_req_valid && inject_error && (mem_addr == error_addr);
            if (mem_req_valid) begin
                if (mem_we) begin
                    if (!(inject_error && (mem_addr == error_addr)))
                        memory[mem_addr[19:2]] <= mem_wdata;
                end
                else begin
                    mem_rdata <= memory[mem_addr[19:2]];
                    mem_reads <= mem_reads + 1;
                end
            end
        end
    end

    task check;
        input condition;
        input [8*88-1:0] name;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
            else $display("[PASS] %0s", name);
        end
    endtask

    task issue_i;
        input [31:0] addr;
        output response_error;
        begin
            @(negedge clk);
            c0_ireq_addr = addr;
            c0_ireq_valid = 1'b1;
            wait (c0_iresp_valid);
            #1 response_error = c0_iresp_error;
            @(negedge clk);
            c0_ireq_valid = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task issue_d;
        input [1:0] typ;
        input [31:0] addr;
        input [255:0] line;
        output response_error;
        begin
            @(negedge clk);
            c0_dreq_type = typ;
            c0_dreq_addr = addr;
            c0_dreq_line = line;
            c0_dreq_valid = 1'b1;
            wait (c0_dresp_valid);
            #1 response_error = c0_dresp_error;
            @(negedge clk);
            c0_dreq_valid = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    reg response_error;
    integer reads_before;
    reg [255:0] dirty_line;
    localparam [31:0] I_ADDR = 32'h0000_1000;
    localparam [31:0] D_ERR  = 32'h0000_4000;
    localparam [31:0] A0 = 32'h0001_0000;
    localparam [31:0] A1 = 32'h0003_0000;
    localparam [31:0] A2 = 32'h0005_0000;
    localparam [31:0] A3 = 32'h0007_0000;
    localparam [31:0] A4 = 32'h0009_0000;

    initial begin
        for (k = 0; k < 262144; k = k + 1)
            memory[k] = 32'h4000_0000 + k;

        rst = 1'b1; errors = 0;
        c0_dreq_valid = 1'b0; c0_dreq_type = 2'b0;
        c0_dreq_addr = 32'b0; c0_dreq_line = 256'b0;
        c0_ireq_valid = 1'b0; c0_ireq_addr = 32'b0;
        inject_error = 1'b0; error_addr = 32'b0;
        dirty_line = {8{32'hD17D_0001}};

        repeat (4) @(posedge clk);
        rst = 1'b0;

        // Instruction-side error is returned only to the I requester.
        inject_error = 1'b1; error_addr = I_ADDR;
        issue_i(I_ADDR, response_error);
        check(response_error, "I-line memory error returned on iresp_error");
        check(!c0_dresp_valid, "I-line error was not misrouted to D response");
        check(memory_error, "coherence memory_error diagnostic latched");

        // Retry must refetch all eight words: the failed line was not filled.
        inject_error = 1'b0;
        reads_before = mem_reads;
        issue_i(I_ADDR, response_error);
        check(!response_error, "I-line retry succeeds after error removal");
        check((mem_reads - reads_before) == 8,
              "failed I-line response did not allocate L2");

        inject_error = 1'b1; error_addr = D_ERR;
        issue_d(2'b00, D_ERR, 256'b0, response_error);
        check(response_error, "D-line memory error returned on dresp_error");

        // Build one dirty L2 victim in way 0 and fill the remaining ways
        // of the same set. A4 then evicts A0; fail word 1 of that WB.
        inject_error = 1'b0;
        issue_d(2'b01, A0, 256'b0, response_error); // RFO/fill
        issue_d(2'b10, A0, dirty_line, response_error); // L1 writeback -> L2 dirty
        issue_d(2'b00, A1, 256'b0, response_error);
        issue_d(2'b00, A2, 256'b0, response_error);
        issue_d(2'b00, A3, 256'b0, response_error);

        inject_error = 1'b1; error_addr = A0 + 32'd4;
        issue_d(2'b00, A4, 256'b0, response_error);
        check(response_error, "dirty-victim writeback error returned to requester");
        check(dut.u_engine.g_internal_l2.u_l2.valid_r[0][12'h800] && dut.u_engine.g_internal_l2.u_l2.dirty_r[0][12'h800],
              "failed dirty victim restored valid+dirty in L2");
        check(dut.u_engine.g_internal_l2.u_l2.tag_r[0][12'h800] == A0[31:17],
              "restored victim kept original L2 tag");
        check(dut.u_engine.g_internal_l2.u_l2.data_r[0][12'h800] == dirty_line,
              "restored victim kept authoritative dirty data");
        check(dut.u_engine.g_internal_l2.u_l2.sharers_r[0][12'h800] == 4'b0,
              "restored victim has no stale sharers");

        if (errors == 0) $display("COHERENCE_ERROR_TB: PASS");
        else             $display("COHERENCE_ERROR_TB: FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("COHERENCE_ERROR_TB: FAIL (timeout)");
        $finish;
    end
endmodule
