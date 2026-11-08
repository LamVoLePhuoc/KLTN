`timescale 1ns / 1ps

// End-to-end regression for the source-level DMA subsystem.  It exercises
// APB programming, cache-maintenance ordering, 4 KiB/burst splitting,
// data copying, read/write error propagation, and watchdog drain safety.
module tb_dma_end_to_end;
    localparam CLK_PERIOD = 10;
    localparam MEM_WORDS  = 4096;

    reg clk;
    reg rst;
    reg buffer_quiesced;

    wire cache_flush;
    reg  cache_flush_busy;
    reg  cache_flush_done;
    reg  cache_flush_error;

    reg  [5:0]  paddr;
    reg         psel;
    reg         penable;
    reg         pwrite;
    reg  [31:0] pwdata;
    reg  [3:0]  pstrb;
    reg  [2:0]  pprot;
    wire [31:0] prdata;
    wire        pready;
    wire        pslverr;

    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rlast;
    wire        m_axi_rvalid;
    wire        m_axi_rready;
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    wire        m_axi_awready;
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    wire        m_axi_wready;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    wire        m_axi_bready;

    wire       status_busy;
    wire       status_done;
    wire       status_error;
    wire [2:0] status_error_code;

    reg [31:0] memory [0:MEM_WORDS-1];
    reg        read_active;
    reg [31:0] read_addr;
    reg [8:0]  read_beats_left;
    reg        write_active;
    reg [31:0] write_addr;
    reg [8:0]  write_beats_left;
    reg        bvalid_r;
    reg [1:0]  bresp_r;

    reg inject_read_error;
    reg inject_write_error;
    reg inject_flush_error;
    integer flush_delay_cfg;
    integer flush_countdown;
    integer flush_count;
    integer read_burst_count;
    integer write_burst_count;
    integer errors;
    integer i;
    integer before_count;
    integer before_writes;
    integer before_reads;
    integer wait_cycles;
    reg [31:0] apb_read_value;

    assign m_axi_arready = !read_active;
    assign m_axi_rvalid  = read_active;
    assign m_axi_rdata   = memory[read_addr[13:2]];
    assign m_axi_rresp   = inject_read_error ? 2'b10 : 2'b00;
    assign m_axi_rlast   = read_active && (read_beats_left == 1);

    assign m_axi_awready = !write_active && !bvalid_r;
    assign m_axi_wready  = write_active;
    assign m_axi_bvalid  = bvalid_r;
    assign m_axi_bresp   = bresp_r;

    soc_dma_controller #(
        .MAX_BURST_LEN(4),
        .TIMEOUT_CYCLES(16)
    ) dut (
        .clk(clk), .rst(rst), .buffer_quiesced(buffer_quiesced),
        .cache_flush(cache_flush), .cache_flush_busy(cache_flush_busy),
        .cache_flush_done(cache_flush_done),
        .cache_flush_error(cache_flush_error),
        .paddr(paddr), .psel(psel), .penable(penable), .pwrite(pwrite),
        .pwdata(pwdata), .pstrb(pstrb), .pprot(pprot),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready), .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .status_busy(status_busy), .status_done(status_done),
        .status_error(status_error),
        .status_error_code(status_error_code)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // Minimal AXI4 memory slave.  The assertions here also verify that every
    // burst stays within the configured four-beat limit and a 4 KiB boundary.
    always @(posedge clk) begin
        if (rst) begin
            read_active      <= 1'b0;
            read_addr        <= 32'd0;
            read_beats_left  <= 9'd0;
            write_active     <= 1'b0;
            write_addr       <= 32'd0;
            write_beats_left <= 9'd0;
            bvalid_r         <= 1'b0;
            bresp_r          <= 2'b00;
            read_burst_count <= 0;
            write_burst_count <= 0;
        end
        else begin
            if (m_axi_arvalid && m_axi_arready) begin
                read_active      <= 1'b1;
                read_addr        <= m_axi_araddr;
                read_beats_left  <= {1'b0, m_axi_arlen} + 9'd1;
                read_burst_count <= read_burst_count + 1;
                if ((m_axi_arburst != 2'b01) || (m_axi_arsize != 3'd2) ||
                    (m_axi_arlen >= 8'd4) ||
                    ({1'b0, m_axi_araddr[11:0]} +
                     (({5'd0, m_axi_arlen} + 13'd1) << m_axi_arsize) > 13'd4096)) begin
                    $display("[FAIL] illegal AXI read burst addr=%08x len=%0d",
                             m_axi_araddr, m_axi_arlen + 1);
                    errors = errors + 1;
                end
            end
            else if (read_active && m_axi_rready) begin
                if (read_beats_left == 1) begin
                    read_active <= 1'b0;
                    read_beats_left <= 9'd0;
                end
                else begin
                    read_addr <= read_addr + 32'd4;
                    read_beats_left <= read_beats_left - 9'd1;
                end
            end

            if (m_axi_awvalid && m_axi_awready) begin
                write_active      <= 1'b1;
                write_addr        <= m_axi_awaddr;
                write_beats_left  <= {1'b0, m_axi_awlen} + 9'd1;
                write_burst_count <= write_burst_count + 1;
                if ((m_axi_awburst != 2'b01) || (m_axi_awsize != 3'd2) ||
                    (m_axi_awlen >= 8'd4) ||
                    ({1'b0, m_axi_awaddr[11:0]} +
                     (({5'd0, m_axi_awlen} + 13'd1) << m_axi_awsize) > 13'd4096)) begin
                    $display("[FAIL] illegal AXI write burst addr=%08x len=%0d",
                             m_axi_awaddr, m_axi_awlen + 1);
                    errors = errors + 1;
                end
            end

            if (write_active && m_axi_wvalid) begin
                if (m_axi_wstrb[0]) memory[write_addr[13:2]][7:0]   <= m_axi_wdata[7:0];
                if (m_axi_wstrb[1]) memory[write_addr[13:2]][15:8]  <= m_axi_wdata[15:8];
                if (m_axi_wstrb[2]) memory[write_addr[13:2]][23:16] <= m_axi_wdata[23:16];
                if (m_axi_wstrb[3]) memory[write_addr[13:2]][31:24] <= m_axi_wdata[31:24];

                if (m_axi_wlast != (write_beats_left == 1)) begin
                    $display("[FAIL] WLAST at wrong beat");
                    errors = errors + 1;
                end

                if (write_beats_left == 1) begin
                    write_active <= 1'b0;
                    write_beats_left <= 9'd0;
                    bvalid_r <= 1'b1;
                    bresp_r <= inject_write_error ? 2'b10 : 2'b00;
                end
                else begin
                    write_addr <= write_addr + 32'd4;
                    write_beats_left <= write_beats_left - 9'd1;
                end
            end

            if (bvalid_r && m_axi_bready)
                bvalid_r <= 1'b0;
        end
    end

    // Cache-maintenance responder with a programmable delay.  Error is valid
    // with done, matching the aggregate cache-maintenance interface.
    always @(posedge clk) begin
        if (rst) begin
            cache_flush_busy <= 1'b0;
            cache_flush_done <= 1'b0;
            cache_flush_error <= 1'b0;
            flush_countdown <= 0;
            flush_count <= 0;
        end
        else begin
            cache_flush_done <= 1'b0;
            cache_flush_error <= 1'b0;
            if (cache_flush && !cache_flush_busy) begin
                cache_flush_busy <= 1'b1;
                flush_countdown <= flush_delay_cfg;
                flush_count <= flush_count + 1;
            end
            else if (cache_flush_busy) begin
                if (flush_countdown <= 1) begin
                    cache_flush_busy <= 1'b0;
                    cache_flush_done <= 1'b1;
                    cache_flush_error <= inject_flush_error;
                    flush_countdown <= 0;
                end
                else
                    flush_countdown <= flush_countdown - 1;
            end
        end
    end

    task apb_write;
        input [5:0] address;
        input [31:0] value;
        begin
            @(negedge clk);
            paddr   = address;
            pwrite  = 1'b1;
            pwdata  = value;
            pstrb   = 4'hf;
            psel    = 1'b1;
            penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            while (!pready)
                @(negedge clk);
            if (pslverr) begin
                $display("[FAIL] APB write response at %02x", address);
                errors = errors + 1;
            end
            @(negedge clk);
            psel    = 1'b0;
            penable = 1'b0;
            pwrite  = 1'b0;
        end
    endtask

    task clear_status;
        begin
            apb_write(6'h00, 32'h0000_0002);
        end
    endtask

    task apb_read;
        input [5:0] address;
        output [31:0] value;
        begin
            @(negedge clk);
            paddr   = address;
            pwrite  = 1'b0;
            psel    = 1'b1;
            penable = 1'b0;
            @(negedge clk);
            penable = 1'b1;
            while (!pready)
                @(negedge clk);
            value = prdata;
            if (pslverr) begin
                $display("[FAIL] APB read response at %02x", address);
                errors = errors + 1;
            end
            @(negedge clk);
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    task start_transfer;
        input [31:0] source;
        input [31:0] destination;
        input [31:0] length_bytes;
        begin
            clear_status;
            apb_write(6'h08, source);
            apb_write(6'h0c, destination);
            apb_write(6'h10, length_bytes);
            apb_write(6'h00, 32'h0000_0001);
        end
    endtask

    task wait_for_done;
        begin
            wait_cycles = 0;
            while (!status_done && (wait_cycles < 1000)) begin
                @(posedge clk);
                wait_cycles = wait_cycles + 1;
            end
            if (!status_done) begin
                $display("[FAIL] DMA completion timeout");
                errors = errors + 1;
            end
            @(posedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        buffer_quiesced = 1'b1;
        paddr = 6'd0;
        psel = 1'b0;
        penable = 1'b0;
        pwrite = 1'b0;
        pwdata = 32'd0;
        pstrb = 4'hf;
        pprot = 3'd0;
        inject_read_error = 1'b0;
        inject_write_error = 1'b0;
        inject_flush_error = 1'b0;
        flush_delay_cfg = 2;
        errors = 0;
        for (i = 0; i < MEM_WORDS; i = i + 1)
            memory[i] = 32'hca00_0000 + i;

        repeat (5) @(posedge clk);
        rst = 1'b0;

        // Verify the APB4 control plane independently of the AXI datapath.
        apb_write(6'h08, 32'h1234_5678);
        apb_read(6'h08, apb_read_value);
        if (apb_read_value !== 32'h1234_5678) begin
            $display("[FAIL] APB SRC_ADDR readback: %08x", apb_read_value);
            errors = errors + 1;
        end

        // A pending software start must not reach cache or AXI until the
        // software/producer declares the DMA buffers quiescent.
        buffer_quiesced = 1'b0;
        before_count = flush_count;
        start_transfer(32'h0000_0ff0, 32'h0000_1fe0, 32'd96);
        repeat (8) @(posedge clk);
        if (!status_busy || (flush_count != before_count) ||
            (read_burst_count != 0)) begin
            $display("[FAIL] buffer_quiesced gate");
            errors = errors + 1;
        end
        buffer_quiesced = 1'b1;
        wait_for_done;
        if (status_error || (flush_count != before_count + 2)) begin
            $display("[FAIL] successful DMA status/flush ordering: error=%0b code=%0d flushes=%0d expected=%0d",
                     status_error, status_error_code, flush_count,
                     before_count + 2);
            errors = errors + 1;
        end
        for (i = 0; i < 24; i = i + 1) begin
            if (memory[(32'h1fe0 >> 2) + i] !==
                memory[(32'h0ff0 >> 2) + i]) begin
                $display("[FAIL] copy word %0d", i);
                errors = errors + 1;
            end
        end

        // A source read error must not issue any destination write burst.
        before_count = flush_count;
        before_writes = write_burst_count;
        for (i = 0; i < 4; i = i + 1)
            memory[(32'h2400 >> 2) + i] = 32'hdead_beef;
        inject_read_error = 1'b1;
        start_transfer(32'h0000_0200, 32'h0000_2400, 32'd16);
        wait_for_done;
        inject_read_error = 1'b0;
        if (!status_error || (status_error_code != 3'd2) ||
            (write_burst_count != before_writes) ||
            (flush_count != before_count + 2)) begin
            $display("[FAIL] read-error propagation/suppression");
            errors = errors + 1;
        end
        for (i = 0; i < 4; i = i + 1)
            if (memory[(32'h2400 >> 2) + i] !== 32'hdead_beef) begin
                $display("[FAIL] read error modified destination word %0d", i);
                errors = errors + 1;
            end

        // Misaligned byte counts are rejected before any AXI memory request.
        before_count = flush_count;
        before_reads = read_burst_count;
        before_writes = write_burst_count;
        start_transfer(32'h0000_0200, 32'h0000_2400, 32'd6);
        wait_for_done;
        if (!status_error || (status_error_code != 3'd2) ||
            (read_burst_count != before_reads) ||
            (write_burst_count != before_writes) ||
            (flush_count != before_count + 2)) begin
            $display("[FAIL] unaligned command rejection");
            errors = errors + 1;
        end

        // A write response error still requires post-DMA maintenance.
        before_count = flush_count;
        inject_write_error = 1'b1;
        start_transfer(32'h0000_0300, 32'h0000_2500, 32'd16);
        wait_for_done;
        inject_write_error = 1'b0;
        if (!status_error || (status_error_code != 3'd2) ||
            (flush_count != before_count + 2)) begin
            $display("[FAIL] write-error post-flush");
            errors = errors + 1;
        end

        // Watchdog expiry is diagnostic only.  The request remains busy until
        // the delayed pre-flush really completes, and no DMA read may start.
        flush_delay_cfg = 24;
        before_reads = read_burst_count;
        before_count = flush_count;
        start_transfer(32'h0000_0400, 32'h0000_2600, 32'd16);
        repeat (18) @(posedge clk);
        if (status_done || !status_busy || (read_burst_count != before_reads)) begin
            $display("[FAIL] watchdog fabricated safe completion");
            errors = errors + 1;
        end
        wait_for_done;
        if (!status_error || (status_error_code != 3'd4) ||
            (read_burst_count != before_reads) ||
            (flush_count != before_count + 1)) begin
            $display("[FAIL] watchdog diagnostic result");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("DMA_END_TO_END_TB: PASS");
        else
            $display("DMA_END_TO_END_TB: FAIL (%0d checks failed)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 5000);
        $display("DMA_END_TO_END_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
