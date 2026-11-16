`timescale 1ns / 1ps

// A compiled, shared-image four-hart workload.  The program is built from
// sw/workloads/quad_cache_{crt0.S,workload.c}; all harts start at 0x1000 and
// use mhartid to select private data and their ordered coherence phase.
//
// The test deliberately terminates through uncached MMIO signatures instead
// of inspecting cached memory.  This avoids turning a dirty-cache visibility
// artifact into a false workload pass.
module tb_quad_core_compiled_workload #(
    parameter MESI_ENABLE = 1,
    parameter integer CLK_PERIOD = 10
);
    localparam MEM_WORDS  = 16384;
    localparam BOOT_ADDR  = 32'h0000_1000;
    localparam SIG_BASE   = 32'hC000_0100;
    localparam ETOM_BASE  = 32'h0000_7000;
    localparam ETOM_LIMIT = 32'h0000_7080;
    localparam MAX_CYCLES = 500_000;

    reg clk;
    reg resetn;
    reg mmu_flush;
    reg cache_flush;
    wire cache_flush_busy, cache_flush_done, cache_flush_error;
    wire [31:0] result_w0, result_w1, result_w2, result_w3;
    wire fetch_pf0, fetch_pf1, fetch_pf2, fetch_pf3;
    wire data_pf0, data_pf1, data_pf2, data_pf3;

    wire [31:0] awaddr, wdata, araddr;
    wire [7:0] awlen, arlen;
    wire [2:0] awsize, arsize;
    wire [1:0] awburst, arburst;
    wire [3:0] wstrb;
    wire awvalid, wvalid, wlast, bready, arvalid, rready;
    wire awready, wready, arready;
    reg [1:0] bresp, rresp;
    reg bvalid, rvalid, rlast;
    reg [31:0] rdata;

    reg [31:0] memory [0:MEM_WORDS-1];
    reg [31:0] signature [0:3];
    reg [3:0]  signature_seen;
    integer i;
    integer errors;
    integer cycles;

    // AXI memory-model state and traffic counters.
    reg        read_pending;
    reg [31:0] read_addr;
    reg [7:0]  read_len;
    reg [7:0]  read_beat;
    integer    read_delay;
    reg        aw_captured;
    reg [31:0] write_addr;
    reg [7:0]  write_len;
    reg [7:0]  write_beat;
    reg        w_captured;
    reg [31:0] write_data;
    integer    write_delay;

    integer axi_read_transactions;
    integer axi_write_transactions;
    integer axi_read_beats;
    integer axi_write_beats;
    integer axi_burst_reads;
    integer axi_burst_writes;
    integer ahb_transfer_cycles;
    integer ahb_occupied_cycles;
    integer etom_read_requests;
    integer etom_rfo_requests;
    integer etom_s_grants;
    integer etom_e_grants;
    reg     first_controller_error_seen;

    reg [63:0] total_retired;
    reg [63:0] total_l1_accesses;
    reg [63:0] total_l1_hits;
    reg [63:0] total_l1_misses;
    reg [63:0] ipc_milli;
    reg [63:0] miss_rate_ppm;
    reg [63:0] ahb_util_ppm;

    quad_core_axi_wrapper_ahb #(
        .RESET_ADDR0(BOOT_ADDR), .RESET_ADDR1(BOOT_ADDR),
        .RESET_ADDR2(BOOT_ADDR), .RESET_ADDR3(BOOT_ADDR),
        .MESI_ENABLE(MESI_ENABLE)
    ) dut (
        .ACLK(clk), .ARESETN(resetn),
        .Mmu_Flush(mmu_flush), .Cache_Flush(cache_flush),
        .Cache_Flush_Busy(cache_flush_busy),
        .Cache_Flush_Done(cache_flush_done),
        .Cache_Flush_Error(cache_flush_error),
        .ResultW0(result_w0), .ResultW1(result_w1),
        .ResultW2(result_w2), .ResultW3(result_w3),
        .Fetch_PageFault0(fetch_pf0), .Fetch_PageFault1(fetch_pf1),
        .Fetch_PageFault2(fetch_pf2), .Fetch_PageFault3(fetch_pf3),
        .Data_PageFault0(data_pf0), .Data_PageFault1(data_pf1),
        .Data_PageFault2(data_pf2), .Data_PageFault3(data_pf3),
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

    // Deterministic throttling creates reproducible backpressure while still
    // allowing SAIF/power runs to compare MSI and MESI with identical memory.
    assign arready = resetn && !read_pending && !rvalid && (cycles[1:0] != 2'b00);
    assign awready = resetn && !aw_captured && !bvalid && cycles[0];
    assign wready  = resetn && aw_captured && !w_captured && !bvalid && cycles[1];

    function is_signature_address;
        input [31:0] address;
        begin
            is_signature_address = (address >= SIG_BASE) &&
                                   (address < (SIG_BASE + 32'd16)) &&
                                   (address[1:0] == 2'b00);
        end
    endfunction

    function is_etom_line;
        input [31:0] address;
        begin
            is_etom_line = (address >= ETOM_BASE) &&
                           (address < ETOM_LIMIT) &&
                           (address[4:0] == 5'b0);
        end
    endfunction

    always @(posedge clk) begin
        if (!resetn) begin
            cycles                 <= 0;
            read_pending           <= 1'b0;
            read_addr              <= 32'b0;
            read_len               <= 8'b0;
            read_beat              <= 8'b0;
            read_delay             <= 0;
            rvalid                 <= 1'b0;
            rdata                  <= 32'b0;
            rresp                  <= 2'b00;
            rlast                  <= 1'b0;
            aw_captured            <= 1'b0;
            write_addr             <= 32'b0;
            write_len              <= 8'b0;
            write_beat             <= 8'b0;
            w_captured             <= 1'b0;
            write_data             <= 32'b0;
            write_delay            <= -1;
            bvalid                 <= 1'b0;
            bresp                  <= 2'b00;
            axi_read_transactions  <= 0;
            axi_write_transactions <= 0;
            axi_read_beats         <= 0;
            axi_write_beats        <= 0;
            axi_burst_reads        <= 0;
            axi_burst_writes       <= 0;
            ahb_transfer_cycles    <= 0;
            ahb_occupied_cycles    <= 0;
            etom_read_requests     <= 0;
            etom_rfo_requests      <= 0;
            etom_s_grants          <= 0;
            etom_e_grants          <= 0;
            first_controller_error_seen <= 1'b0;
            signature_seen         <= 4'b0;
            for (i = 0; i < 4; i = i + 1)
                signature[i] <= 32'b0;
        end
        else begin
            cycles <= cycles + 1;

            if (dut.soc.shared_htrans[1] && dut.soc.shared_hready)
                ahb_transfer_cycles <= ahb_transfer_cycles + 1;
            if (dut.soc.shared_htrans != 2'b00)
                ahb_occupied_cycles <= ahb_occupied_cycles + 1;

            // Count accepted controller transactions only, not the cycles for
            // which a blocking L1 holds valid high. Source IDs 0..3 are D$.
            if (dut.soc.shared_req_valid && dut.soc.shared_req_ready &&
                !dut.soc.ahb_grant_source[2] &&
                is_etom_line(dut.soc.shared_req_addr)) begin
                if (dut.soc.shared_req_type == 2'b00)
                    etom_read_requests <= etom_read_requests + 1;
                else if (dut.soc.shared_req_type == 2'b01)
                    etom_rfo_requests <= etom_rfo_requests + 1;
            end

            // The read response proves which stable state was installed. The
            // request address/type remain held by the blocking D$ until this
            // response pulse, so RFO responses cannot be miscounted as grants.
            if (dut.soc.core0.dbus_resp_valid &&
                (dut.soc.core0.dbus_req_type == 2'b00) &&
                is_etom_line(dut.soc.core0.dbus_req_addr)) begin
                if (dut.soc.core0.dbus_resp_state == 2'b01)
                    etom_s_grants <= etom_s_grants + 1;
                else if (dut.soc.core0.dbus_resp_state == 2'b10)
                    etom_e_grants <= etom_e_grants + 1;
            end
            if (dut.soc.core1.dbus_resp_valid &&
                (dut.soc.core1.dbus_req_type == 2'b00) &&
                is_etom_line(dut.soc.core1.dbus_req_addr)) begin
                if (dut.soc.core1.dbus_resp_state == 2'b01)
                    etom_s_grants <= etom_s_grants + 1;
                else if (dut.soc.core1.dbus_resp_state == 2'b10)
                    etom_e_grants <= etom_e_grants + 1;
            end
            if (dut.soc.core2.dbus_resp_valid &&
                (dut.soc.core2.dbus_req_type == 2'b00) &&
                is_etom_line(dut.soc.core2.dbus_req_addr)) begin
                if (dut.soc.core2.dbus_resp_state == 2'b01)
                    etom_s_grants <= etom_s_grants + 1;
                else if (dut.soc.core2.dbus_resp_state == 2'b10)
                    etom_e_grants <= etom_e_grants + 1;
            end
            if (dut.soc.core3.dbus_resp_valid &&
                (dut.soc.core3.dbus_req_type == 2'b00) &&
                is_etom_line(dut.soc.core3.dbus_req_addr)) begin
                if (dut.soc.core3.dbus_resp_state == 2'b01)
                    etom_s_grants <= etom_s_grants + 1;
                else if (dut.soc.core3.dbus_resp_state == 2'b10)
                    etom_e_grants <= etom_e_grants + 1;
            end


            if (arvalid && arready) begin
                read_pending <= 1'b1;
                read_addr    <= araddr;
                read_len     <= arlen;
                read_beat    <= 8'b0;
                read_delay   <= 1;
                axi_read_transactions <= axi_read_transactions + 1;
                if (arlen == 8'd7 && arsize == 3'b010 && arburst == 2'b01)
                    axi_burst_reads <= axi_burst_reads + 1;
                else begin
                    errors = errors + 1;
                    $display("[FAIL] cached AXI read is not LEN=7/SIZE=4/INCR addr=%08x", araddr);
                end
            end
            else if (read_pending && read_delay > 0)
                read_delay <= read_delay - 1;
            else if (read_pending && !rvalid) begin
                if (read_addr[31:16] == 16'b0) begin
                    rdata <= memory[read_addr[15:2] + read_beat];
                    rresp <= 2'b00;
                end
                else begin
                    rdata <= 32'b0;
                    rresp <= 2'b10;
                end
                rlast  <= (read_beat == read_len);
                rvalid <= 1'b1;
            end
            if (rvalid && rready) begin
                rvalid <= 1'b0;
                axi_read_beats <= axi_read_beats + 1;
                if (rlast) begin
                    read_pending <= 1'b0;
                    read_beat <= 8'b0;
                end
                else begin
                    read_beat <= read_beat + 8'd1;
                    read_delay <= cycles[0];
                end
            end

            if (awvalid && awready) begin
                aw_captured <= 1'b1;
                write_addr  <= awaddr;
                write_len   <= awlen;
                write_beat  <= 8'b0;
                if (is_signature_address(awaddr)) begin
                    if (awlen != 0 || awsize != 3'b010 || awburst != 2'b01) begin
                        errors = errors + 1;
                        $display("[FAIL] MMIO signature must be a single AXI beat addr=%08x", awaddr);
                    end
                end
                else if (awlen == 8'd7 && awsize == 3'b010 && awburst == 2'b01)
                    axi_burst_writes <= axi_burst_writes + 1;
                else begin
                    errors = errors + 1;
                    $display("[FAIL] cached AXI write is not LEN=7/SIZE=4/INCR addr=%08x", awaddr);
                end
            end
            if (wvalid && wready) begin
                if (write_addr[31:16] == 16'b0) begin
                    if (wstrb[0]) memory[write_addr[15:2] + write_beat][7:0]   <= wdata[7:0];
                    if (wstrb[1]) memory[write_addr[15:2] + write_beat][15:8]  <= wdata[15:8];
                    if (wstrb[2]) memory[write_addr[15:2] + write_beat][23:16] <= wdata[23:16];
                    if (wstrb[3]) memory[write_addr[15:2] + write_beat][31:24] <= wdata[31:24];
                end
                axi_write_beats <= axi_write_beats + 1;
                write_data <= wdata;
                if (wlast) begin
                    w_captured <= 1'b1;
                    if (write_beat != write_len) begin
                        errors = errors + 1;
                        $display("[FAIL] AXI WLAST beat=%0d expected=%0d", write_beat, write_len);
                    end
                end
                else
                    write_beat <= write_beat + 8'd1;
            end
            if (aw_captured && w_captured && (write_delay < 0))
                write_delay <= 1;
            else if (write_delay > 0)
                write_delay <= write_delay - 1;
            else if ((write_delay == 0) && !bvalid) begin
                bresp <= ((write_addr[31:16] == 16'b0) ||
                          is_signature_address(write_addr)) ? 2'b00 : 2'b10;
                bvalid <= 1'b1;
                write_delay <= -1;
                axi_write_transactions <= axi_write_transactions + 1;
                if (is_signature_address(write_addr)) begin
                    signature[(write_addr - SIG_BASE) >> 2] <= write_data;
                    signature_seen[(write_addr - SIG_BASE) >> 2] <= 1'b1;
                    $display("WORKLOAD_SIGNATURE hart=%0d value=%08x cycle=%0d",
                             (write_addr - SIG_BASE) >> 2, write_data, cycles);
                end
            end
            if (bvalid && bready) begin
                bvalid      <= 1'b0;
                aw_captured <= 1'b0;
                w_captured  <= 1'b0;
                write_beat  <= 8'b0;
                write_delay <= -1;
            end

            if ({fetch_pf3, fetch_pf2, fetch_pf1, fetch_pf0} != 4'b0 ||
                {data_pf3, data_pf2, data_pf1, data_pf0} != 4'b0) begin
                errors = errors + 1;
                $display("[FAIL] unexpected page-fault output in physical-only workload");
            end

            if (!first_controller_error_seen &&
                (dut.soc.cache_protocol_error || dut.soc.cache_timeout_error ||
                 dut.soc.cache_memory_error)) begin
                first_controller_error_seen <= 1'b1;
                $display("WORKLOAD_FIRST_ERROR cycle=%0d protocol=%b timeout=%b memory=%b state=%0d req_addr=%08x pc=%08x/%08x/%08x/%08x x9=%08x/%08x/%08x/%08x x10=%08x/%08x/%08x/%08x x19=%08x/%08x/%08x/%08x",
                         cycles, dut.soc.cache_protocol_error,
                         dut.soc.cache_timeout_error, dut.soc.cache_memory_error,
                         dut.soc.u_cache_controller_mmu.state,
                         dut.soc.u_cache_controller_mmu.req_addr,
                         dut.soc.core0.PCF, dut.soc.core1.PCF,
                         dut.soc.core2.PCF, dut.soc.core3.PCF,
                         dut.soc.core0.physical_core.core.decode_unit.rf.Register[9],
                         dut.soc.core1.physical_core.core.decode_unit.rf.Register[9],
                         dut.soc.core2.physical_core.core.decode_unit.rf.Register[9],
                         dut.soc.core3.physical_core.core.decode_unit.rf.Register[9],
                         dut.soc.core0.physical_core.core.decode_unit.rf.Register[10],
                         dut.soc.core1.physical_core.core.decode_unit.rf.Register[10],
                         dut.soc.core2.physical_core.core.decode_unit.rf.Register[10],
                         dut.soc.core3.physical_core.core.decode_unit.rf.Register[10],
                         dut.soc.core0.physical_core.core.decode_unit.rf.Register[19],
                         dut.soc.core1.physical_core.core.decode_unit.rf.Register[19],
                         dut.soc.core2.physical_core.core.decode_unit.rf.Register[19],
                         dut.soc.core3.physical_core.core.decode_unit.rf.Register[19]);
            end
        end
    end

    task report_statistics;
        begin
            total_retired = dut.soc.core0.physical_core.core.perf_retired_instructions +
                            dut.soc.core1.physical_core.core.perf_retired_instructions +
                            dut.soc.core2.physical_core.core.perf_retired_instructions +
                            dut.soc.core3.physical_core.core.perf_retired_instructions;
            total_l1_accesses = dut.soc.core0.u_dcache.perf_cpu_accesses +
                                dut.soc.core1.u_dcache.perf_cpu_accesses +
                                dut.soc.core2.u_dcache.perf_cpu_accesses +
                                dut.soc.core3.u_dcache.perf_cpu_accesses;
            total_l1_hits = dut.soc.core0.u_dcache.perf_l1_hits +
                            dut.soc.core1.u_dcache.perf_l1_hits +
                            dut.soc.core2.u_dcache.perf_l1_hits +
                            dut.soc.core3.u_dcache.perf_l1_hits;
            total_l1_misses = dut.soc.core0.u_dcache.perf_l1_misses +
                              dut.soc.core1.u_dcache.perf_l1_misses +
                              dut.soc.core2.u_dcache.perf_l1_misses +
                              dut.soc.core3.u_dcache.perf_l1_misses;
            ipc_milli = (cycles != 0) ? ((total_retired * 1000) / cycles) : 0;
            miss_rate_ppm = (total_l1_accesses != 0) ?
                            ((total_l1_misses * 1_000_000) / total_l1_accesses) : 0;
            ahb_util_ppm = (cycles != 0) ?
                           ((ahb_occupied_cycles * 1_000_000) / cycles) : 0;

            if (MESI_ENABLE)
                $display("QUAD_WORKLOAD_STATS protocol=MESI cycles=%0d retired=%0d ipc_milli=%0d l1_accesses=%0d l1_hits=%0d l1_misses=%0d miss_rate_ppm=%0d ahb_transfer_cycles=%0d ahb_occupied_cycles=%0d ahb_util_ppm=%0d axi_read_txn=%0d axi_write_txn=%0d axi_read_beats=%0d axi_write_beats=%0d axi_burst_reads=%0d axi_burst_writes=%0d d_reads=%0d rfos=%0d writebacks=%0d l2_hits=%0d l2_misses=%0d snoops=%0d controller_busy_cycles=%0d etom_reads=%0d etom_rfos=%0d etom_s_grants=%0d etom_e_grants=%0d",
                         cycles, total_retired, ipc_milli, total_l1_accesses,
                         total_l1_hits, total_l1_misses, miss_rate_ppm,
                         ahb_transfer_cycles, ahb_occupied_cycles, ahb_util_ppm,
                         axi_read_transactions, axi_write_transactions,
                         axi_read_beats, axi_write_beats,
                         axi_burst_reads, axi_burst_writes,
                         dut.soc.cache_perf_d_bus_reads,
                         dut.soc.cache_perf_d_rfos,
                         dut.soc.cache_perf_d_writebacks,
                         dut.soc.cache_perf_l2_hits, dut.soc.cache_perf_l2_misses,
                         dut.soc.cache_perf_snoop_requests,
                         dut.soc.cache_perf_busy_cycles,
                         etom_read_requests, etom_rfo_requests,
                         etom_s_grants, etom_e_grants);
            else
                $display("QUAD_WORKLOAD_STATS protocol=MSI cycles=%0d retired=%0d ipc_milli=%0d l1_accesses=%0d l1_hits=%0d l1_misses=%0d miss_rate_ppm=%0d ahb_transfer_cycles=%0d ahb_occupied_cycles=%0d ahb_util_ppm=%0d axi_read_txn=%0d axi_write_txn=%0d axi_read_beats=%0d axi_write_beats=%0d axi_burst_reads=%0d axi_burst_writes=%0d d_reads=%0d rfos=%0d writebacks=%0d l2_hits=%0d l2_misses=%0d snoops=%0d controller_busy_cycles=%0d etom_reads=%0d etom_rfos=%0d etom_s_grants=%0d etom_e_grants=%0d",
                         cycles, total_retired, ipc_milli, total_l1_accesses,
                         total_l1_hits, total_l1_misses, miss_rate_ppm,
                         ahb_transfer_cycles, ahb_occupied_cycles, ahb_util_ppm,
                         axi_read_transactions, axi_write_transactions,
                         axi_read_beats, axi_write_beats,
                         axi_burst_reads, axi_burst_writes,
                         dut.soc.cache_perf_d_bus_reads,
                         dut.soc.cache_perf_d_rfos,
                         dut.soc.cache_perf_d_writebacks,
                         dut.soc.cache_perf_l2_hits, dut.soc.cache_perf_l2_misses,
                         dut.soc.cache_perf_snoop_requests,
                         dut.soc.cache_perf_busy_cycles,
                         etom_read_requests, etom_rfo_requests,
                         etom_s_grants, etom_e_grants);
        end
    endtask

    initial begin
        clk = 1'b0;
        resetn = 1'b0;
        mmu_flush = 1'b0;
        cache_flush = 1'b0;
        errors = 0;

        for (i = 0; i < MEM_WORDS; i = i + 1)
            memory[i] = 32'b0;
        $readmemh("quad_cache_workload.mem", memory);

        repeat (8) @(posedge clk);
        @(negedge clk); resetn = 1'b1;

        while ((signature_seen != 4'b1111) && (cycles < MAX_CYCLES))
            @(posedge clk);

        if (signature_seen != 4'b1111) begin
            errors = errors + 1;
            $display("[FAIL] workload timeout signatures=%b cycle=%0d", signature_seen, cycles);
            $display("WORKLOAD_TIMEOUT_STATE pc=%08x/%08x/%08x/%08x x9=%08x/%08x/%08x/%08x x10=%08x/%08x/%08x/%08x x19=%08x/%08x/%08x/%08x",
                     dut.soc.core0.PCF, dut.soc.core1.PCF,
                     dut.soc.core2.PCF, dut.soc.core3.PCF,
                     dut.soc.core0.physical_core.core.decode_unit.rf.Register[9],
                     dut.soc.core1.physical_core.core.decode_unit.rf.Register[9],
                     dut.soc.core2.physical_core.core.decode_unit.rf.Register[9],
                     dut.soc.core3.physical_core.core.decode_unit.rf.Register[9],
                     dut.soc.core0.physical_core.core.decode_unit.rf.Register[10],
                     dut.soc.core1.physical_core.core.decode_unit.rf.Register[10],
                     dut.soc.core2.physical_core.core.decode_unit.rf.Register[10],
                     dut.soc.core3.physical_core.core.decode_unit.rf.Register[10],
                     dut.soc.core0.physical_core.core.decode_unit.rf.Register[19],
                     dut.soc.core1.physical_core.core.decode_unit.rf.Register[19],
                     dut.soc.core2.physical_core.core.decode_unit.rf.Register[19],
                     dut.soc.core3.physical_core.core.decode_unit.rf.Register[19]);
            $display("WORKLOAD_TIMEOUT_PROGRESS round_x14=%08x/%08x/%08x/%08x next_x12=%08x/%08x/%08x/%08x",
                     dut.soc.core0.physical_core.core.decode_unit.rf.Register[14],
                     dut.soc.core1.physical_core.core.decode_unit.rf.Register[14],
                     dut.soc.core2.physical_core.core.decode_unit.rf.Register[14],
                     dut.soc.core3.physical_core.core.decode_unit.rf.Register[14],
                     dut.soc.core0.physical_core.core.decode_unit.rf.Register[12],
                     dut.soc.core1.physical_core.core.decode_unit.rf.Register[12],
                     dut.soc.core2.physical_core.core.decode_unit.rf.Register[12],
                     dut.soc.core3.physical_core.core.decode_unit.rf.Register[12]);
            $display("WORKLOAD_TURN_CACHE c0_state=%0d/%0d data=%08x/%08x c1_state=%0d/%0d data=%08x/%08x c2_state=%0d/%0d data=%08x/%08x c3_state=%0d/%0d data=%08x/%08x",
                     dut.soc.core0.u_dcache.u_meta_way0.mem[48][1:0],
                     dut.soc.core0.u_dcache.u_meta_way1.mem[48][1:0],
                     dut.soc.core0.u_dcache.u_data_way0.mem[48][31:0],
                     dut.soc.core0.u_dcache.u_data_way1.mem[48][31:0],
                     dut.soc.core1.u_dcache.u_meta_way0.mem[48][1:0],
                     dut.soc.core1.u_dcache.u_meta_way1.mem[48][1:0],
                     dut.soc.core1.u_dcache.u_data_way0.mem[48][31:0],
                     dut.soc.core1.u_dcache.u_data_way1.mem[48][31:0],
                     dut.soc.core2.u_dcache.u_meta_way0.mem[48][1:0],
                     dut.soc.core2.u_dcache.u_meta_way1.mem[48][1:0],
                     dut.soc.core2.u_dcache.u_data_way0.mem[48][31:0],
                     dut.soc.core2.u_dcache.u_data_way1.mem[48][31:0],
                     dut.soc.core3.u_dcache.u_meta_way0.mem[48][1:0],
                     dut.soc.core3.u_dcache.u_meta_way1.mem[48][1:0],
                     dut.soc.core3.u_dcache.u_data_way0.mem[48][31:0],
                     dut.soc.core3.u_dcache.u_data_way1.mem[48][31:0]);
            $display("WORKLOAD_PIPELINE_WAIT dcache_fsm=%0d/%0d/%0d/%0d core_done=%b/%b/%b/%b mem_re=%b/%b/%b/%b mem_we=%b/%b/%b/%b mem_valid=%b/%b/%b/%b bus_req=%b/%b/%b/%b controller_state=%0d",
                     dut.soc.core0.u_dcache.state,
                     dut.soc.core1.u_dcache.state,
                     dut.soc.core2.u_dcache.state,
                     dut.soc.core3.u_dcache.state,
                     dut.soc.core0.physical_core.core_data_completed,
                     dut.soc.core1.physical_core.core_data_completed,
                     dut.soc.core2.physical_core.core_data_completed,
                     dut.soc.core3.physical_core.core_data_completed,
                     dut.soc.core0.Mem_ReadEnM, dut.soc.core1.Mem_ReadEnM,
                     dut.soc.core2.Mem_ReadEnM, dut.soc.core3.Mem_ReadEnM,
                     dut.soc.core0.Mem_WriteEnM, dut.soc.core1.Mem_WriteEnM,
                     dut.soc.core2.Mem_WriteEnM, dut.soc.core3.Mem_WriteEnM,
                     dut.soc.core0.Mem_DataValid, dut.soc.core1.Mem_DataValid,
                     dut.soc.core2.Mem_DataValid, dut.soc.core3.Mem_DataValid,
                     dut.soc.core0.dbus_req_valid, dut.soc.core1.dbus_req_valid,
                     dut.soc.core2.dbus_req_valid, dut.soc.core3.dbus_req_valid,
                     dut.soc.u_cache_controller_mmu.state);
        end
        for (i = 0; i < 4; i = i + 1) begin
            if (signature[i] !== (32'hC0DE_0000 | i)) begin
                errors = errors + 1;
                $display("[FAIL] hart%0d signature=%08x expected=%08x",
                         i, signature[i], (32'hC0DE_0000 | i));
            end
        end
        if (dut.soc.cache_protocol_error || dut.soc.cache_timeout_error ||
            dut.soc.cache_memory_error) begin
            errors = errors + 1;
            $display("[FAIL] controller status protocol=%b timeout=%b memory=%b",
                     dut.soc.cache_protocol_error, dut.soc.cache_timeout_error,
                     dut.soc.cache_memory_error);
        end
        if (axi_burst_reads == 0 || axi_read_beats < (axi_burst_reads * 8)) begin
            errors = errors + 1;
            $display("[FAIL] no complete eight-beat AXI read burst observed");
        end
        if (etom_read_requests != 4) begin
            errors = errors + 1;
            $display("[FAIL] E->M phase accepted %0d cold reads, expected 4",
                     etom_read_requests);
        end
        if (MESI_ENABLE) begin
            if (etom_rfo_requests != 0 || etom_s_grants != 0 ||
                etom_e_grants != 4) begin
                errors = errors + 1;
                $display("[FAIL] MESI E->M evidence rfos=%0d S=%0d E=%0d expected 0/0/4",
                         etom_rfo_requests, etom_s_grants, etom_e_grants);
            end
        end
        else begin
            if (etom_rfo_requests != 4 || etom_s_grants != 4 ||
                etom_e_grants != 0) begin
                errors = errors + 1;
                $display("[FAIL] MSI read-then-write evidence rfos=%0d S=%0d E=%0d expected 4/4/0",
                         etom_rfo_requests, etom_s_grants, etom_e_grants);
            end
        end
        report_statistics;
        if ((^total_l1_accesses) === 1'bx || (^total_retired) === 1'bx) begin
            errors = errors + 1;
            $display("[FAIL] performance counter contains X");
        end
        if (errors == 0)
            $display("QUAD_CORE_COMPILED_WORKLOAD_TB: PASS");
        else
            $display("QUAD_CORE_COMPILED_WORKLOAD_TB: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * (MAX_CYCLES + 1000));
        $display("QUAD_CORE_COMPILED_WORKLOAD_TB: FAIL (global timeout)");
        $finish;
    end
endmodule

module tb_quad_core_compiled_workload_msi;
    tb_quad_core_compiled_workload #(.MESI_ENABLE(0)) test();
endmodule

module tb_quad_core_compiled_workload_mesi;
    tb_quad_core_compiled_workload #(.MESI_ENABLE(1)) test();
endmodule

// Power-activity variants run the identical cycle-level workload at the
// routed target clock so SAIF toggle rates and create_clock agree.
module tb_quad_core_compiled_workload_msi_250;
    tb_quad_core_compiled_workload #(.MESI_ENABLE(0), .CLK_PERIOD(4)) test();
endmodule

module tb_quad_core_compiled_workload_mesi_250;
    tb_quad_core_compiled_workload #(.MESI_ENABLE(1), .CLK_PERIOD(4)) test();
endmodule
