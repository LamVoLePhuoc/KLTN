`timescale 1ns / 1ps

// System-level cache-maintenance completion tracker test.  The four
// private-cache engines are represented by explicit busy/done/error
// vectors so staggered completion and a request queued behind FENCE.I
// can be checked without running four complete processor pipelines.
module tb_cache_maintenance;
    reg clk, rst;
    reg request;
    reg [3:0] core_busy;
    reg [3:0] core_done;
    reg [3:0] core_error;
    wire busy, done, error;

    integer errors;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    cache_maintenance_tracker #(.WATCHDOG_CYCLES(12)) dut (
        .clk(clk), .rst(rst), .request(request),
        .core_busy(core_busy), .core_done(core_done),
        .core_error(core_error), .busy(busy), .done(done),
        .error(error)
    );

    task check;
        input condition;
        input [8*80-1:0] message;
        begin
            if (!condition) begin
                $display("[FAIL] %0s", message);
                errors = errors + 1;
            end
            else
                $display("[PASS] %0s", message);
        end
    endtask

    task pulse_request;
        begin
            @(negedge clk); request = 1'b1;
            #1 check(busy, "busy asserts immediately with request");
            @(negedge clk); request = 1'b0;
        end
    endtask

    task pulse_core_done;
        input [3:0] mask;
        begin
            @(negedge clk); core_done = mask;
            @(negedge clk); core_done = 4'b0;
        end
    endtask

    initial begin
        errors = 0;
        rst = 1'b1;
        request = 1'b0;
        core_busy = 4'b0;
        core_done = 4'b0;
        core_error = 4'b0;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        // Staggered completion: the system response must wait for all
        // four caches, not merely the first or last currently-busy one.
        pulse_request();
        pulse_core_done(4'b0001);
        check(busy && !done, "staggered core 0 completion does not finish transaction");
        pulse_core_done(4'b0110);
        check(busy && !done, "staggered cores 1/2 completion does not finish transaction");
        @(negedge clk); core_done = 4'b1000;
        @(posedge clk); #1;
        check(done && !busy, "all four idle completions produce one done pulse");
        @(negedge clk); core_done = 4'b0;
        @(posedge clk); #1;
        check(!done, "done is exactly one cycle");

        // A request can arrive while one core is already handling a
        // local FENCE.I.  Its first done pulse is not the completion of
        // the queued external flush because that core remains busy.
        core_busy = 4'b0001;
        pulse_request();
        pulse_core_done(4'b1110);
        @(negedge clk); core_done = 4'b0001;
        @(posedge clk); #1;
        check(busy && !done, "busy core's earlier FENCE.I done is not miscounted");
        @(negedge clk); core_done = 4'b0;
        repeat (2) @(posedge clk);
        @(negedge clk); core_busy = 4'b0000; core_done = 4'b0001;
        @(posedge clk); #1;
        check(done && !busy, "queued external maintenance completes after core becomes idle");
        @(negedge clk); core_done = 4'b0;

        // Errors are diagnostic and sticky, while completion still
        // releases the external DMA/boot controller without deadlock.
        pulse_request();
        @(negedge clk); core_error = 4'b0100; core_done = 4'b1111;
        @(posedge clk); #1;
        check(done && error, "error is reported together with completion");
        @(negedge clk); core_error = 4'b0; core_done = 4'b0;
        repeat (2) @(posedge clk);
        check(error, "maintenance error remains sticky until reset");

        // A stuck cache must become diagnosable, but the tracker must not
        // fabricate completion or release busy without a safe bus cancel.
        @(negedge clk); rst = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk); rst = 1'b0; core_busy = 4'b0001;
        pulse_request();
        repeat (14) @(posedge clk);
        check(error && busy && !done,
              "watchdog reports a stuck maintenance without unsafe completion");

        if (errors == 0)
            $display("CACHE_MAINTENANCE_TB: PASS");
        else
            $display("CACHE_MAINTENANCE_TB: FAIL (%0d check(s) failed)", errors);
        $finish;
    end

    initial begin
        #5000;
        $display("CACHE_MAINTENANCE_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
