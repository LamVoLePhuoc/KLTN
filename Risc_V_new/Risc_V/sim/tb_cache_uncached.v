`timescale 1ns / 1ps

// End-to-end regression for the D$ -> coherence-manager uncached/MMIO
// path.  It proves that device accesses are single-word, non-allocating,
// byte-strobe-correct, error-reporting, and recoverable.
module tb_cache_uncached;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst;
    integer errors;
    integer external_requests;
    integer requests_before;

    reg [31:0] cpu_addr, cpu_wdata;
    reg cpu_we, cpu_re;
    reg [2:0] cpu_memop;
    reg cpu_amo;
    wire [31:0] cpu_rdata;
    wire cpu_valid, cpu_error;

    wire dreq_valid;
    wire [1:0] dreq_type;
    wire [31:0] dreq_addr;
    wire [255:0] dreq_line;
    wire dresp_valid, dresp_error;
    wire [255:0] dresp_line;
    wire [1:0] dresp_state;

    wire mem_req_valid, mem_we;
    wire [31:0] mem_addr, mem_wdata;
    wire [3:0] mem_wstrb;
    reg [31:0] mem_rdata;
    reg mem_valid, mem_error;
    reg inject_error;
    reg [31:0] mmio_word;
    reg [31:0] last_addr, last_wdata;
    reg [3:0] last_wstrb;
    reg last_we;
    wire protocol_error;

    l1_dcache #(.INDEX_BITS(1)) dut_dc (
        .clk(clk), .rst(rst), .flush(1'b0), .flush_busy(), .flush_done(),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_we(cpu_we),
        .cpu_re(cpu_re), .cpu_memop(cpu_memop), .cpu_amo(cpu_amo),
        .cpu_amo_op(5'b00000), .cpu_amo_operand(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_valid(cpu_valid), .cpu_error(cpu_error),
        .bus_req_valid(dreq_valid), .bus_req_type(dreq_type),
        .bus_req_addr(dreq_addr), .bus_req_line(dreq_line),
        .bus_resp_valid(dresp_valid), .bus_resp_error(dresp_error),
        .bus_resp_line(dresp_line), .bus_resp_state(dresp_state),
        .snoop_valid(1'b0), .snoop_type(1'b0), .snoop_addr(32'b0),
        .snoop_ack_valid(), .snoop_ack_hit(), .snoop_ack_dirty(),
        .snoop_ack_line(), .flush_error()
    );

    coherence_manager dut_cm (
        .clk(clk), .rst(rst),
        .c0_dreq_valid(dreq_valid), .c0_dreq_type(dreq_type),
        .c0_dreq_addr(dreq_addr), .c0_dreq_line(dreq_line),
        .c0_dresp_valid(dresp_valid), .c0_dresp_error(dresp_error),
        .c0_dresp_line(dresp_line), .c0_dresp_state(dresp_state),
        .c0_dsnoop_valid(), .c0_dsnoop_type(), .c0_dsnoop_addr(),
        .c0_dsnoop_ack_valid(1'b0), .c0_dsnoop_ack_hit(1'b0),
        .c0_dsnoop_ack_dirty(1'b0), .c0_dsnoop_ack_line(256'b0),
        .c0_ireq_valid(1'b0), .c0_ireq_addr(32'b0),
        .c0_iresp_valid(), .c0_iresp_error(), .c0_iresp_line(),

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
        .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
        .mem_valid(mem_valid), .mem_error(mem_error),
        .perf_total_requests(), .perf_d_bus_reads(), .perf_d_rfos(), .perf_d_writebacks(),
        .perf_i_reads(), .perf_l2_hits(), .perf_l2_misses(), .perf_snoop_requests(),
        .perf_mem_read_words(), .perf_mem_write_words(), .perf_busy_cycles(),
        .protocol_error(protocol_error), .timeout_error(), .memory_error(),
        .debug_trace_rd_index(4'b0), .debug_trace_rd_data(), .debug_trace_count(),
        .debug_trace_write_index(), .debug_controller_state()
    );

    integer lane;
    always @(posedge clk) begin
        if (rst) begin
            mem_valid <= 1'b0;
            mem_error <= 1'b0;
            mem_rdata <= 32'b0;
            external_requests <= 0;
            last_addr <= 32'b0;
            last_wdata <= 32'b0;
            last_wstrb <= 4'b0;
            last_we <= 1'b0;
        end
        else begin
            mem_valid <= mem_req_valid;
            mem_error <= mem_req_valid && inject_error;
            if (mem_req_valid) begin
                external_requests <= external_requests + 1;
                last_addr  <= mem_addr;
                last_wdata <= mem_wdata;
                last_wstrb <= mem_wstrb;
                last_we    <= mem_we;
                if (mem_we && !inject_error) begin
                    for (lane = 0; lane < 4; lane = lane + 1)
                        if (mem_wstrb[lane])
                            mmio_word[lane*8 +: 8] <= mem_wdata[lane*8 +: 8];
                end
                else if (!mem_we) begin
                    mem_rdata <= mmio_word;
                end
            end
        end
    end

    task check;
        input condition;
        input [8*96-1:0] name;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
            else $display("[PASS] %0s", name);
        end
    endtask

    task access;
        input [31:0] addr;
        input [31:0] wdata;
        input we;
        input [2:0] memop;
        input amo;
        output [31:0] rdata;
        output fault;
        begin
            @(negedge clk);
            cpu_addr = addr;
            cpu_wdata = wdata;
            cpu_we = we;
            cpu_re = ~we;
            cpu_memop = memop;
            cpu_amo = amo;
            wait (cpu_valid);
            #1;
            rdata = cpu_rdata;
            fault = cpu_error;
            @(negedge clk);
            cpu_we = 1'b0;
            cpu_re = 1'b0;
            cpu_amo = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    reg [31:0] got;
    reg fault;
    initial begin
        errors = 0;
        rst = 1'b1;
        cpu_addr = 0;
        cpu_wdata = 0;
        cpu_we = 0;
        cpu_re = 0;
        cpu_memop = 3'b010;
        cpu_amo = 0;
        inject_error = 0;
        mmio_word = 32'hA1B2_C3D4;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (2) @(posedge clk);

        access(32'hC000_0003, 0, 1'b0, 3'b000, 1'b0, got, fault); // LB
        check(!fault && got == 32'hFFFF_FFA1, "uncached LB sign-extends selected byte");
        check(last_addr == 32'hC000_0000 && !last_we && last_wstrb == 4'b0,
              "uncached read is one aligned external word and carries no write lanes");

        requests_before = external_requests;
        access(32'hC000_0002, 0, 1'b0, 3'b101, 1'b0, got, fault); // LHU
        check(!fault && got == 32'h0000_A1B2, "uncached LHU extracts upper halfword");
        check(external_requests == requests_before + 1,
              "second MMIO read reaches the device again (no L1/L2 allocation)");

        access(32'hC000_0001, 32'h0000_00EE, 1'b1, 3'b000, 1'b0, got, fault); // SB
        check(!fault && mmio_word == 32'hA1B2_EED4, "uncached SB preserves untouched device lanes");
        check(last_addr == 32'hC000_0000 && last_wstrb == 4'b0010 &&
              last_wdata == 32'h0000_EE00,
              "uncached SB propagates aligned address, shifted data and WSTRB");

        access(32'hC000_0002, 32'h0000_5566, 1'b1, 3'b001, 1'b0, got, fault); // SH
        check(!fault && mmio_word == 32'h5566_EED4, "uncached SH preserves lower device halfword");
        check(last_wstrb == 4'b1100 && last_wdata == 32'h5566_0000,
              "uncached SH propagates upper byte lanes");

        access(32'hC000_0000, 32'h1234_5678, 1'b1, 3'b010, 1'b0, got, fault); // SW
        check(!fault && mmio_word == 32'h1234_5678 && last_wstrb == 4'b1111,
              "uncached SW writes every byte lane");

        inject_error = 1'b1;
        access(32'hC000_0000, 0, 1'b0, 3'b010, 1'b0, got, fault);
        check(fault, "MMIO bus error reaches D$ as an access error");
        inject_error = 1'b0;
        access(32'hC000_0000, 0, 1'b0, 3'b010, 1'b0, got, fault);
        check(!fault && got == 32'h1234_5678, "MMIO path recovers after an error");

        requests_before = external_requests;
        access(32'hC000_0000, 32'h1, 1'b1, 3'b010, 1'b1, got, fault);
        check(fault && external_requests == requests_before,
              "unsupported uncached AMO faults without issuing a non-atomic device write");
        check(!protocol_error, "valid uncached traffic does not latch coherence protocol_error");

        if (errors == 0) $display("CACHE_UNCACHED_TB: PASS");
        else             $display("CACHE_UNCACHED_TB: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
