`timescale 1ns/1ps

module tb_new_mmu;

    logic clk;
    logic rst_n;

    logic [31:0] i_cpu_addr;
    wire  [31:0] i_cpu_rdata;
    wire         i_cpu_ready;

    logic        d_cpu_mem_st_en;
    logic        d_cpu_mem_ld_en;
    logic [11:0] d_cpu_mem_addr;
    logic [3:0]  d_cpu_mem_byte_en;
    logic [2:0]  d_cpu_mem_ld_sel;
    logic [63:0] d_cpu_mem_st_data;
    wire  [63:0] d_cpu_mem_ld_data;
    wire         d_cpu_ready;

    logic        d_fpu_mem_ld_sel;
    logic        d_fpu_mem_wren;
    logic [11:0] d_fpu_mem_addr;
    logic [63:0] d_fpu_mem_din;
    wire  [63:0] d_fpu_mem_dout;

    wire  [31:0]  i_mem_req_addr;
    wire          i_mem_req_read;
    wire          i_mem_req_write;
    wire  [255:0] i_mem_req_wdata;
    logic [255:0] i_mem_rdata;
    logic         i_mem_ready;

    wire  [31:0]  d_mem_req_addr;
    wire          d_mem_req_read;
    wire          d_mem_req_write;
    wire  [255:0] d_mem_req_wdata;
    logic [255:0] d_mem_rdata;
    logic         d_mem_ready;

    logic [255:0] i_mem [0:31];
    logic [255:0] d_mem [0:31];

    MMU dut (
        .clk(clk),
        .rst_n(rst_n),
        .i_cpu_addr(i_cpu_addr),
        .i_cpu_rdata(i_cpu_rdata),
        .i_cpu_ready(i_cpu_ready),
        .d_cpu_mem_st_en(d_cpu_mem_st_en),
        .d_cpu_mem_ld_en(d_cpu_mem_ld_en),
        .d_cpu_mem_addr(d_cpu_mem_addr),
        .d_cpu_mem_byte_en(d_cpu_mem_byte_en),
        .d_cpu_mem_ld_sel(d_cpu_mem_ld_sel),
        .d_cpu_mem_st_data(d_cpu_mem_st_data),
        .d_cpu_mem_ld_data(d_cpu_mem_ld_data),
        .d_cpu_ready(d_cpu_ready),
        .d_fpu_mem_ld_sel(d_fpu_mem_ld_sel),
        .d_fpu_mem_wren(d_fpu_mem_wren),
        .d_fpu_mem_addr(d_fpu_mem_addr),
        .d_fpu_mem_din(d_fpu_mem_din),
        .d_fpu_mem_dout(d_fpu_mem_dout),
        .i_mem_req_addr(i_mem_req_addr),
        .i_mem_req_read(i_mem_req_read),
        .i_mem_req_write(i_mem_req_write),
        .i_mem_req_wdata(i_mem_req_wdata),
        .i_mem_rdata(i_mem_rdata),
        .i_mem_ready(i_mem_ready),
        .d_mem_req_addr(d_mem_req_addr),
        .d_mem_req_read(d_mem_req_read),
        .d_mem_req_write(d_mem_req_write),
        .d_mem_req_wdata(d_mem_req_wdata),
        .d_mem_rdata(d_mem_rdata),
        .d_mem_ready(d_mem_ready)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic [255:0] make_line32(input [31:0] base);
        make_line32 = {
            base + 32'h00,
            base + 32'h04,
            base + 32'h08,
            base + 32'h0c,
            base + 32'h10,
            base + 32'h14,
            base + 32'h18,
            base + 32'h1c
        };
    endfunction

    function automatic [255:0] make_line64(input [63:0] base);
        make_line64 = {
            base + 64'h00,
            base + 64'h08,
            base + 64'h10,
            base + 64'h18
        };
    endfunction

    task automatic wait_i_ready;
        int timeout;
        begin
            timeout = 0;
            while (!i_cpu_ready && timeout < 40) begin
                @(posedge clk);
                timeout++;
            end
            if (!i_cpu_ready) $fatal(1, "I-cache timeout");
        end
    endtask

    task automatic wait_d_ready;
        int timeout;
        begin
            timeout = 0;
            while (!d_cpu_ready && timeout < 40) begin
                @(posedge clk);
                timeout++;
            end
            if (!d_cpu_ready) $fatal(1, "D-cache timeout");
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            i_mem_ready <= 1'b0;
            i_mem_rdata <= '0;
        end else begin
            i_mem_ready <= i_mem_req_read || i_mem_req_write;
            if (i_mem_req_read) begin
                i_mem_rdata <= i_mem[i_mem_req_addr[9:5]];
            end
            if (i_mem_req_write) begin
                i_mem[i_mem_req_addr[9:5]] <= i_mem_req_wdata;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_mem_ready <= 1'b0;
            d_mem_rdata <= '0;
        end else begin
            d_mem_ready <= d_mem_req_read || d_mem_req_write;
            if (d_mem_req_read) begin
                d_mem_rdata <= d_mem[d_mem_req_addr[9:5]];
            end
            if (d_mem_req_write) begin
                d_mem[d_mem_req_addr[9:5]] <= d_mem_req_wdata;
            end
        end
    end

    initial begin
        i_mem[0] = make_line32(32'h1000_0000);
        d_mem[0] = make_line64(64'h2000_0000_0000_0000);

        rst_n = 1'b0;
        i_cpu_addr = 32'h0000_0000;
        d_cpu_mem_st_en = 1'b0;
        d_cpu_mem_ld_en = 1'b0;
        d_cpu_mem_addr = 12'h000;
        d_cpu_mem_byte_en = 4'b0000;
        d_cpu_mem_ld_sel = 3'h3;
        d_cpu_mem_st_data = '0;
        d_fpu_mem_ld_sel = 1'b0;
        d_fpu_mem_wren = 1'b0;
        d_fpu_mem_addr = 12'h000;
        d_fpu_mem_din = '0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        i_cpu_addr = 32'h0000_0000;
        wait_i_ready();
        if (i_cpu_rdata !== 32'h1000_0000) begin
            $fatal(1, "I fetch mismatch: got %h", i_cpu_rdata);
        end
        $display("NEW: I fetch pass");

        d_cpu_mem_addr = 12'h000;
        d_cpu_mem_ld_sel = 3'h3;
        d_cpu_mem_ld_en = 1'b1;
        wait_d_ready();
        if (d_cpu_mem_ld_data !== 64'h2000_0000_0000_0000) begin
            $fatal(1, "D load mismatch: got %h", d_cpu_mem_ld_data);
        end
        d_cpu_mem_ld_en = 1'b0;
        @(posedge clk);
        $display("NEW: D load pass");

        d_cpu_mem_addr = 12'h000;
        d_cpu_mem_byte_en = 4'b0111;
        d_cpu_mem_st_data = 64'hdead_beef_cafe_1234;
        d_cpu_mem_st_en = 1'b1;
        wait_d_ready();
        d_cpu_mem_st_en = 1'b0;
        @(posedge clk);

        d_cpu_mem_addr = 12'h000;
        d_cpu_mem_ld_sel = 3'h3;
        d_cpu_mem_ld_en = 1'b1;
        wait_d_ready();
        if (d_cpu_mem_ld_data !== 64'hdead_beef_cafe_1234) begin
            $fatal(1, "D load-after-store mismatch: got %h", d_cpu_mem_ld_data);
        end
        d_cpu_mem_ld_en = 1'b0;
        $display("NEW: D store/load pass");
        $display("NEW MMU TB PASS");
        $finish;
    end

endmodule
