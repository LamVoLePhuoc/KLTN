`timescale 1ns / 1ps

// A flush arriving while the shared PTW is active must invalidate all
// TLBs, discard the in-flight response, and re-walk the held VA.  This
// test changes the leaf mapping between the discarded and fresh walks;
// observing only the new PA proves that stale refill cannot escape.
module tb_mmu_sfence;
    reg clk, rst, mmu_enable, flush;
    reg [31:0] va_fetch;
    reg [31:0] ptw_mem_rdata;
    reg ptw_mem_valid;
    wire [31:0] pa_fetch;
    wire fetch_fault, mem_fault, busy;
    wire [1:0] fetch_fault_cause, mem_fault_cause;
    wire ptw_mem_req, ptw_mem_we;
    wire [31:0] ptw_mem_addr, ptw_mem_wdata;
    integer errors, refill_count;

    localparam [19:0] ROOT_PPN = 20'h00100;
    localparam [19:0] L0_PPN   = 20'h00200;
    localparam [19:0] OLD_PPN  = 20'h34567;
    localparam [19:0] NEW_PPN  = 20'h45678;

    mmu_top dut (
        .clk(clk), .rst(rst), .mmu_enable(mmu_enable),
        .satp_ppn(ROOT_PPN), .flush(flush),
        .current_priv(2'b01), .mstatus_sum(1'b0), .mstatus_mxr(1'b0),
        .va_fetch(va_fetch), .pa_fetch(pa_fetch),
        .va_mem(32'b0), .mem_req(1'b0), .mem_is_store(1'b0), .pa_mem(),
        .fetch_fault(fetch_fault), .mem_fault(mem_fault),
        .fetch_access_fault(), .mem_access_fault(),
        .fetch_fault_cause(fetch_fault_cause),
        .mem_fault_cause(mem_fault_cause),
        .ptw_mem_req(ptw_mem_req), .ptw_mem_we(ptw_mem_we),
        .ptw_mem_addr(ptw_mem_addr), .ptw_mem_wdata(ptw_mem_wdata),
        .ptw_mem_rdata(ptw_mem_rdata), .ptw_mem_valid(ptw_mem_valid),
        .ptw_mem_error(1'b0),
        .busy(busy), .debug_trace_rd_index(4'b0),
        .debug_trace_rd_data(), .debug_trace_count(),
        .debug_trace_write_index(), .debug_controller_state(),
        .debug_fetch_region(), .debug_mem_region(), .ptw_timeout_error()
    );

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (rst) refill_count <= 0;
        else if (dut.itlb_refill || dut.itlb_super_refill)
            refill_count <= refill_count + 1;
    end

    task wait_for_read;
        input [31:0] expected_addr;
        begin
            while (!ptw_mem_req) @(negedge clk);
            if (ptw_mem_we || ptw_mem_addr !== expected_addr) begin
                $display("[FAIL] PTW request we=%b addr=%h expected=%h",
                         ptw_mem_we, ptw_mem_addr, expected_addr);
                errors = errors + 1;
            end
        end
    endtask

    task respond_read;
        input [31:0] data;
        begin
            @(negedge clk); ptw_mem_rdata=data; ptw_mem_valid=1'b1;
            @(negedge clk); ptw_mem_valid=1'b0;
        end
    endtask

    initial begin
        clk=0; rst=1; mmu_enable=0; flush=0;
        va_fetch=32'h0040_1234; ptw_mem_rdata=0; ptw_mem_valid=0;
        errors=0; refill_count=0;
        repeat (3) @(posedge clk); #1 rst=0; mmu_enable=1;

        // First walk: root pointer, then an old leaf. Assert flush on
        // the exact cycle the leaf read completes.
        wait_for_read({ROOT_PPN, va_fetch[31:22], 2'b00});
        respond_read({L0_PPN, 12'h001});
        wait_for_read({L0_PPN, va_fetch[21:12], 2'b00});
        @(negedge clk);
        ptw_mem_rdata={OLD_PPN, 12'h04B}; // V+R+X+A
        ptw_mem_valid=1'b1;
        flush=1'b1;
        @(negedge clk);
        ptw_mem_valid=1'b0;
        flush=1'b0;

        // Deferred flush must force a complete second walk. Return a
        // different PPN and verify that only this response is refilled.
        wait_for_read({ROOT_PPN, va_fetch[31:22], 2'b00});
        respond_read({L0_PPN, 12'h001});
        wait_for_read({L0_PPN, va_fetch[21:12], 2'b00});
        respond_read({NEW_PPN, 12'h04B});

        while (busy) @(negedge clk);
        #1;
        if (fetch_fault || mem_fault) begin
            $display("[FAIL] deferred flush produced a page fault");
            errors=errors+1;
        end
        if (pa_fetch !== {NEW_PPN, va_fetch[11:0]}) begin
            $display("[FAIL] stale/fresh PA mismatch got=%h expected=%h",
                     pa_fetch, {NEW_PPN, va_fetch[11:0]});
            errors=errors+1;
        end else $display("[PASS] flush during PTW discards stale translation");
        if (refill_count !== 1) begin
            $display("[FAIL] refill count=%0d expected=1", refill_count);
            errors=errors+1;
        end else $display("[PASS] only the post-flush walk refills the TLB");

        // Repeat with A=0 and assert flush while the A-bit writeback
        // completes. The write is allowed to finish, but its response
        // is discarded and the translation must be checked again.
        @(negedge clk); flush=1'b1;
        @(negedge clk); flush=1'b0;
        wait_for_read({ROOT_PPN, va_fetch[31:22], 2'b00});
        respond_read({L0_PPN, 12'h001});
        wait_for_read({L0_PPN, va_fetch[21:12], 2'b00});
        respond_read({NEW_PPN, 12'h00B}); // V+R+X, A=0
        while (!(ptw_mem_req && ptw_mem_we)) @(negedge clk);
        if (ptw_mem_addr !== {L0_PPN, va_fetch[21:12], 2'b00} ||
            !ptw_mem_wdata[6]) begin
            $display("[FAIL] malformed A-bit writeback addr=%h data=%h",
                     ptw_mem_addr, ptw_mem_wdata);
            errors=errors+1;
        end
        ptw_mem_valid=1'b1;
        flush=1'b1;
        @(negedge clk);
        ptw_mem_valid=1'b0;
        flush=1'b0;

        wait_for_read({ROOT_PPN, va_fetch[31:22], 2'b00});
        respond_read({L0_PPN, 12'h001});
        wait_for_read({L0_PPN, va_fetch[21:12], 2'b00});
        respond_read({NEW_PPN, 12'h04B}); // PTE after A writeback
        while (busy) @(negedge clk);
        #1;
        if (fetch_fault || pa_fetch !== {NEW_PPN, va_fetch[11:0]}) begin
            $display("[FAIL] flush during A/D writeback did not revalidate mapping");
            errors=errors+1;
        end else $display("[PASS] flush during A/D writeback re-walks safely");
        if (refill_count !== 2) begin
            $display("[FAIL] total refill count=%0d expected=2", refill_count);
            errors=errors+1;
        end else $display("[PASS] A/D pre-flush response cannot refill the TLB");

        if (errors==0) $display("MMU_SFENCE_TB: PASS");
        else $display("MMU_SFENCE_TB: FAIL (%0d checks)", errors);
        $finish;
    end

    initial begin #3000; $display("MMU_SFENCE_TB: FAIL (timeout)"); $finish; end
endmodule
