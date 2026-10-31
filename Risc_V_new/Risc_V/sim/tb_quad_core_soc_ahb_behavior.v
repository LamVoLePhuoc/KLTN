`timescale 1ns / 1ps

// TC-SOC-001..006 | Active physical-address/cache-controller architecture
//
// Full four-core behavioral test for the active AHB subsystem.  This is above
// the block-level cache tests: four real RV32IMA pipelines, private L1 I$/D$,
// eight point-to-point AHB-Lite links, the shared cache controller and L2 are
// all instantiated.  The external CPU memory port is the only testbench model.
//
// Expected behavior comes from the active architecture contract:
//   * RESET_ADDR0..3 are physical fetch addresses.
//   * Mmu_Flush is a deprecated no-op after removal of VA/PA translation.
//   * four stores to different words of one cache line must survive ownership
//     transfers and become visible in memory after Cache_Flush completes.
//   * page-fault outputs are permanently low in the physical-address design.
module tb_quad_core_soc_ahb_behavior;
    localparam CLK_PERIOD = 10;
    localparam MEM_WORDS  = 16384;
    localparam BOOT0      = 32'h0000_1000;
    localparam BOOT1      = 32'h0000_2000;
    localparam BOOT2      = 32'h0000_3000;
    localparam BOOT3      = 32'h0000_4000;
    localparam DATA_BASE  = 32'h0000_8000;

    reg clk;
    reg rst;
    reg mmu_flush;
    reg cache_flush;

    wire cache_flush_busy;
    wire cache_flush_done;
    wire cache_flush_error;
    wire [31:0] result_w0, result_w1, result_w2, result_w3;
    wire fetch_pf0, fetch_pf1, fetch_pf2, fetch_pf3;
    wire data_pf0, data_pf1, data_pf2, data_pf3;

    wire        mem_req_valid;
    wire        mem_we;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    reg  [31:0] mem_rdata;
    reg         mem_valid;
    reg         mem_error;

    reg [31:0] memory [0:MEM_WORDS-1];
    integer i;
    integer errors;
    integer cycles;
    integer memory_requests;
    reg [3:0] core_done_seen;

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

    function [31:0] enc_sw;
        input [4:0] rs2;
        input [4:0] rs1;
        input [11:0] imm;
        begin enc_sw = {imm[11:5], rs2, rs1, 3'b010,
                        imm[4:0], 7'b0100011}; end
    endfunction

    function [31:0] enc_lw;
        input [4:0] rd;
        input [4:0] rs1;
        input [11:0] imm;
        begin enc_lw = {imm, rs1, 3'b010, rd, 7'b0000011}; end
    endfunction

    task load_program;
        input [31:0] base;
        input [11:0] signature;
        input [11:0] byte_offset;
        integer w;
        begin
            w = base >> 2;
            memory[w + 0] = enc_addi(5'd1, 5'd0, signature);
            memory[w + 1] = enc_lui(5'd2, 20'h00008);
            memory[w + 2] = enc_addi(5'd2, 5'd2, byte_offset);
            memory[w + 3] = enc_sw(5'd1, 5'd2, 12'd0);
            memory[w + 4] = enc_lw(5'd3, 5'd2, 12'd0);
            // Derive completion from the loaded value so a marker cannot be
            // reached successfully through a broken D-cache data path.
            memory[w + 5] = 32'h0000_0013; // load-use bubble
            memory[w + 6] = enc_addi(5'd5, 5'd3, 12'h100);
            memory[w + 7] = 32'h0000_006f; // jal x0, 0
        end
    endtask

    task check_true;
        input condition;
        input [8*96-1:0] label_text;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[FAIL] %0s", label_text);
            end
            else
                $display("[PASS] %0s", label_text);
        end
    endtask

    task check_word;
        input [31:0] address;
        input [31:0] expected;
        input [8*96-1:0] label_text;
        begin
            if (memory[address[15:2]] !== expected) begin
                errors = errors + 1;
                $display("[FAIL] %0s got=%08x expected=%08x",
                         label_text, memory[address[15:2]], expected);
            end
            else
                $display("[PASS] %0s = %08x", label_text, expected);
        end
    endtask

    quad_core_soc_ahb #(
        .RESET_ADDR0(BOOT0), .RESET_ADDR1(BOOT1),
        .RESET_ADDR2(BOOT2), .RESET_ADDR3(BOOT3)
    ) dut (
        .clk(clk), .rst(rst),
        .Mmu_Flush(mmu_flush), .Cache_Flush(cache_flush),
        .Cache_Flush_Busy(cache_flush_busy),
        .Cache_Flush_Done(cache_flush_done),
        .Cache_Flush_Error(cache_flush_error),
        .ResultW0(result_w0), .ResultW1(result_w1),
        .ResultW2(result_w2), .ResultW3(result_w3),
        .Fetch_PageFault0(fetch_pf0), .Fetch_PageFault1(fetch_pf1),
        .Fetch_PageFault2(fetch_pf2), .Fetch_PageFault3(fetch_pf3),
        .Data_PageFault0(data_pf0), .Data_PageFault1(data_pf1),
        .Data_PageFault2(data_pf2), .Data_PageFault3(data_pf3),
        .mem_req_valid(mem_req_valid), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata), .mem_valid(mem_valid), .mem_error(mem_error)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // One-cycle, single-word physical memory model.  Byte strobes are honored
    // so this model is also valid for the uncached/MMIO sideband contract.
    always @(posedge clk) begin
        mem_valid <= 1'b0;
        mem_error <= 1'b0;
        if (!rst && mem_req_valid) begin
            memory_requests <= memory_requests + 1;
            if (mem_addr[31:16] != 16'b0) begin
                mem_error <= 1'b1;
                mem_rdata <= 32'b0;
            end
            else if (mem_we) begin
                if (mem_wstrb[0]) memory[mem_addr[15:2]][7:0]   <= mem_wdata[7:0];
                if (mem_wstrb[1]) memory[mem_addr[15:2]][15:8]  <= mem_wdata[15:8];
                if (mem_wstrb[2]) memory[mem_addr[15:2]][23:16] <= mem_wdata[23:16];
                if (mem_wstrb[3]) memory[mem_addr[15:2]][31:24] <= mem_wdata[31:24];
            end
            else begin
                mem_rdata <= memory[mem_addr[15:2]];
            end
            mem_valid <= 1'b1;
        end
    end

    // Interface-level monitors.  These checks do not depend on internal state
    // encodings and remain valid if cache/controller implementation changes.
    always @(posedge clk) begin
        if (!rst) begin
            if (result_w0 == 32'h0000_0211) core_done_seen[0] <= 1'b1;
            if (result_w1 == 32'h0000_0322) core_done_seen[1] <= 1'b1;
            if (result_w2 == 32'h0000_0433) core_done_seen[2] <= 1'b1;
            if (result_w3 == 32'h0000_0544) core_done_seen[3] <= 1'b1;
            if ({fetch_pf3, fetch_pf2, fetch_pf1, fetch_pf0} != 4'b0 ||
                {data_pf3, data_pf2, data_pf1, data_pf0} != 4'b0) begin
                errors = errors + 1;
                $display("[FAIL] page-fault output asserted in physical-only design");
            end
        end
    end

`ifdef COHERENCE_TRACE
    always @(posedge clk) begin
        if (!rst) begin
            if (dut.l2_cmd_valid && dut.l2_cmd_we &&
                (dut.l2_cmd_addr[31:5] == DATA_BASE[31:5]))
                $display("[TRACE L2] t=%0t addr=%08x dirty=%b sharers=%b words=%08x %08x %08x %08x",
                         $time, dut.l2_cmd_addr, dut.l2_cmd_w_dirty,
                         dut.l2_cmd_w_sharers, dut.l2_cmd_wdata[31:0],
                         dut.l2_cmd_wdata[63:32], dut.l2_cmd_wdata[95:64],
                         dut.l2_cmd_wdata[127:96]);
            if (dut.dsnoop_ack_valid[0])
                $display("[TRACE S0] t=%0t hit=%b dirty=%b words=%08x %08x %08x %08x",
                         $time, dut.dsnoop_ack_hit[0], dut.dsnoop_ack_dirty[0],
                         dut.dsnoop_ack_line[0][31:0], dut.dsnoop_ack_line[0][63:32],
                         dut.dsnoop_ack_line[0][95:64], dut.dsnoop_ack_line[0][127:96]);
            if (dut.dsnoop_ack_valid[1])
                $display("[TRACE S1] t=%0t hit=%b dirty=%b words=%08x %08x %08x %08x",
                         $time, dut.dsnoop_ack_hit[1], dut.dsnoop_ack_dirty[1],
                         dut.dsnoop_ack_line[1][31:0], dut.dsnoop_ack_line[1][63:32],
                         dut.dsnoop_ack_line[1][95:64], dut.dsnoop_ack_line[1][127:96]);
            if (dut.dsnoop_ack_valid[2])
                $display("[TRACE S2] t=%0t hit=%b dirty=%b words=%08x %08x %08x %08x",
                         $time, dut.dsnoop_ack_hit[2], dut.dsnoop_ack_dirty[2],
                         dut.dsnoop_ack_line[2][31:0], dut.dsnoop_ack_line[2][63:32],
                         dut.dsnoop_ack_line[2][95:64], dut.dsnoop_ack_line[2][127:96]);
            if (dut.dsnoop_ack_valid[3])
                $display("[TRACE S3] t=%0t hit=%b dirty=%b words=%08x %08x %08x %08x",
                         $time, dut.dsnoop_ack_hit[3], dut.dsnoop_ack_dirty[3],
                         dut.dsnoop_ack_line[3][31:0], dut.dsnoop_ack_line[3][63:32],
                         dut.dsnoop_ack_line[3][95:64], dut.dsnoop_ack_line[3][127:96]);
        end
    end
`endif

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        mmu_flush = 1'b0;
        cache_flush = 1'b0;
        mem_rdata = 32'b0;
        mem_valid = 1'b0;
        mem_error = 1'b0;
        errors = 0;
        cycles = 0;
        memory_requests = 0;
        core_done_seen = 4'b0;

        for (i = 0; i < MEM_WORDS; i = i + 1)
            memory[i] = 32'h0000_0013;

        // All cores deliberately modify different words of the same line.
        load_program(BOOT0, 12'h111, 12'd0);
        load_program(BOOT1, 12'h222, 12'd4);
        load_program(BOOT2, 12'h333, 12'd8);
        load_program(BOOT3, 12'h444, 12'd12);
        memory[DATA_BASE[15:2] + 0] = 32'h0;
        memory[DATA_BASE[15:2] + 1] = 32'h0;
        memory[DATA_BASE[15:2] + 2] = 32'h0;
        memory[DATA_BASE[15:2] + 3] = 32'h0;

        repeat (8) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while ((core_done_seen != 4'b1111) && (cycles < 30000)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        check_true(core_done_seen == 4'b1111,
                   "TC-SOC-001 all four physical-address programs completed");

        // The compatibility pin must not launch maintenance or memory traffic.
        // At this point every core is looping from its hot I$ line.
        repeat (8) @(posedge clk);
        @(negedge clk); mmu_flush = 1'b1;
        repeat (2) @(negedge clk);
        mmu_flush = 1'b0;
        repeat (12) @(posedge clk);
        check_true(!cache_flush_busy && !cache_flush_done,
                   "TC-SOC-002 deprecated Mmu_Flush is a no-op");
        check_true({fetch_pf3, fetch_pf2, fetch_pf1, fetch_pf0,
                    data_pf3, data_pf2, data_pf1, data_pf0} == 8'b0,
                   "TC-SOC-003 Mmu_Flush causes no translation exception");

        // Clean/invalidate all private caches, making the final dirty owner
        // write the shared line back to the external memory model.
        @(negedge clk); cache_flush = 1'b1;
        @(negedge clk); cache_flush = 1'b0;
        cycles = 0;
        // The timing-closed L2 uses a three-stage lookup/maintenance path.
        // A full 4-way x 4096-set scan therefore needs at least 65,536
        // clocks, plus the private-L1 drain and dirty-line writeback.
        while (!cache_flush_done && (cycles < 75000)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        check_true(cache_flush_done && !cache_flush_error,
                   "TC-SOC-004 aggregate cache maintenance completes without error");
        @(posedge clk);

        check_word(DATA_BASE + 32'd0,  32'h0000_0111,
                   "TC-SOC-005 core0 word survived shared-line ownership transfers");
        check_word(DATA_BASE + 32'd4,  32'h0000_0222,
                   "TC-SOC-005 core1 word survived shared-line ownership transfers");
        check_word(DATA_BASE + 32'd8,  32'h0000_0333,
                   "TC-SOC-005 core2 word survived shared-line ownership transfers");
        check_word(DATA_BASE + 32'd12, 32'h0000_0444,
                   "TC-SOC-005 core3 word survived shared-line ownership transfers");
        check_true({fetch_pf3, fetch_pf2, fetch_pf1, fetch_pf0,
                    data_pf3, data_pf2, data_pf1, data_pf0} == 8'b0,
                   "TC-SOC-006 physical-only system reports no page faults");

        if (errors == 0)
            $display("QUAD_CORE_SOC_AHB_BEHAVIOR_TB: PASS");
        else
            $display("QUAD_CORE_SOC_AHB_BEHAVIOR_TB: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 110000);
        $display("QUAD_CORE_SOC_AHB_BEHAVIOR_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
