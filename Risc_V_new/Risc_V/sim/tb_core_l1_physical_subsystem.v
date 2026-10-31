`timescale 1ns / 1ps

// TC-L1-SUB-001..006 | One physical core + private L1 I$/D$ subsystem
//
// This closes the integration gap between the bare-core ISA test and the
// four-cache coherence test.  A real core_l1_wrapper executes a short program
// against a specification-level line-memory responder.  No TLB/PTW or virtual
// address model is present.
module tb_core_l1_physical_subsystem;
    localparam CLK_PERIOD = 10;
    localparam MEM_WORDS  = 16384;
    localparam BOOT_ADDR  = 32'h0000_1000;
    localparam DATA_ADDR  = 32'h0000_7000;

    reg clk;
    reg rst;
    reg mmu_flush;
    reg cache_flush;
    wire cache_flush_busy, cache_flush_done, cache_flush_error;
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

    wire dsnoop_ack_valid, dsnoop_ack_hit, dsnoop_ack_dirty;
    wire [255:0] dsnoop_ack_line;

    reg [31:0] memory [0:MEM_WORDS-1];
    reg i_request_seen;
    reg d_request_seen;
    integer transactions;
    integer errors;
    integer cycles;
    integer i;
    integer j;
    reg program_done;

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

    core_l1_wrapper #(
        .RESET_ADDR(BOOT_ADDR),
        .HART_ID(32'd0)
    ) dut (
        .clk(clk), .rst(rst),
        .Mmu_Flush(mmu_flush), .Cache_Flush(cache_flush),
        .Cache_Flush_Busy(cache_flush_busy),
        .Cache_Flush_Done(cache_flush_done),
        .Cache_Flush_Error(cache_flush_error),
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
        .dsnoop_ack_valid(dsnoop_ack_valid), .dsnoop_ack_hit(dsnoop_ack_hit),
        .dsnoop_ack_dirty(dsnoop_ack_dirty), .dsnoop_ack_line(dsnoop_ack_line)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Independent I$ and D$ responders. Each level-held request receives one
    // response. Line word 0 occupies bits [31:0], matching the cache contract.
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
            if (!ibus_req_valid)
                i_request_seen <= 1'b0;
            else if (!i_request_seen) begin
                i_request_seen <= 1'b1;
                transactions <= transactions + 1;
                for (j = 0; j < 8; j = j + 1)
                    ibus_resp_line[j*32 +: 32] <=
                        memory[(ibus_req_addr[15:2] & 14'h3ff8) + j];
                ibus_resp_valid <= 1'b1;
            end

            if (!dbus_req_valid)
                d_request_seen <= 1'b0;
            else if (!d_request_seen) begin
                d_request_seen <= 1'b1;
                transactions <= transactions + 1;
                if (dbus_req_type == 2'b10) begin
                    for (j = 0; j < 8; j = j + 1)
                        memory[(dbus_req_addr[15:2] & 14'h3ff8) + j] <=
                            dbus_req_line[j*32 +: 32];
                    dbus_resp_state <= 2'b00;
                end
                else begin
                    for (j = 0; j < 8; j = j + 1)
                        dbus_resp_line[j*32 +: 32] <=
                            memory[(dbus_req_addr[15:2] & 14'h3ff8) + j];
                    dbus_resp_state <= (dbus_req_type == 2'b01) ?
                                       2'b11 : 2'b01;
                end
                dbus_resp_valid <= 1'b1;
            end

            if (result_w == 32'h0000_05d5)
                program_done <= 1'b1;
            if (fetch_page_fault || data_page_fault) begin
                errors = errors + 1;
                $display("[FAIL] page-fault output asserted in physical L1 subsystem");
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        mmu_flush = 1'b0;
        cache_flush = 1'b0;
        ibus_resp_valid = 1'b0;
        ibus_resp_error = 1'b0;
        ibus_resp_line = 256'b0;
        dbus_resp_valid = 1'b0;
        dbus_resp_error = 1'b0;
        dbus_resp_line = 256'b0;
        dbus_resp_state = 2'b00;
        i_request_seen = 1'b0;
        d_request_seen = 1'b0;
        transactions = 0;
        errors = 0;
        cycles = 0;
        program_done = 1'b0;

        for (i = 0; i < MEM_WORDS; i = i + 1)
            memory[i] = 32'h0000_0013;
        i = BOOT_ADDR >> 2;
        memory[i + 0] = enc_addi(5'd1, 5'd0, 12'h2d5);
        memory[i + 1] = enc_lui(5'd2, 20'h00007);
        memory[i + 2] = enc_sw(5'd1, 5'd2, 12'd0);
        memory[i + 3] = enc_lw(5'd3, 5'd2, 12'd0);
        // Completion depends on the value returned by the preceding load;
        // this cannot pass if the store/load path is silently bypassed.
        memory[i + 4] = 32'h0000_0013; // load-use bubble
        memory[i + 5] = enc_addi(5'd5, 5'd3, 12'h300);
        memory[i + 6] = 32'h0000_006f;
        memory[DATA_ADDR[15:2]] = 32'b0;

        repeat (8) @(posedge clk);
        @(negedge clk); rst = 1'b0;

        while (!program_done && cycles < 12000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        check_true(program_done,
                   "TC-L1-SUB-001 core executes through private I$ and D$");

        @(negedge clk); mmu_flush = 1'b1;
        repeat (2) @(negedge clk);
        mmu_flush = 1'b0;
        repeat (12) @(posedge clk);
        check_true(!cache_flush_busy && !cache_flush_done,
                   "TC-L1-SUB-002 deprecated Mmu_Flush is a no-op");
        check_true(!fetch_page_fault && !data_page_fault,
                   "TC-L1-SUB-003 Mmu_Flush causes no translation exception");

        @(negedge clk); cache_flush = 1'b1;
        @(negedge clk); cache_flush = 1'b0;
        cycles = 0;
        while (!cache_flush_done && cycles < 12000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        check_true(cache_flush_done && !cache_flush_error,
                   "TC-L1-SUB-004 D$ clean then I$ invalidate completes");
        repeat (2) @(posedge clk);
        check_true(memory[DATA_ADDR[15:2]] == 32'h0000_02d5,
                   "TC-L1-SUB-005 dirty physical data reaches memory after flush");
        check_true(!fetch_page_fault && !data_page_fault,
                   "TC-L1-SUB-006 physical subsystem has no page faults");

        if (errors == 0)
            $display("CORE_L1_PHYSICAL_SUBSYSTEM_TB: PASS");
        else
            $display("CORE_L1_PHYSICAL_SUBSYSTEM_TB: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 30000);
        $display("CORE_L1_PHYSICAL_SUBSYSTEM_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
