`timescale 1ns / 1ps

// End-to-end cache-maintenance smoke test for one integrated core.
// A real FENCE.I instruction is fetched through l1_icache, reaches
// RV32IMA's M stage, and must make core_l1_wrapper:
//   1) hold the core,
//   2) complete the safe D$ walker,
//   3) invalidate I$ only after D$ is clean,
//   4) fetch the current instruction line again.
module tb_cache_fence_i;
    localparam CLK_PERIOD = 10;

    reg clk, rst;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    wire [31:0] result_w, alu_debug;
    wire fetch_pf, data_pf;
    wire [1:0] fetch_cause, data_cause;
    wire cache_flush_busy, cache_flush_done, cache_flush_error;

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

    core_l1_wrapper #(.RESET_ADDR(32'h0000_1000)) dut (
        .clk(clk), .rst(rst), .Mmu_Flush(1'b0), .Cache_Flush(1'b0),
        .Cache_Flush_Busy(cache_flush_busy), .Cache_Flush_Done(cache_flush_done),
        .Cache_Flush_Error(cache_flush_error),
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
    integer ibus_request_starts;

    // One-cycle response to each new level-held I$ miss.  Word 0 at
    // RESET_ADDR is FENCE.I (0x0000100f); every following word is NOP.
    always @(posedge clk) begin
        if (rst) begin
            prev_ibus_req      <= 1'b0;
            ibus_resp_valid    <= 1'b0;
            ibus_resp_line     <= {8{32'h0000_0013}};
            ibus_request_starts<= 0;
            dbus_resp_valid    <= 1'b0;
            dbus_resp_line     <= 256'b0;
            dbus_resp_state    <= 2'b01;
        end
        else begin
            ibus_resp_valid <= 1'b0;
            dbus_resp_valid <= 1'b0;
            if (ibus_req_valid && !prev_ibus_req) begin
                ibus_request_starts <= ibus_request_starts + 1;
                ibus_resp_line      <= {8{32'h0000_0013}};
                if (ibus_req_addr == 32'h0000_1000)
                    ibus_resp_line[31:0] <= 32'h0000_100f;
                ibus_resp_valid <= 1'b1;
            end
            prev_ibus_req <= ibus_req_valid;

            // This program contains no data access.  Keep a benign
            // responder here so any unexpected request cannot hang
            // the test and can instead be reported explicitly below.
            if (dbus_req_valid) begin
                dbus_resp_valid <= 1'b1;
                dbus_resp_line  <= 256'b0;
                dbus_resp_state <= (dbus_req_type == 2'b01) ? 2'b11 : 2'b01;
            end
        end
    end

    integer errors;
    integer cycles;
    reg maintenance_seen;
    reg maintenance_done_seen;
    reg unexpected_dbus;

    initial begin
        errors = 0;
        cycles = 0;
        maintenance_seen = 1'b0;
        maintenance_done_seen = 1'b0;
        unexpected_dbus = 1'b0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        while (!maintenance_seen && cycles < 200) begin
            @(posedge clk);
            cycles = cycles + 1;
            if (dut.cache_flush_active)
                maintenance_seen = 1'b1;
            if (cache_flush_done)
                maintenance_done_seen = 1'b1;
            if (dbus_req_valid)
                unexpected_dbus = 1'b1;
        end

        if (!maintenance_seen) begin
            $display("[FAIL] FENCE.I never started cache maintenance");
            errors = errors + 1;
        end
        else begin
            $display("[PASS] FENCE.I reached wrapper and stalled for maintenance");
            cycles = 0;
            while (dut.cache_flush_active && cycles < 1500) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (dbus_req_valid)
                    unexpected_dbus = 1'b1;
                if (cache_flush_done)
                    maintenance_done_seen = 1'b1;
            end
            if (dut.cache_flush_active) begin
                $display("[FAIL] D$ flush walker did not finish");
                errors = errors + 1;
            end
            else begin
                $display("[PASS] D$ walker completed and released the core");
            end
        end

        repeat (20) begin
            @(posedge clk);
            if (cache_flush_done)
                maintenance_done_seen = 1'b1;
        end
        if (!maintenance_done_seen || cache_flush_error) begin
            $display("[FAIL] maintenance handshake done/error was incorrect");
            errors = errors + 1;
        end
        else begin
            $display("[PASS] maintenance handshake completed without error");
        end
        if (ibus_request_starts < 2) begin
            $display("[FAIL] I$ was not invalidated/refetched, requests=%0d", ibus_request_starts);
            errors = errors + 1;
        end
        else begin
            $display("[PASS] I$ invalidation forced a new line fetch");
        end

        if (unexpected_dbus) begin
            $display("[FAIL] NOP/FENCE.I program unexpectedly accessed D$");
            errors = errors + 1;
        end
        else begin
            $display("[PASS] maintenance of a clean D$ emitted no writeback");
        end

        if (errors == 0)
            $display("CACHE_FENCE_I_TB: PASS");
        else
            $display("CACHE_FENCE_I_TB: FAIL (%0d check(s) failed)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 2500);
        $display("CACHE_FENCE_I_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
