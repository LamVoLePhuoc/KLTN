`timescale 1ns / 1ps

// Verifies the internal L1<->coherence AHB bridge preserves the new error
// sideband in both directions instead of treating HRESP ERROR as OKAY.
module tb_ahb_error_sideband;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg resetn;
    integer errors;

    reg bus_req_valid;
    reg [1:0] bus_req_type;
    reg [31:0] bus_req_addr;
    reg [255:0] bus_req_line;
    wire bus_resp_valid, bus_resp_error;
    wire [255:0] bus_resp_line;
    wire [1:0] bus_resp_state;

    wire [31:0] haddr, hwdata, hrdata;
    wire hwrite, hready, hmastlock;
    wire [1:0] htrans, hresp;
    wire [2:0] hsize;
    wire [3:0] hprot;

    wire dreq_valid;
    wire [1:0] dreq_type;
    wire [31:0] dreq_addr;
    wire [255:0] dreq_line;
    reg dresp_valid, dresp_error;
    reg [255:0] dresp_line;

    ahb_lite_l1_adapter u_master (
        .HCLK(clk), .HRESETn(resetn),
        .bus_req_valid(bus_req_valid), .bus_req_type(bus_req_type),
        .bus_req_addr(bus_req_addr), .bus_req_line(bus_req_line),
        .bus_resp_valid(bus_resp_valid), .bus_resp_error(bus_resp_error),
        .bus_resp_line(bus_resp_line), .bus_resp_state(bus_resp_state),
        .HADDR(haddr), .HWRITE(hwrite), .HSIZE(hsize), .HTRANS(htrans),
        .HWDATA(hwdata), .HBURST(), .HPROT(hprot), .HMASTLOCK(hmastlock),
        .HRDATA(hrdata), .HREADY(hready), .HRESP(hresp)
    );

    ahb_lite_l1_slave_adapter u_slave (
        .HCLK(clk), .HRESETn(resetn),
        .HADDR(haddr), .HWRITE(hwrite), .HTRANS(htrans),
        .HWDATA(hwdata), .HMASTLOCK(hmastlock), .HSIZE(hsize), .HPROT(hprot),
        .HREADYOUT(hready), .HRDATA(hrdata), .HRESP(hresp),
        .dreq_valid(dreq_valid), .dreq_type(dreq_type),
        .dreq_addr(dreq_addr), .dreq_line(dreq_line),
        .dresp_valid(dresp_valid), .dresp_error(dresp_error),
        .dresp_line(dresp_line), .dresp_state(2'b01)
    );

    task check;
        input condition;
        input [8*80-1:0] name;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
            else $display("[PASS] %0s", name);
        end
    endtask

    task transact;
        input [1:0] typ;
        input backend_error;
        output observed_error;
        begin
            @(negedge clk);
            bus_req_type = typ;
            bus_req_valid = 1'b1;
            wait (dreq_valid);
            @(negedge clk);
            dresp_error = backend_error;
            dresp_valid = 1'b1;
            @(negedge clk);
            dresp_valid = 1'b0;
            dresp_error = 1'b0;
            wait (bus_resp_valid);
            #1 observed_error = bus_resp_error;
            @(negedge clk);
            bus_req_valid = 1'b0;
            repeat (3) @(posedge clk);
        end
    endtask

    reg observed_error;
    initial begin
        resetn = 1'b0; errors = 0;
        bus_req_valid = 1'b0; bus_req_type = 2'b00;
        bus_req_addr = 32'h0000_8000;
        bus_req_line = {8{32'hABCD_0123}};
        dresp_valid = 1'b0; dresp_error = 1'b0;
        dresp_line = {8{32'h1357_9BDF}};
        repeat (3) @(posedge clk);
        resetn = 1'b1;

        transact(2'b00, 1'b1, observed_error);
        check(observed_error, "AHB read ERROR reaches L1 bus_resp_error");

        transact(2'b10, 1'b1, observed_error);
        check(observed_error, "AHB write ERROR reaches L1 bus_resp_error");

        transact(2'b00, 1'b0, observed_error);
        check(!observed_error, "AHB bridge recovers for a later OKAY response");
        check(bus_resp_line == dresp_line,
              "successful AHB retry returns the complete cache line");

        if (errors == 0) $display("AHB_ERROR_SIDEBAND_TB: PASS");
        else             $display("AHB_ERROR_SIDEBAND_TB: FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #20000;
        $display("AHB_ERROR_SIDEBAND_TB: FAIL (timeout)");
        $finish;
    end
endmodule
