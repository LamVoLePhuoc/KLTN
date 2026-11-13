`timescale 1ns / 1ps

module tb_reset_sync;
    localparam CLK_PERIOD = 10;
    reg clk;
    reg arst_n;
    wire srst;
    wire srst_n;
    integer errors;

    reset_sync dut (
        .clk(clk), .arst_n(arst_n), .srst(srst), .srst_n(srst_n)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    task check_reset;
        input expected;
        input [8*80-1:0] label_text;
        begin
            #1;
            if ((srst !== expected) || (srst_n !== ~expected)) begin
                errors = errors + 1;
                $display("[FAIL] %0s srst=%b srst_n=%b expected=%b",
                         label_text, srst, srst_n, expected);
            end
            else
                $display("[PASS] %0s", label_text);
        end
    endtask

    initial begin
        clk = 1'b0;
        arst_n = 1'b0;
        errors = 0;
        check_reset(1'b1, "asynchronous reset starts asserted");

        // Deassert away from an edge.  Release must wait for two complete
        // rising edges, irrespective of the phase of the external pin.
        #2 arst_n = 1'b1;
        @(posedge clk); check_reset(1'b1, "first release edge remains reset");
        @(posedge clk); check_reset(1'b0, "second release edge leaves reset");

        // Assert just after a rising edge; downstream reset must react without
        // waiting for another clock edge.
        #2 arst_n = 1'b0;
        check_reset(1'b1, "mid-cycle assertion is asynchronous");

        // A short release followed by reassertion before two edges must never
        // expose a partial reset release.
        #2 arst_n = 1'b1;
        @(posedge clk); check_reset(1'b1, "short release reached one stage only");
        #1 arst_n = 1'b0;
        check_reset(1'b1, "reassertion clears both synchronizer stages");

        #3 arst_n = 1'b1;
        @(posedge clk); check_reset(1'b1, "final release edge one");
        @(posedge clk); check_reset(1'b0, "final release edge two");

        if (errors == 0)
            $display("RESET_SYNC_TB: PASS");
        else
            $display("RESET_SYNC_TB: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 30);
        $display("RESET_SYNC_TB: FAIL (timeout)");
        $finish;
    end
endmodule
