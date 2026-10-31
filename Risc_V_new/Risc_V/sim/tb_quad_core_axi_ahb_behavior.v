`timescale 1ns / 1ps

// TC-AXI-SYS-001..007 | Board-facing behavior gate
//
// Instantiates the exact module-reference top used by soc_4core_trial.bd:
// quad_core_axi_wrapper_ahb.  Four real cores execute from four physical boot
// addresses through L1/AHB/cache-controller/L2 and a backpressured AXI memory
// model.  This is a behavioral pre-bitstream gate, not a timing simulation.
module tb_quad_core_axi_ahb_behavior;
    localparam CLK_PERIOD = 10;
    localparam MEM_WORDS  = 16384;
    localparam BOOT0      = 32'h0000_1000;
    localparam BOOT1      = 32'h0000_2000;
    localparam BOOT2      = 32'h0000_3000;
    localparam BOOT3      = 32'h0000_4000;
    localparam DATA_BASE  = 32'h0000_9000;

    reg clk;
    reg resetn;
    reg mmu_flush;
    reg cache_flush;
    wire cache_flush_busy, cache_flush_done, cache_flush_error;
    wire [31:0] result_w0, result_w1, result_w2, result_w3;
    wire fetch_pf0, fetch_pf1, fetch_pf2, fetch_pf3;
    wire data_pf0, data_pf1, data_pf2, data_pf3;

    wire [31:0] awaddr, wdata, araddr;
    wire [3:0]  wstrb;
    wire awvalid, wvalid, bready, arvalid, rready;
    wire awready, wready, arready;
    reg [1:0] bresp, rresp;
    reg bvalid, rvalid;
    reg [31:0] rdata;

    reg [31:0] memory [0:MEM_WORDS-1];
    integer i;
    integer errors;
    integer cycles;
    integer axi_reads;
    integer axi_writes;
    reg [3:0] core_done_seen;

    reg        read_pending;
    reg [31:0] read_addr;
    integer    read_delay;
    reg        aw_captured;
    reg [31:0] write_addr;
    reg        w_captured;
    reg [31:0] write_data;
    reg [3:0]  write_strb;
    integer    write_delay;

    reg        ar_waiting;
    reg [31:0] held_araddr;
    reg        aw_waiting;
    reg [31:0] held_awaddr;
    reg        w_waiting;
    reg [31:0] held_wdata;
    reg [3:0]  held_wstrb;

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
            memory[w + 1] = enc_lui(5'd2, 20'h00009);
            memory[w + 2] = enc_addi(5'd2, 5'd2, byte_offset);
            memory[w + 3] = enc_sw(5'd1, 5'd2, 12'd0);
            memory[w + 4] = enc_lw(5'd3, 5'd2, 12'd0);
            memory[w + 5] = 32'h0000_0013; // load-use bubble
            memory[w + 6] = enc_addi(5'd5, 5'd3, 12'h100);
            memory[w + 7] = 32'h0000_006f;
        end
    endtask

    task check_true;
        input condition;
        input [8*100-1:0] label_text;
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
        input [8*100-1:0] label_text;
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

    quad_core_axi_wrapper_ahb #(
        .RESET_ADDR0(BOOT0), .RESET_ADDR1(BOOT1),
        .RESET_ADDR2(BOOT2), .RESET_ADDR3(BOOT3)
    ) dut (
        .ACLK(clk), .ARESETN(resetn),
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
        .M_AXI_AWADDR(awaddr), .M_AXI_AWVALID(awvalid),
        .M_AXI_AWREADY(awready), .M_AXI_WDATA(wdata),
        .M_AXI_WSTRB(wstrb), .M_AXI_WVALID(wvalid), .M_AXI_WREADY(wready),
        .M_AXI_BRESP(bresp), .M_AXI_BVALID(bvalid), .M_AXI_BREADY(bready),
        .M_AXI_ARADDR(araddr), .M_AXI_ARVALID(arvalid),
        .M_AXI_ARREADY(arready), .M_AXI_RDATA(rdata),
        .M_AXI_RRESP(rresp), .M_AXI_RVALID(rvalid), .M_AXI_RREADY(rready)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Deterministic READY throttling exercises the wrapper's requirement to
    // retain VALID and payload until each independent AXI handshake.
    assign arready = resetn && !read_pending && !rvalid && (cycles[1:0] != 2'b00);
    assign awready = resetn && !aw_captured && !bvalid && cycles[0];
    assign wready  = resetn && !w_captured && !bvalid && cycles[1];

    always @(posedge clk) begin
        if (!resetn) begin
            cycles       <= 0;
            read_pending <= 1'b0;
            read_addr    <= 32'b0;
            read_delay   <= 0;
            rvalid       <= 1'b0;
            rdata        <= 32'b0;
            rresp        <= 2'b00;
            aw_captured  <= 1'b0;
            write_addr   <= 32'b0;
            w_captured   <= 1'b0;
            write_data   <= 32'b0;
            write_strb   <= 4'b0;
            write_delay  <= -1;
            bvalid       <= 1'b0;
            bresp        <= 2'b00;
            axi_reads    <= 0;
            axi_writes   <= 0;
            ar_waiting   <= 1'b0;
            aw_waiting   <= 1'b0;
            w_waiting    <= 1'b0;
        end
        else begin
            cycles <= cycles + 1;

            if (ar_waiting && !arvalid) begin
                errors = errors + 1;
                $display("[FAIL] TC-AXI-SYS-002 ARVALID dropped before ARREADY");
                ar_waiting <= 1'b0;
            end
            else if (arvalid && !arready) begin
                if (ar_waiting && araddr !== held_araddr) begin
                    errors = errors + 1;
                    $display("[FAIL] TC-AXI-SYS-002 ARADDR changed under backpressure");
                end
                ar_waiting <= 1'b1;
                held_araddr <= araddr;
            end
            else if (arvalid && arready)
                ar_waiting <= 1'b0;

            if (aw_waiting && !awvalid) begin
                errors = errors + 1;
                $display("[FAIL] TC-AXI-SYS-002 AWVALID dropped before AWREADY t=%0t held_addr=%08x current_addr=%08x req_pending=%b req_we=%b aw_done=%b bvalid=%b bready=%b",
                         $time, held_awaddr, awaddr, dut.req_pending,
                         dut.req_we, dut.aw_done, bvalid, bready);
                aw_waiting <= 1'b0;
            end
            else if (awvalid && !awready) begin
                if (aw_waiting && awaddr !== held_awaddr) begin
                    errors = errors + 1;
                    $display("[FAIL] TC-AXI-SYS-002 AWADDR changed under backpressure");
                end
                aw_waiting <= 1'b1;
                held_awaddr <= awaddr;
            end
            else if (awvalid && awready)
                aw_waiting <= 1'b0;

            if (w_waiting && !wvalid) begin
                errors = errors + 1;
                $display("[FAIL] TC-AXI-SYS-002 WVALID dropped before WREADY");
                w_waiting <= 1'b0;
            end
            else if (wvalid && !wready) begin
                if (w_waiting && ((wdata !== held_wdata) ||
                                  (wstrb !== held_wstrb))) begin
                    errors = errors + 1;
                    $display("[FAIL] TC-AXI-SYS-002 W payload changed under backpressure");
                end
                w_waiting <= 1'b1;
                held_wdata <= wdata;
                held_wstrb <= wstrb;
            end
            else if (wvalid && wready)
                w_waiting <= 1'b0;

            if (arvalid && arready) begin
                read_pending <= 1'b1;
                read_addr    <= araddr;
                read_delay   <= 2;
                axi_reads    <= axi_reads + 1;
            end
            else if (read_pending && read_delay > 0)
                read_delay <= read_delay - 1;
            else if (read_pending && !rvalid) begin
                rdata  <= (read_addr[31:16] == 16'b0) ?
                          memory[read_addr[15:2]] : 32'b0;
                rresp  <= (read_addr[31:16] == 16'b0) ? 2'b00 : 2'b10;
                rvalid <= 1'b1;
                read_pending <= 1'b0;
            end
            if (rvalid && rready)
                rvalid <= 1'b0;

            if (awvalid && awready) begin
                aw_captured <= 1'b1;
                write_addr  <= awaddr;
            end
            if (wvalid && wready) begin
                w_captured <= 1'b1;
                write_data <= wdata;
                write_strb <= wstrb;
            end
            if (aw_captured && w_captured && (write_delay < 0))
                write_delay <= 2;
            else if (write_delay > 0)
                write_delay <= write_delay - 1;
            else if ((write_delay == 0) && !bvalid) begin
                if (write_addr[31:16] == 16'b0) begin
                    if (write_strb[0]) memory[write_addr[15:2]][7:0]   <= write_data[7:0];
                    if (write_strb[1]) memory[write_addr[15:2]][15:8]  <= write_data[15:8];
                    if (write_strb[2]) memory[write_addr[15:2]][23:16] <= write_data[23:16];
                    if (write_strb[3]) memory[write_addr[15:2]][31:24] <= write_data[31:24];
                    bresp <= 2'b00;
                end
                else
                    bresp <= 2'b10;
                bvalid <= 1'b1;
                write_delay <= -1;
                axi_writes <= axi_writes + 1;
            end
            if (bvalid && bready) begin
                bvalid <= 1'b0;
                aw_captured <= 1'b0;
                w_captured <= 1'b0;
                // Do not restart the response delay from the old captured
                // flags on the B-handshake edge.  All conditions above see
                // pre-edge values, so without this final-priority assignment
                // the first if-clause can schedule a spurious second BVALID.
                write_delay <= -1;
            end

            if (result_w0 == 32'h0000_0255) core_done_seen[0] <= 1'b1;
            if (result_w1 == 32'h0000_0366) core_done_seen[1] <= 1'b1;
            if (result_w2 == 32'h0000_0477) core_done_seen[2] <= 1'b1;
            if (result_w3 == 32'h0000_0588) core_done_seen[3] <= 1'b1;

            if ({fetch_pf3, fetch_pf2, fetch_pf1, fetch_pf0} != 4'b0 ||
                {data_pf3, data_pf2, data_pf1, data_pf0} != 4'b0) begin
                errors = errors + 1;
                $display("[FAIL] page-fault output asserted in physical-only AXI system");
            end
        end
    end

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        mmu_flush = 1'b0;
        cache_flush = 1'b0;
        errors = 0;
        cycles = 0;
        core_done_seen = 4'b0;

        for (i = 0; i < MEM_WORDS; i = i + 1)
            memory[i] = 32'h0000_0013;
        load_program(BOOT0, 12'h155, 12'd0);
        load_program(BOOT1, 12'h266, 12'd4);
        load_program(BOOT2, 12'h377, 12'd8);
        load_program(BOOT3, 12'h488, 12'd12);
        memory[DATA_BASE[15:2] + 0] = 32'h0;
        memory[DATA_BASE[15:2] + 1] = 32'h0;
        memory[DATA_BASE[15:2] + 2] = 32'h0;
        memory[DATA_BASE[15:2] + 3] = 32'h0;

        repeat (8) @(posedge clk);
        @(negedge clk); resetn = 1'b1;

        while ((core_done_seen != 4'b1111) && (cycles < 40000))
            @(posedge clk);
        check_true(core_done_seen == 4'b1111,
                   "TC-AXI-SYS-001 four cores execute through the board AXI boundary");
        check_true(axi_reads > 0,
                   "TC-AXI-SYS-002 AXI read traffic completed under backpressure");

        repeat (8) @(posedge clk);
        @(negedge clk); mmu_flush = 1'b1;
        repeat (2) @(negedge clk);
        mmu_flush = 1'b0;
        repeat (12) @(posedge clk);
        check_true(!cache_flush_busy && !cache_flush_done,
                   "TC-AXI-SYS-003 deprecated Mmu_Flush is a board-level no-op");
        check_true({fetch_pf3, fetch_pf2, fetch_pf1, fetch_pf0,
                    data_pf3, data_pf2, data_pf1, data_pf0} == 8'b0,
                   "TC-AXI-SYS-004 Mmu_Flush causes no translation exception");

        @(negedge clk); cache_flush = 1'b1;
        @(negedge clk); cache_flush = 1'b0;
        while (!cache_flush_done && (cycles < 85000))
            @(posedge clk);
        check_true(cache_flush_done && !cache_flush_error,
                   "TC-AXI-SYS-005 cache maintenance completes through AXI");
        repeat (3) @(posedge clk);
        check_true(axi_writes > 0,
                   "TC-AXI-SYS-005 dirty cache data used AXI write channel");

        check_word(DATA_BASE + 32'd0, 32'h0000_0155,
                   "TC-AXI-SYS-006 core0 coherent signature reached AXI memory");
        check_word(DATA_BASE + 32'd4, 32'h0000_0266,
                   "TC-AXI-SYS-006 core1 coherent signature reached AXI memory");
        check_word(DATA_BASE + 32'd8, 32'h0000_0377,
                   "TC-AXI-SYS-006 core2 coherent signature reached AXI memory");
        check_word(DATA_BASE + 32'd12, 32'h0000_0488,
                   "TC-AXI-SYS-006 core3 coherent signature reached AXI memory");
        check_true({fetch_pf3, fetch_pf2, fetch_pf1, fetch_pf0,
                    data_pf3, data_pf2, data_pf1, data_pf0} == 8'b0,
                   "TC-AXI-SYS-007 no page faults exist after translation removal");

        if (errors == 0)
            $display("QUAD_CORE_AXI_AHB_BEHAVIOR_TB: PASS");
        else
            $display("QUAD_CORE_AXI_AHB_BEHAVIOR_TB: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 110000);
        $display("QUAD_CORE_AXI_AHB_BEHAVIOR_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
