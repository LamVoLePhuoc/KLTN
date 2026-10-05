`timescale 1ns / 1ps

module tb_boot_ctrl;
    reg clk, resetn;
    reg [3:0] awaddr;
    reg awvalid;
    wire awready;
    reg [31:0] wdata;
    reg [3:0] wstrb;
    reg wvalid;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready;
    reg [3:0] araddr;
    reg arvalid;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready;

    wire core_go;
    reg cache_busy, cache_done, cache_error;
    wire cache_request;

    integer errors;
    integer request_count;
    reg previous_request;
    reg [31:0] read_value;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    boot_ctrl dut (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(resetn),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb), .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp), .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready),
        .core_go(core_go), .cache_flush_busy(cache_busy),
        .cache_flush_done(cache_done), .cache_flush_error(cache_error),
        .cache_flush_request(cache_request)
    );

    always @(posedge clk) begin
        if (!resetn) begin
            request_count <= 0;
            previous_request <= 1'b0;
        end
        else begin
            if (cache_request)
                request_count <= request_count + 1;
            if (cache_request && previous_request) begin
                $display("[FAIL] cache maintenance request lasted more than one cycle");
                errors = errors + 1;
            end
            previous_request <= cache_request;
        end
    end

    task check;
        input condition;
        input [8*90-1:0] message;
        begin
            if (!condition) begin
                $display("[FAIL] %0s", message);
                errors = errors + 1;
            end
            else
                $display("[PASS] %0s", message);
        end
    endtask

    task axi_write;
        input [3:0] address;
        input [31:0] data;
        input [3:0] strobes;
        begin
            @(negedge clk);
            awaddr = address; wdata = data; wstrb = strobes;
            awvalid = 1'b1; wvalid = 1'b1;
            wait (awready && wready);
            @(negedge clk);
            awvalid = 1'b0; wvalid = 1'b0;
            bready = 1'b1;
            wait (bvalid);
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task axi_read;
        input [3:0] address;
        output [31:0] data;
        begin
            @(negedge clk);
            araddr = address; arvalid = 1'b1;
            wait (arready && rvalid);
            #1 data = rdata;
            @(negedge clk);
            arvalid = 1'b0; rready = 1'b1;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    initial begin
        errors = 0;
        resetn = 1'b0;
        awaddr = 4'b0; awvalid = 1'b0;
        wdata = 32'b0; wstrb = 4'b0; wvalid = 1'b0;
        bready = 1'b0; araddr = 4'b0; arvalid = 1'b0; rready = 1'b0;
        cache_busy = 1'b0; cache_done = 1'b0; cache_error = 1'b0;
        repeat (4) @(posedge clk);
        resetn = 1'b1;

        // A maintenance command before GO is intentionally rejected: the
        // cache hierarchy is still held in reset and cannot consume it.
        axi_write(4'hC, 32'h1, 4'b0001);
        axi_read(4'hC, read_value);
        check(request_count == 0 && read_value[3],
              "pre-GO maintenance request is rejected and reported");

        // WSTRB must be honored for all software-visible registers.
        axi_write(4'h0, 32'h1, 4'b0000);
        check(!core_go, "zero byte strobe cannot release cores");
        axi_write(4'h0, 32'h1, 4'b0001);
        check(core_go, "GO write releases cores");
        axi_write(4'h0, 32'h0, 4'b0001);
        check(core_go, "GO remains sticky after a write of zero");

        axi_write(4'h8, 32'h1122_3344, 4'b1111);
        axi_write(4'h8, 32'hAABB_CCDD, 4'b0101);
        axi_read(4'h8, read_value);
        check(read_value == 32'h11BB_33DD,
              "RESULT register applies AXI byte strobes");

        // Accepted command emits exactly one pulse and clears stale status.
        axi_write(4'hC, 32'h1, 4'b0001);
        repeat (2) @(posedge clk);
        check(request_count == 1, "accepted maintenance emits one request pulse");
        axi_read(4'hC, read_value);
        check(!read_value[3] && !read_value[1],
              "accepted maintenance clears rejected and stale done status");

        cache_busy = 1'b1;
        axi_read(4'hC, read_value);
        check(read_value[0], "CACHE status exposes hierarchy busy");
        axi_write(4'hC, 32'h1, 4'b0001);
        repeat (2) @(posedge clk);
        axi_read(4'hC, read_value);
        check(request_count == 1 && read_value[3],
              "command while busy is rejected without a second pulse");

        @(negedge clk); cache_busy = 1'b0; cache_done = 1'b1;
        @(negedge clk); cache_done = 1'b0;
        axi_read(4'hC, read_value);
        check(read_value[1], "one-cycle hierarchy done is latched for software polling");

        cache_error = 1'b1;
        axi_read(4'hC, read_value);
        check(read_value[2], "CACHE status exposes sticky hierarchy error");

        if (errors == 0)
            $display("BOOT_CTRL_TB: PASS");
        else
            $display("BOOT_CTRL_TB: FAIL (%0d check(s) failed)", errors);
        $finish;
    end

    initial begin
        #10000;
        $display("BOOT_CTRL_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
