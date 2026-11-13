`timescale 1ns / 1ps

// Executes one self-checking RISC-V ACT4 ELF image converted to arch_test.mem.
// Hart 0 starts at 0x1000; harts 1..3 park on JAL x0,0 at address zero so the
// actual quad-core/cache/interconnect hierarchy remains under test without
// allowing four copies of a single-hart architectural test to race.
module tb_riscv_arch_test;
    localparam CLK_PERIOD = 10;
    localparam MEM_WORDS  = 262144; // 1 MiB, word addressed by objcopy .mem
    localparam BOOT_ADDR  = 32'h0000_1000;
    localparam STATUS_ADDR = 32'hC000_0200;
    localparam CONSOLE_ADDR = 32'hC000_0204;
    localparam MAX_CYCLES = 2_000_000;

    reg clk = 1'b0;
    reg resetn = 1'b0;
    integer cycles = 0;
    integer errors = 0;
    integer i;
    reg done = 1'b0;
    reg [31:0] test_status = 32'b0;

    wire [31:0] awaddr, wdata, araddr;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize;
    wire [1:0] awburst, arburst;
    wire [3:0] wstrb;
    wire awvalid, wvalid, wlast, bready, arvalid, rready;
    wire awready, wready, arready;
    reg [1:0] bresp = 2'b00, rresp = 2'b00;
    reg bvalid = 1'b0, rvalid = 1'b0, rlast = 1'b0;
    reg [31:0] rdata = 32'b0;

    reg [31:0] memory [0:MEM_WORDS-1];
    reg read_pending = 1'b0;
    reg [31:0] read_addr = 32'b0;
    reg [7:0] read_len = 8'b0;
    reg [7:0] read_beat = 8'b0;
    reg aw_captured = 1'b0;
    reg [31:0] write_addr = 32'b0;
    reg [7:0] write_len = 8'b0;
    reg [7:0] write_beat = 8'b0;
    reg write_complete = 1'b0;

    wire unused_flush_busy, unused_flush_done, unused_flush_error;
    wire [31:0] unused_result0, unused_result1, unused_result2, unused_result3;
    wire unused_fetch_pf0, unused_fetch_pf1, unused_fetch_pf2, unused_fetch_pf3;
    wire unused_data_pf0, unused_data_pf1, unused_data_pf2, unused_data_pf3;

    quad_core_axi_wrapper_ahb #(
        .RESET_ADDR0(BOOT_ADDR), .RESET_ADDR1(32'h0),
        .RESET_ADDR2(32'h0), .RESET_ADDR3(32'h0),
        .MESI_ENABLE(1)
    ) dut (
        .ACLK(clk), .ARESETN(resetn),
        .Mmu_Flush(1'b0), .Cache_Flush(1'b0),
        .Cache_Flush_Busy(unused_flush_busy),
        .Cache_Flush_Done(unused_flush_done),
        .Cache_Flush_Error(unused_flush_error),
        .ResultW0(unused_result0), .ResultW1(unused_result1),
        .ResultW2(unused_result2), .ResultW3(unused_result3),
        .Fetch_PageFault0(unused_fetch_pf0), .Fetch_PageFault1(unused_fetch_pf1),
        .Fetch_PageFault2(unused_fetch_pf2), .Fetch_PageFault3(unused_fetch_pf3),
        .Data_PageFault0(unused_data_pf0), .Data_PageFault1(unused_data_pf1),
        .Data_PageFault2(unused_data_pf2), .Data_PageFault3(unused_data_pf3),
        .M_AXI_AWADDR(awaddr), .M_AXI_AWLEN(awlen),
        .M_AXI_AWSIZE(awsize), .M_AXI_AWBURST(awburst),
        .M_AXI_AWVALID(awvalid), .M_AXI_AWREADY(awready),
        .M_AXI_WDATA(wdata), .M_AXI_WSTRB(wstrb),
        .M_AXI_WVALID(wvalid), .M_AXI_WLAST(wlast), .M_AXI_WREADY(wready),
        .M_AXI_BRESP(bresp), .M_AXI_BVALID(bvalid), .M_AXI_BREADY(bready),
        .M_AXI_ARADDR(araddr), .M_AXI_ARLEN(arlen),
        .M_AXI_ARSIZE(arsize), .M_AXI_ARBURST(arburst),
        .M_AXI_ARVALID(arvalid), .M_AXI_ARREADY(arready),
        .M_AXI_RDATA(rdata), .M_AXI_RRESP(rresp),
        .M_AXI_RVALID(rvalid), .M_AXI_RLAST(rlast), .M_AXI_RREADY(rready)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    function in_ram;
        input [31:0] address;
        begin
            in_ram = (address < (MEM_WORDS * 4));
        end
    endfunction

    assign arready = resetn && !read_pending && !rvalid;
    assign awready = resetn && !aw_captured && !bvalid;
    assign wready  = resetn && aw_captured && !write_complete && !bvalid;

    always @(posedge clk) begin
        if (!resetn) begin
            cycles        <= 0;
            read_pending  <= 1'b0;
            rvalid        <= 1'b0;
            rlast         <= 1'b0;
            aw_captured   <= 1'b0;
            write_complete <= 1'b0;
            bvalid        <= 1'b0;
            done          <= 1'b0;
            test_status   <= 32'b0;
        end
        else begin
            cycles <= cycles + 1;

            if (arvalid && arready) begin
                read_pending <= 1'b1;
                read_addr    <= araddr;
                read_len     <= arlen;
                read_beat    <= 8'b0;
                if ((arlen != 8'd7) || (arsize != 3'b010) ||
                    (arburst != 2'b01)) begin
                    errors = errors + 1;
                    $display("[FAIL] illegal cached AXI read burst addr=%08x len=%0d", araddr, arlen);
                end
            end
            else if (read_pending && !rvalid) begin
                rdata  <= in_ram(read_addr + (read_beat << 2)) ?
                          memory[(read_addr >> 2) + read_beat] : 32'b0;
                rresp  <= in_ram(read_addr + (read_beat << 2)) ? 2'b00 : 2'b10;
                rlast  <= (read_beat == read_len);
                rvalid <= 1'b1;
            end
            if (rvalid && rready) begin
                rvalid <= 1'b0;
                if (rlast) begin
                    read_pending <= 1'b0;
                    read_beat <= 8'b0;
                end
                else
                    read_beat <= read_beat + 1'b1;
            end

            if (awvalid && awready) begin
                aw_captured <= 1'b1;
                write_addr  <= awaddr;
                write_len   <= awlen;
                write_beat  <= 8'b0;
                if ((awsize != 3'b010) || (awburst != 2'b01)) begin
                    errors = errors + 1;
                    $display("[FAIL] illegal AXI write attributes addr=%08x", awaddr);
                end
            end

            if (wvalid && wready) begin
                if (in_ram(write_addr + (write_beat << 2))) begin
                    if (wstrb[0]) memory[(write_addr >> 2) + write_beat][7:0]   <= wdata[7:0];
                    if (wstrb[1]) memory[(write_addr >> 2) + write_beat][15:8]  <= wdata[15:8];
                    if (wstrb[2]) memory[(write_addr >> 2) + write_beat][23:16] <= wdata[23:16];
                    if (wstrb[3]) memory[(write_addr >> 2) + write_beat][31:24] <= wdata[31:24];
                end
                else if ((write_addr == STATUS_ADDR) && (write_len == 0)) begin
                    test_status <= wdata;
                    done <= 1'b1;
                end
                else if ((write_addr == CONSOLE_ADDR) && (write_len == 0)) begin
                    $write("%c", wdata[7:0]);
                end
                else begin
                    errors = errors + 1;
                    $display("[FAIL] unsupported MMIO write addr=%08x data=%08x", write_addr, wdata);
                end

                if (wlast) begin
                    if (write_beat != write_len) begin
                        errors = errors + 1;
                        $display("[FAIL] WLAST beat=%0d expected=%0d", write_beat, write_len);
                    end
                    write_complete <= 1'b1;
                end
                else
                    write_beat <= write_beat + 1'b1;
            end

            if (aw_captured && write_complete && !bvalid) begin
                bresp  <= (in_ram(write_addr) || (write_addr == STATUS_ADDR) ||
                           (write_addr == CONSOLE_ADDR)) ? 2'b00 : 2'b10;
                bvalid <= 1'b1;
            end
            if (bvalid && bready) begin
                bvalid         <= 1'b0;
                aw_captured    <= 1'b0;
                write_complete <= 1'b0;
            end
        end
    end

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1)
            memory[i] = 32'b0;
        // Parking loop for harts 1..3. ACT image begins at 0x1000.
        memory[0] = 32'h0000_006F;
        $readmemh("arch_test.mem", memory);

        repeat (8) @(posedge clk);
        resetn = 1'b1;

        wait (done || (cycles >= MAX_CYCLES));
        repeat (8) @(posedge clk);
        if (!done) begin
            $display("RISCV_ARCH_TEST_TB: FAIL (timeout after %0d cycles)", cycles);
        end
        else if ((test_status == 32'd1) && (errors == 0)) begin
            $display("RISCV_ARCH_TEST_TB: PASS cycles=%0d", cycles);
        end
        else begin
            $display("RISCV_ARCH_TEST_TB: FAIL status=%08x errors=%0d cycles=%0d",
                     test_status, errors, cycles);
        end
        $finish;
    end
endmodule
