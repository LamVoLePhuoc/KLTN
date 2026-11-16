`timescale 1ns / 1ps

// A real RV32IMA core generates exactly 1000 sequential cached LW requests.
// With a cold 32-byte-line D-cache, eight words share each line, so the
// deterministic result is 125 read misses and 875 hits.
module tb_dcache_1000_cpu_requests;
    localparam CLK_PERIOD       = 10;
    localparam MEM_WORDS        = 16384;
    localparam BOOT_ADDR        = 32'h0000_1000;
    localparam DATA_ADDR        = 32'h0000_7000;
    localparam REQUESTS         = 1000;
    localparam EXPECTED_MISSES  = 125;
    localparam EXPECTED_HITS    = REQUESTS - EXPECTED_MISSES;
    localparam EXPECTED_LAST_WORD = 32'd999;
    localparam COMPLETION_MAGIC = 32'h0000_05a5;

    reg clk;
    reg rst;
    wire [31:0] result_w;
    wire fetch_page_fault, data_page_fault;

    wire ibus_req_valid;
    wire [31:0] ibus_req_addr;
    reg ibus_resp_valid;
    reg ibus_resp_error;
    reg [255:0] ibus_resp_line;

    wire dbus_req_valid;
    wire [1:0] dbus_req_type;
    wire [31:0] dbus_req_addr;
    wire [255:0] dbus_req_line;
    reg dbus_resp_valid;
    reg dbus_resp_error;
    reg [255:0] dbus_resp_line;
    reg [1:0] dbus_resp_state;

    reg [31:0] memory [0:MEM_WORDS-1];
    reg i_request_seen;
    reg d_request_seen;
    reg program_done;
    reg final_word_seen;
    integer d_line_reads;
    integer errors;
    integer cycles;
    integer miss_rate_bp;
    integer i;
    integer j;
    integer k;

    function [31:0] enc_addi;
        input [4:0] rd;
        input [4:0] rs1;
        input [11:0] imm;
        begin enc_addi = {imm, rs1, 3'b000, rd, 7'b0010011}; end
    endfunction

    function [31:0] enc_lui;
        input [4:0] rd;
        input [19:0] imm20;
        begin enc_lui = {imm20, rd, 7'b0110111}; end
    endfunction

    function [31:0] enc_lw;
        input [4:0] rd;
        input [4:0] rs1;
        input [11:0] imm;
        begin enc_lw = {imm, rs1, 3'b010, rd, 7'b0000011}; end
    endfunction

    task check_true;
        input condition;
        input [8*96-1:0] label_text;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[FAIL] %0s", label_text);
            end
            else begin
                $display("[PASS] %0s", label_text);
            end
        end
    endtask

    core_l1_wrapper #(
        .RESET_ADDR(BOOT_ADDR),
        .HART_ID(32'd0),
        .MESI_ENABLE(1)
    ) dut (
        .clk(clk), .rst(rst),
        .Mmu_Flush(1'b0), .Cache_Flush(1'b0),
        .Cache_Flush_Busy(), .Cache_Flush_Done(), .Cache_Flush_Error(),
        .ResultW(result_w), .ALU_ResultE_Debug(),
        .Fetch_PageFault(fetch_page_fault), .Data_PageFault(data_page_fault),
        .Fetch_PageFault_Cause(), .Data_PageFault_Cause(),
        .ibus_req_valid(ibus_req_valid), .ibus_req_ready(1'b1),
        .ibus_req_addr(ibus_req_addr), .ibus_resp_valid(ibus_resp_valid),
        .ibus_resp_error(ibus_resp_error), .ibus_resp_line(ibus_resp_line),
        .dbus_req_valid(dbus_req_valid), .dbus_req_ready(1'b1),
        .dbus_req_type(dbus_req_type), .dbus_req_addr(dbus_req_addr),
        .dbus_req_line(dbus_req_line), .dbus_resp_valid(dbus_resp_valid),
        .dbus_resp_error(dbus_resp_error), .dbus_resp_line(dbus_resp_line),
        .dbus_resp_state(dbus_resp_state),
        .dsnoop_valid(1'b0), .dsnoop_type(1'b0), .dsnoop_addr(32'b0),
        .dsnoop_ack_valid(), .dsnoop_ack_hit(),
        .dsnoop_ack_dirty(), .dsnoop_ack_line()
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Independent I$ and D$ line responders.  The D$ read response grants E
    // because this one-core workload has no other sharers.
    always @(posedge clk) begin
        ibus_resp_valid <= 1'b0;
        ibus_resp_error <= 1'b0;
        dbus_resp_valid <= 1'b0;
        dbus_resp_error <= 1'b0;

        if (rst) begin
            i_request_seen <= 1'b0;
            d_request_seen <= 1'b0;
        end
        else begin
            if (!ibus_req_valid) begin
                i_request_seen <= 1'b0;
            end
            else if (!i_request_seen) begin
                i_request_seen <= 1'b1;
                for (j = 0; j < 8; j = j + 1)
                    ibus_resp_line[j*32 +: 32] <=
                        memory[(ibus_req_addr[15:2] & 14'h3ff8) + j];
                ibus_resp_valid <= 1'b1;
            end

            if (!dbus_req_valid) begin
                d_request_seen <= 1'b0;
            end
            else if (!d_request_seen) begin
                d_request_seen <= 1'b1;
                if (dbus_req_type == 2'b10) begin
                    for (j = 0; j < 8; j = j + 1)
                        memory[(dbus_req_addr[15:2] & 14'h3ff8) + j] <=
                            dbus_req_line[j*32 +: 32];
                    dbus_resp_state <= 2'b00;
                end
                else begin
                    d_line_reads <= d_line_reads + 1;
                    for (j = 0; j < 8; j = j + 1)
                        dbus_resp_line[j*32 +: 32] <=
                            memory[(dbus_req_addr[15:2] & 14'h3ff8) + j];
                    dbus_resp_state <= 2'b10; // MESI Exclusive grant
                end
                dbus_resp_valid <= 1'b1;
            end

            if (result_w == EXPECTED_LAST_WORD)
                final_word_seen <= 1'b1;
            if (result_w == COMPLETION_MAGIC)
                program_done <= 1'b1;

            if (fetch_page_fault || data_page_fault) begin
                errors = errors + 1;
                $display("[FAIL] page-fault output asserted in physical workload");
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        ibus_resp_valid = 1'b0;
        ibus_resp_error = 1'b0;
        ibus_resp_line = 256'b0;
        dbus_resp_valid = 1'b0;
        dbus_resp_error = 1'b0;
        dbus_resp_line = 256'b0;
        dbus_resp_state = 2'b00;
        i_request_seen = 1'b0;
        d_request_seen = 1'b0;
        program_done = 1'b0;
        final_word_seen = 1'b0;
        d_line_reads = 0;
        errors = 0;
        cycles = 0;
        miss_rate_bp = 0;

        for (i = 0; i < MEM_WORDS; i = i + 1)
            memory[i] = 32'h0000_0013;

        // Unroll the first workload so this test measures the D-cache rather
        // than the core's branch scheduling. x2 walks 1000 sequential words;
        // explicit NOP spacing removes data-hazard ambiguity from the result.
        i = BOOT_ADDR >> 2;
        memory[i + 0] = enc_lui(5'd2, 20'h00007);
        memory[i + 1] = 32'h0000_0013;
        memory[i + 2] = 32'h0000_0013;
        for (k = 0; k < REQUESTS; k = k + 1) begin
            memory[i + 3 + k*6 + 0] = enc_lw(5'd3, 5'd2, 12'd0);
            memory[i + 3 + k*6 + 1] = 32'h0000_0013;
            memory[i + 3 + k*6 + 2] = 32'h0000_0013;
            memory[i + 3 + k*6 + 3] = enc_addi(5'd2, 5'd2, 12'd4);
            memory[i + 3 + k*6 + 4] = 32'h0000_0013;
            memory[i + 3 + k*6 + 5] = 32'h0000_0013;
        end
        memory[i + 3 + REQUESTS*6] = enc_addi(5'd5, 5'd0, 12'h5a5);
        memory[i + 4 + REQUESTS*6] = 32'h0000_006f; // completion loop

        for (i = 0; i < REQUESTS; i = i + 1)
            memory[(DATA_ADDR >> 2) + i] = i;

        repeat (8) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        while (!program_done && cycles < 100000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        repeat (4) @(posedge clk);

        if (!program_done) begin
            $display("DCACHE_1000_TIMEOUT pc=%08x instr=%08x instr_valid=%0b mem_req=%0b mem_re=%0b mem_addr=%08x ic_state=%0d dc_state=%0d accesses=%0d",
                     dut.PCF, dut.InstrF, dut.Instr_ValidF,
                     dut.physical_core.mem_req_core,
                     dut.Mem_ReadEnM, dut.Mem_AddrM,
                     dut.u_icache.state, dut.u_dcache.state,
                     dut.u_dcache.perf_cpu_accesses);
        end

        check_true(program_done,
                   "CPU completed the 1000-request workload");
        check_true(final_word_seen,
                   "CPU observed the final sequential data word (999)");
        check_true(dut.u_dcache.perf_cpu_accesses == REQUESTS,
                   "D-cache counted exactly 1000 cacheable CPU accesses");
        check_true(dut.u_dcache.perf_l1_hits == EXPECTED_HITS,
                   "Sequential workload produced 875 L1 hits");
        check_true(dut.u_dcache.perf_l1_misses == EXPECTED_MISSES,
                   "Sequential workload produced 125 L1 misses");
        check_true(dut.u_dcache.perf_l1_read_misses == EXPECTED_MISSES,
                   "All 125 misses were read misses");
        check_true(dut.u_dcache.perf_l1_write_misses == 0,
                   "Read-only workload produced no write misses");
        check_true(dut.u_dcache.perf_uncached_accesses == 0,
                   "Workload produced no uncached accesses");
        check_true(dut.u_dcache.perf_cpu_accesses ==
                   (dut.u_dcache.perf_l1_hits + dut.u_dcache.perf_l1_misses),
                   "accesses equals hits plus misses");
        check_true(d_line_reads == EXPECTED_MISSES,
                   "Observed line fills equal the D-cache miss count");
        check_true(!fetch_page_fault && !data_page_fault,
                   "Physical workload produced no page faults");

        if (dut.u_dcache.perf_cpu_accesses != 0)
            miss_rate_bp = (dut.u_dcache.perf_l1_misses * 10000) /
                           dut.u_dcache.perf_cpu_accesses;
        $display("DCACHE_1000_STATS accesses=%0d hits=%0d misses=%0d miss_rate=%0d.%02d%% cycles=%0d",
                 dut.u_dcache.perf_cpu_accesses,
                 dut.u_dcache.perf_l1_hits,
                 dut.u_dcache.perf_l1_misses,
                 miss_rate_bp / 100, miss_rate_bp % 100, cycles);

        if (errors == 0)
            $display("DCACHE_1000_CPU_REQUESTS_TB: PASS");
        else
            $display("DCACHE_1000_CPU_REQUESTS_TB: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 120000);
        $display("DCACHE_1000_CPU_REQUESTS_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
