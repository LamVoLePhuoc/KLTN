`timescale 1ns / 1ps

module tb_ahb_arbiter;
    reg clk;
    reg resetn;
    reg [7:0] requests;
    wire [7:0] grants;
    wire grant_valid;
    wire [2:0] grant_source;
    reg [15:0] master_htrans;
    wire [7:0] master_hready;
    wire [255:0] master_hrdata;
    wire [15:0] master_hresp;
    reg slave_hready;
    reg [31:0] slave_hrdata;
    reg [1:0] slave_hresp;
    integer errors;
    integer step;
    reg [2:0] expected_source;

    ahb_lite_arbiter_8m1s dut (
        .HCLK(clk), .HRESETn(resetn),
        .M_REQ_ACTIVE(requests),
        .M_HADDR(256'b0), .M_HWRITE(8'b0),
        .M_HSIZE({8{3'b010}}), .M_HTRANS(master_htrans),
        .M_HWDATA(256'b0), .M_HPROT({8{4'b1011}}),
        .M_HMASTLOCK(8'b0),
        .M_HGRANT(grants), .M_HREADY(master_hready),
        .M_HRDATA(master_hrdata), .M_HRESP(master_hresp),
        .S_HADDR(), .S_HWRITE(), .S_HSIZE(), .S_HTRANS(),
        .S_HWDATA(), .S_HPROT(), .S_HMASTLOCK(), .S_REQ_ACTIVE(),
        .S_HREADY(slave_hready), .S_HRDATA(slave_hrdata),
        .S_HRESP(slave_hresp),
        .GRANT_VALID(grant_valid), .GRANT_SOURCE(grant_source)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        requests = 8'b0;
        master_htrans = 16'b0;
        slave_hready = 1'b1;
        slave_hrdata = 32'b0;
        slave_hresp = 2'b00;
        errors = 0;
        repeat (3) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        requests = 8'hff;
        expected_source = 3'd0;
        for (step = 0; step < 8; step = step + 1) begin
            while (!grant_valid) @(negedge clk);
            if ((grant_source !== expected_source) ||
                (grants !== (8'b1 << expected_source))) begin
                $display("[FAIL] expected grant %0d, source=%0d grants=%02x",
                         expected_source, grant_source, grants);
                errors = errors + 1;
            end
            repeat (2) begin
                @(negedge clk);
                if (!grant_valid || (grant_source !== expected_source)) begin
                    $display("[FAIL] grant %0d was not held", expected_source);
                    errors = errors + 1;
                end
            end
            requests[expected_source] = 1'b0;
            while (grant_valid) @(negedge clk);
            expected_source = expected_source + 3'd1;
        end

        // The slave response must be buffered for exactly one cycle and
        // returned only to its owning master.  Use master 3 and insert two
        // slave wait cycles to exercise both address/data-phase tracking and
        // registered response routing.
        @(negedge clk);
        requests[3] = 1'b1;
        master_htrans[3*2 +: 2] = 2'b10;
        while (!grant_valid || (grant_source != 3'd3)) @(negedge clk);
        @(posedge clk); // address phase accepted while slave_hready is high
        @(negedge clk);
        master_htrans[3*2 +: 2] = 2'b00;
        slave_hready = 1'b0;
        repeat (2) begin
            @(negedge clk);
            if (master_hready !== 8'b0) begin
                $display("[FAIL] master completed before the slave response");
                errors = errors + 1;
            end
        end

        slave_hrdata = 32'hDEAD_BEEF;
        slave_hresp  = 2'b01;
        slave_hready = 1'b1;
        @(posedge clk); // capture slave response into master-3 buffer
        @(negedge clk);
        if (master_hready !== 8'b0000_1000 ||
            master_hrdata[3*32 +: 32] !== 32'hDEAD_BEEF ||
            master_hresp[3*2 +: 2] !== 2'b01) begin
            $display("[FAIL] buffered response routed incorrectly: ready=%02x data=%08x resp=%02b",
                     master_hready, master_hrdata[3*32 +: 32],
                     master_hresp[3*2 +: 2]);
            errors = errors + 1;
        end
        @(posedge clk);
        @(negedge clk);
        if (master_hready !== 8'b0) begin
            $display("[FAIL] buffered response valid lasted more than one cycle");
            errors = errors + 1;
        end
        requests[3] = 1'b0;

        if (errors == 0)
            $display("AHB_ARBITER_TB: PASS");
        else
            $display("AHB_ARBITER_TB: FAIL (%0d checks failed)", errors);
        $finish;
    end

    initial begin
        #5000;
        $display("AHB_ARBITER_TB: FAIL (timeout)");
        $finish;
    end
endmodule
