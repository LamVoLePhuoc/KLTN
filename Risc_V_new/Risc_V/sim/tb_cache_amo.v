`timescale 1ns / 1ps

// End-to-end cached AMO test for one integrated core.  A real AMOADD.W
// instruction travels through RV32IMA and mmu_core_wrapper into l1_dcache.
// The target starts absent from D$, so the cache must obtain ownership,
// return the old word to rd, and commit the RMW result atomically on fill.
module tb_cache_amo;
    localparam CLK_PERIOD = 10;

    reg clk, rst;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    wire [31:0] result_w, alu_debug;
    wire fetch_pf, data_pf;
    wire [1:0] fetch_cause, data_cause;

    wire         ibus_req_valid;
    wire [31:0]  ibus_req_addr;
    reg          ibus_resp_valid;
    reg  [255:0] ibus_resp_line;

    wire         dbus_req_valid;
    wire [1:0]   dbus_req_type;
    wire [31:0]  dbus_req_addr;
    wire [255:0] dbus_req_line;
    reg          dbus_resp_valid;
    reg  [255:0] dbus_resp_line;
    reg  [1:0]   dbus_resp_state;

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
        .dsnoop_valid(1'b0), .dsnoop_type(1'b0), .dsnoop_addr(32'b0),
        .dsnoop_ack_valid(), .dsnoop_ack_hit(), .dsnoop_ack_dirty(), .dsnoop_ack_line()
    );

    reg prev_ibus_req;
    reg prev_dbus_req;
    integer rfo_count;
    integer unexpected_dreq_count;

    // Program at 0x1000:
    //   lui       x1, 0x2              // x1 = 0x2000
    //   addi      x2, x0, 5
    //   nop
    //   nop
    //   amoadd.w  x3, x2, (x1)        // x3 = 10, [0x2000] = 15
    //   lw        x4, 0(x1)            // x4 = 15 (D$ hit)
    //   jal       x0, 0
    //   nop
    //
    // Both responders pulse valid once per new level-held request, matching
    // the cache/coherence-manager contract used by the integrated SoC.
    always @(posedge clk) begin
        if (rst) begin
            prev_ibus_req        <= 1'b0;
            prev_dbus_req        <= 1'b0;
            ibus_resp_valid      <= 1'b0;
            dbus_resp_valid      <= 1'b0;
            ibus_resp_line       <= 256'b0;
            dbus_resp_line       <= 256'b0;
            dbus_resp_state      <= 2'b01;
            rfo_count            <= 0;
            unexpected_dreq_count <= 0;
        end
        else begin
            ibus_resp_valid <= 1'b0;
            dbus_resp_valid <= 1'b0;

            if (ibus_req_valid && !prev_ibus_req) begin
                if (ibus_req_addr == 32'h0000_1000) begin
                    ibus_resp_line <= {
                        32'h0000_0013, // nop
                        32'h0000_006f, // jal x0, 0
                        32'h0000_a203, // lw x4, 0(x1)
                        32'h0020_a1af, // amoadd.w x3, x2, (x1)
                        32'h0000_0013, // nop
                        32'h0000_0013, // nop
                        32'h0050_0113, // addi x2, x0, 5
                        32'h0000_20b7  // lui x1, 0x2
                    };
                end
                else begin
                    ibus_resp_line <= {8{32'h0000_006f}};
                end
                ibus_resp_valid <= 1'b1;
            end

            if (dbus_req_valid && !prev_dbus_req) begin
                dbus_resp_line       <= 256'b0;
                dbus_resp_line[31:0] <= 32'd10;
                dbus_resp_state      <= (dbus_req_type == 2'b01) ? 2'b11 : 2'b01;
                dbus_resp_valid      <= 1'b1;
                if ((dbus_req_type == 2'b01) && (dbus_req_addr == 32'h0000_2000))
                    rfo_count <= rfo_count + 1;
                else
                    unexpected_dreq_count <= unexpected_dreq_count + 1;
            end

            prev_ibus_req <= ibus_req_valid;
            prev_dbus_req <= dbus_req_valid;
        end
    end

    integer errors;
    integer cycles;
    reg saw_amo_old_value;
    reg saw_load_new_value;

    always @(posedge clk) begin
        if (rst) begin
            saw_amo_old_value <= 1'b0;
            saw_load_new_value <= 1'b0;
        end
        else if (dut.mmu_core.core.RegWriteW) begin
            if ((dut.mmu_core.core.RD_W == 5'd3) && (result_w == 32'd10))
                saw_amo_old_value <= 1'b1;
            if ((dut.mmu_core.core.RD_W == 5'd4) && (result_w == 32'd15))
                saw_load_new_value <= 1'b1;
        end
    end

    initial begin
        errors = 0;
        cycles = 0;
        saw_amo_old_value = 1'b0;
        saw_load_new_value = 1'b0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        while (!(saw_amo_old_value && saw_load_new_value) && cycles < 300) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!saw_amo_old_value) begin
            $display("[FAIL] AMOADD.W did not return the old filled word to rd");
            errors = errors + 1;
        end
        else
            $display("[PASS] AMOADD.W returned old value 10 to x3");

        if (!saw_load_new_value) begin
            $display("[FAIL] post-AMO load did not observe the committed RMW value");
            errors = errors + 1;
        end
        else
            $display("[PASS] following LW observed AMO result 15 in D$");

        if (rfo_count != 1) begin
            $display("[FAIL] cold AMO issued %0d ownership request(s), expected 1", rfo_count);
            errors = errors + 1;
        end
        else
            $display("[PASS] cold AMO issued exactly one RFO");

        if (unexpected_dreq_count != 0) begin
            $display("[FAIL] observed %0d unexpected D$ request(s)", unexpected_dreq_count);
            errors = errors + 1;
        end

        if (fetch_pf || data_pf) begin
            $display("[FAIL] AMO smoke program raised an unexpected page fault");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("CACHE_AMO_TB: PASS");
        else
            $display("CACHE_AMO_TB: FAIL (%0d check(s) failed)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 500);
        $display("CACHE_AMO_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
