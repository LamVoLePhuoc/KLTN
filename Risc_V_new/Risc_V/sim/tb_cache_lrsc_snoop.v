`timescale 1ns / 1ps

// LR/SC failure-path integration test.  A coherence invalidate arrives after
// LR establishes its physical reservation but before SC reaches M.  SC must
// return 1 without issuing an RFO or modifying the cached word.
module tb_cache_lrsc_snoop;
    localparam CLK_PERIOD = 10;

    reg clk, rst;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    wire [31:0] result_w, alu_debug;
    wire fetch_pf, data_pf;
    wire [1:0] fetch_cause, data_cause;
    wire ibus_req_valid;
    wire [31:0] ibus_req_addr;
    reg ibus_resp_valid;
    reg [255:0] ibus_resp_line;
    wire dbus_req_valid;
    wire [1:0] dbus_req_type;
    wire [31:0] dbus_req_addr;
    wire [255:0] dbus_req_line;
    reg dbus_resp_valid;
    reg [255:0] dbus_resp_line;
    reg [1:0] dbus_resp_state;

    reg snoop_valid;
    reg snoop_type;
    reg [31:0] snoop_addr;
    wire snoop_ack_valid, snoop_ack_hit, snoop_ack_dirty;
    wire [255:0] snoop_ack_line;

    core_l1_wrapper #(
        .RESET_ADDR(32'h0000_1000),
        .MMU_REGION_POLICY_ENABLE(0)
    ) dut (
        .clk(clk), .rst(rst), .Mmu_Flush(1'b0), .Cache_Flush(1'b0),
        .ResultW(result_w), .ALU_ResultE_Debug(alu_debug),
        .Fetch_PageFault(fetch_pf), .Data_PageFault(data_pf),
        .Fetch_PageFault_Cause(fetch_cause), .Data_PageFault_Cause(data_cause),
        .ibus_req_valid(ibus_req_valid), .ibus_req_addr(ibus_req_addr),
        .ibus_resp_valid(ibus_resp_valid), .ibus_resp_error(1'b0), .ibus_resp_line(ibus_resp_line),
        .dbus_req_valid(dbus_req_valid), .dbus_req_type(dbus_req_type),
        .dbus_req_addr(dbus_req_addr), .dbus_req_line(dbus_req_line),
        .dbus_resp_valid(dbus_resp_valid), .dbus_resp_error(1'b0), .dbus_resp_line(dbus_resp_line),
        .dbus_resp_state(dbus_resp_state),
        .dsnoop_valid(snoop_valid), .dsnoop_type(snoop_type), .dsnoop_addr(snoop_addr),
        .dsnoop_ack_valid(snoop_ack_valid), .dsnoop_ack_hit(snoop_ack_hit),
        .dsnoop_ack_dirty(snoop_ack_dirty), .dsnoop_ack_line(snoop_ack_line)
    );

    reg prev_ibus_req;
    reg prev_dbus_req;
    reg snoop_injected;
    integer busrd_count;
    integer rfo_count;
    integer unexpected_dreq_count;

    // First line ends with SC so the two NOPs leave enough room to inject the
    // invalidate after LR retirement.  The next line verifies memory stayed 33.
    always @(posedge clk) begin
        if (rst) begin
            prev_ibus_req          <= 1'b0;
            prev_dbus_req          <= 1'b0;
            ibus_resp_valid        <= 1'b0;
            dbus_resp_valid        <= 1'b0;
            ibus_resp_line         <= 256'b0;
            dbus_resp_line         <= 256'b0;
            dbus_resp_state        <= 2'b01;
            snoop_valid            <= 1'b0;
            snoop_type             <= 1'b0;
            snoop_addr             <= 32'h0000_4000;
            snoop_injected         <= 1'b0;
            busrd_count            <= 0;
            rfo_count              <= 0;
            unexpected_dreq_count  <= 0;
        end
        else begin
            ibus_resp_valid <= 1'b0;
            dbus_resp_valid <= 1'b0;
            snoop_valid     <= 1'b0;

            if (ibus_req_valid && !prev_ibus_req) begin
                if (ibus_req_addr == 32'h0000_1000) begin
                    ibus_resp_line <= {
                        32'h1820_a32f, // sc.w x6, x2, (x1)
                        32'h0000_0013,
                        32'h0000_0013,
                        32'h1000_a2af, // lr.w x5, (x1)
                        32'h0000_0013,
                        32'h0000_0013,
                        32'h0090_0113, // addi x2, x0, 9
                        32'h0000_40b7  // lui x1, 0x4
                    };
                end
                else if (ibus_req_addr == 32'h0000_1020) begin
                    ibus_resp_line <= {
                        32'h0000_0013, 32'h0000_0013,
                        32'h0000_0013, 32'h0000_0013,
                        32'h0000_0013, 32'h0000_0013,
                        32'h0000_006f, // jal x0, 0
                        32'h0000_a383  // lw x7, 0(x1)
                    };
                end
                else begin
                    ibus_resp_line <= {8{32'h0000_006f}};
                end
                ibus_resp_valid <= 1'b1;
            end

            if (dbus_req_valid && !prev_dbus_req) begin
                dbus_resp_line       <= 256'b0;
                dbus_resp_line[31:0] <= 32'd33;
                dbus_resp_state      <= (dbus_req_type == 2'b01) ? 2'b11 : 2'b01;
                dbus_resp_valid      <= 1'b1;
                if ((dbus_req_addr == 32'h0000_4000) && (dbus_req_type == 2'b00))
                    busrd_count <= busrd_count + 1;
                else if ((dbus_req_addr == 32'h0000_4000) && (dbus_req_type == 2'b01))
                    rfo_count <= rfo_count + 1;
                else
                    unexpected_dreq_count <= unexpected_dreq_count + 1;
            end

            // reservation_valid is internal architectural state.  Using it as
            // the injection trigger makes this test independent of cache latency.
            if (!snoop_injected && dut.mmu_core.core.memory_unit.reservation_valid) begin
                snoop_valid    <= 1'b1;
                snoop_type     <= 1'b0;
                snoop_addr     <= 32'h0000_4000;
                snoop_injected <= 1'b1;
            end

            prev_ibus_req <= ibus_req_valid;
            prev_dbus_req <= dbus_req_valid;
        end
    end

    reg saw_lr_value;
    reg saw_sc_failure;
    reg saw_original_value;
    integer errors;
    integer cycles;

    always @(posedge clk) begin
        if (rst) begin
            saw_lr_value       <= 1'b0;
            saw_sc_failure     <= 1'b0;
            saw_original_value <= 1'b0;
        end
        else if (dut.mmu_core.core.RegWriteW) begin
            if ((dut.mmu_core.core.RD_W == 5'd5) && (result_w == 32'd33))
                saw_lr_value <= 1'b1;
            if ((dut.mmu_core.core.RD_W == 5'd6) && (result_w == 32'd1))
                saw_sc_failure <= 1'b1;
            if ((dut.mmu_core.core.RD_W == 5'd7) && (result_w == 32'd33))
                saw_original_value <= 1'b1;
        end
    end

    initial begin
        saw_lr_value = 1'b0;
        saw_sc_failure = 1'b0;
        saw_original_value = 1'b0;
        errors = 0;
        cycles = 0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        while (!(saw_lr_value && saw_sc_failure && saw_original_value) && cycles < 350) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!saw_lr_value) begin
            $display("[FAIL] LR.W did not establish the pre-invalidate value");
            errors = errors + 1;
        end
        else
            $display("[PASS] LR.W returned 33 before the invalidate");

        if (!snoop_injected || !saw_sc_failure) begin
            $display("[FAIL] invalidate did not force SC.W to return failure");
            errors = errors + 1;
        end
        else
            $display("[PASS] coherence invalidate cleared reservation; SC.W returned 1");

        if (!saw_original_value) begin
            $display("[FAIL] failed SC.W changed the memory value");
            errors = errors + 1;
        end
        else
            $display("[PASS] failed SC.W issued no store; following LW still read 33");

        if ((busrd_count != 2) || (rfo_count != 0)) begin
            $display("[FAIL] failure-path traffic BusRd=%0d RFO=%0d, expected 2/0",
                     busrd_count, rfo_count);
            errors = errors + 1;
        end
        else
            $display("[PASS] invalidated line refetched twice and failed SC emitted no RFO");

        if (unexpected_dreq_count != 0) begin
            $display("[FAIL] observed %0d unexpected D$ request(s)", unexpected_dreq_count);
            errors = errors + 1;
        end

        if (fetch_pf || data_pf) begin
            $display("[FAIL] LR/SC invalidate program raised an unexpected page fault");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("CACHE_LRSC_SNOOP_TB: PASS");
        else
            $display("CACHE_LRSC_SNOOP_TB: FAIL (%0d check(s) failed)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 600);
        $display("CACHE_LRSC_SNOOP_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
