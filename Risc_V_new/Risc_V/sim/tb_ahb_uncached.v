`timescale 1ns / 1ps

// Verifies that the literal AHB-Lite bridge preserves the native
// single-word UNCACHED request, including HPROT cacheability, HSIZE,
// byte address, write strobes and read data.
module tb_ahb_uncached;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg resetn;
    integer errors;
    integer nonseq_count;

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
        .dresp_line(dresp_line), .dresp_state(2'b00)
    );

    always @(posedge clk) begin
        if (!resetn) nonseq_count <= 0;
        else if (htrans == 2'b10) nonseq_count <= nonseq_count + 1;
    end

    task check;
        input condition;
        input [8*92-1:0] name;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[FAIL] %0s", name);
            end
            else $display("[PASS] %0s", name);
        end
    endtask

    integer count_before;
    initial begin
        errors = 0;
        resetn = 1'b0;
        bus_req_valid = 1'b0;
        bus_req_type = 2'b0;
        bus_req_addr = 32'b0;
        bus_req_line = 256'b0;
        dresp_valid = 1'b0;
        dresp_error = 1'b0;
        dresp_line = 256'b0;
        repeat (4) @(posedge clk);
        resetn = 1'b1;
        repeat (2) @(posedge clk);

        // Upper-halfword device write. Native metadata entering the
        // master is reconstructed after the AHB slave byte-for-byte.
        count_before = nonseq_count;
        @(negedge clk);
        bus_req_type = 2'b11;
        bus_req_addr = 32'hC000_0012;
        bus_req_line = {{219{1'b0}}, 1'b1, 4'b1100, 32'hABCD_0000};
        bus_req_valid = 1'b1;
        wait (dreq_valid);
        #1;
        check(!hprot[3] && hsize == 3'b001 && hwrite,
              "uncached SH uses non-cacheable HPROT, halfword HSIZE and HWRITE");
        check(dreq_type == 2'b11 && dreq_addr == 32'hC000_0012,
              "AHB slave reconstructs exact uncached byte address and request type");
        check(dreq_line[36] && dreq_line[35:32] == 4'b1100 &&
              dreq_line[31:0] == 32'hABCD_0000,
              "AHB slave reconstructs uncached write enable, WSTRB and WDATA");
        @(negedge clk);
        dresp_valid = 1'b1;
        @(negedge clk);
        dresp_valid = 1'b0;
        wait (bus_resp_valid);
        @(negedge clk);
        bus_req_valid = 1'b0;
        repeat (2) @(posedge clk);
        check(nonseq_count == count_before + 1,
              "uncached write consumes exactly one AHB transfer rather than a cache line");

        // Device read also consumes one transfer and returns the backend
        // word in response lane zero for the D$ load formatter.
        count_before = nonseq_count;
        @(negedge clk);
        bus_req_addr = 32'hC000_0021;
        bus_req_line = 256'b0;
        bus_req_valid = 1'b1;
        wait (dreq_valid);
        #1;
        check(!hwrite && !hprot[3] && dreq_type == 2'b11,
              "uncached read remains non-cacheable and is not mistaken for RFO");
        @(negedge clk);
        dresp_line = {{224{1'b0}}, 32'hDEAD_BEEF};
        dresp_valid = 1'b1;
        @(negedge clk);
        dresp_valid = 1'b0;
        wait (bus_resp_valid);
        #1;
        check(!bus_resp_error && bus_resp_line[31:0] == 32'hDEAD_BEEF,
              "uncached read data crosses the AHB bridge in response word zero");
        @(negedge clk);
        bus_req_valid = 1'b0;
        repeat (2) @(posedge clk);
        check(nonseq_count == count_before + 1,
              "uncached read consumes exactly one AHB transfer rather than eight");

        if (errors == 0) $display("AHB_UNCACHED_TB: PASS");
        else             $display("AHB_UNCACHED_TB: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
