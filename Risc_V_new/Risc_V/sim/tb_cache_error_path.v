`timescale 1ns / 1ps

// Unit-level proof that a failed line response completes the held CPU
// access with an error but never installs partial/invalid cache data.
module tb_cache_error_path;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst;
    integer errors;

    reg  [31:0] i_cpu_addr;
    wire [31:0] i_cpu_rdata;
    wire i_cpu_valid, i_cpu_error;
    wire i_req_valid;
    wire [31:0] i_req_addr;
    reg i_resp_valid, i_resp_error;
    reg [255:0] i_resp_line;

    l1_icache u_icache (
        .clk(clk), .rst(rst), .flush(1'b0),
        .cpu_addr(i_cpu_addr), .cpu_rdata(i_cpu_rdata),
        .cpu_valid(i_cpu_valid), .cpu_error(i_cpu_error),
        .bus_req_valid(i_req_valid), .bus_req_addr(i_req_addr),
        .bus_resp_valid(i_resp_valid), .bus_resp_error(i_resp_error),
        .bus_resp_line(i_resp_line)
    );

    reg [31:0] d_cpu_addr, d_cpu_wdata, d_cpu_amo_operand;
    reg d_cpu_we, d_cpu_re, d_cpu_amo;
    reg [2:0] d_cpu_memop;
    reg [4:0] d_cpu_amo_op;
    wire [31:0] d_cpu_rdata;
    wire d_cpu_valid, d_cpu_error;
    wire d_req_valid;
    wire [1:0] d_req_type;
    wire [31:0] d_req_addr;
    wire [255:0] d_req_line;
    reg d_resp_valid, d_resp_error;
    reg [255:0] d_resp_line;

    l1_dcache u_dcache (
        .clk(clk), .rst(rst), .flush(1'b0),
        .flush_busy(), .flush_done(),
        .cpu_addr(d_cpu_addr), .cpu_wdata(d_cpu_wdata),
        .cpu_we(d_cpu_we), .cpu_re(d_cpu_re), .cpu_memop(d_cpu_memop),
        .cpu_amo(d_cpu_amo), .cpu_amo_op(d_cpu_amo_op),
        .cpu_amo_operand(d_cpu_amo_operand),
        .cpu_rdata(d_cpu_rdata), .cpu_valid(d_cpu_valid), .cpu_error(d_cpu_error),
        .bus_req_valid(d_req_valid), .bus_req_type(d_req_type),
        .bus_req_addr(d_req_addr), .bus_req_line(d_req_line),
        .bus_resp_valid(d_resp_valid), .bus_resp_error(d_resp_error),
        .bus_resp_line(d_resp_line), .bus_resp_state(2'b01),
        .snoop_valid(1'b0), .snoop_type(1'b0), .snoop_addr(32'b0),
        .snoop_ack_valid(), .snoop_ack_hit(), .snoop_ack_dirty(),
        .snoop_ack_line(), .flush_error()
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

    initial begin
        rst = 1'b1;
        errors = 0;
        i_cpu_addr = 32'h0000_1000;
        i_resp_valid = 1'b0; i_resp_error = 1'b0;
        i_resp_line = {8{32'h0000_0013}};
        d_cpu_addr = 32'h0000_2000; d_cpu_wdata = 32'b0;
        d_cpu_we = 1'b0; d_cpu_re = 1'b0; d_cpu_memop = 3'b010;
        d_cpu_amo = 1'b0; d_cpu_amo_op = 5'b0; d_cpu_amo_operand = 32'b0;
        d_resp_valid = 1'b0; d_resp_error = 1'b0;
        d_resp_line = {8{32'hCAFE_BABE}};

        repeat (3) @(posedge clk);
        rst = 1'b0;

        // I$: failed fill must report an error and remain a miss.
        wait (i_req_valid);
        @(negedge clk);
        i_resp_valid = 1'b1; i_resp_error = 1'b1;
        #1 check(i_cpu_valid && i_cpu_error,
                 "I-cache failed fill completes fetch with error");
        @(posedge clk);
        @(negedge clk);
        i_resp_valid = 1'b0; i_resp_error = 1'b0;
        wait (i_req_valid);
        check(1'b1, "I-cache error response was not installed as a hit");

        @(negedge clk);
        i_resp_valid = 1'b1; i_resp_error = 1'b0;
        i_resp_line[31:0] = 32'h1234_5678;
        @(posedge clk); #1;
        i_resp_valid = 1'b0;
        check(i_cpu_valid && !i_cpu_error && i_cpu_rdata == 32'h1234_5678,
              "I-cache can refill successfully after an error");

        // D$: failed fill produces a registered completion/error pulse.
        @(negedge clk);
        d_cpu_re = 1'b1;
        wait (d_req_valid);
        @(negedge clk);
        d_resp_valid = 1'b1; d_resp_error = 1'b1;
        @(posedge clk); #1;
        check(d_cpu_valid && d_cpu_error,
              "D-cache failed fill completes load with error");
        @(negedge clk);
        d_resp_valid = 1'b0; d_resp_error = 1'b0; d_cpu_re = 1'b0;
        repeat (2) @(posedge clk);

        // Retry proves the failed response did not allocate the line.
        @(negedge clk);
        d_cpu_re = 1'b1;
        wait (d_req_valid);
        check(1'b1, "D-cache error response was not installed as a hit");
        @(negedge clk);
        d_resp_valid = 1'b1; d_resp_error = 1'b0;
        d_resp_line[31:0] = 32'h89AB_CDEF;
        @(posedge clk); #1;
        check(d_cpu_valid && !d_cpu_error && d_cpu_rdata == 32'h89AB_CDEF,
              "D-cache can refill successfully after an error");
        @(negedge clk);
        d_resp_valid = 1'b0; d_cpu_re = 1'b0;

        if (errors == 0) $display("CACHE_ERROR_PATH_TB: PASS");
        else             $display("CACHE_ERROR_PATH_TB: FAIL (%0d)", errors);
        $finish;
    end

    initial begin
        #10000;
        $display("CACHE_ERROR_PATH_TB: FAIL (timeout)");
        $finish;
    end
endmodule
