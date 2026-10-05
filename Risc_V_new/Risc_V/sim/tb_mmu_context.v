`timescale 1ns / 1ps

// Context-safety regression for mmu_top. It covers automatic TLB
// invalidation on satp/root changes, disabling translation during an
// outstanding walk, permission-context changes during a walk, and the
// non-destructive PTW watchdog used for board/ILA diagnosis.
module tb_mmu_context;
    localparam [19:0] ROOT_A = 20'h00100;
    localparam [19:0] ROOT_B = 20'h00110;
    localparam [19:0] L0_A   = 20'h00200;
    localparam [19:0] L0_B   = 20'h00210;
    localparam [19:0] PPN_A  = 20'h34567;
    localparam [19:0] PPN_B  = 20'h45678;

    reg clk, rst, mmu_enable, flush;
    reg [19:0] satp_ppn;
    reg [1:0] current_priv;
    reg mstatus_sum, mstatus_mxr;
    reg [31:0] va_fetch;
    reg [31:0] ptw_mem_rdata;
    reg ptw_mem_valid;

    wire [31:0] pa_fetch;
    wire fetch_fault, mem_fault, busy;
    wire [1:0] fetch_fault_cause, mem_fault_cause;
    wire ptw_mem_req, ptw_mem_we;
    wire [31:0] ptw_mem_addr, ptw_mem_wdata;
    wire ptw_timeout_error;
    integer errors, refill_count;

    mmu_top #(.PTW_WATCHDOG_CYCLES(6)) dut (
        .clk(clk), .rst(rst), .mmu_enable(mmu_enable),
        .satp_ppn(satp_ppn), .flush(flush),
        .current_priv(current_priv), .mstatus_sum(mstatus_sum),
        .mstatus_mxr(mstatus_mxr),
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
        .busy(busy),
        .debug_trace_rd_index(4'b0), .debug_trace_rd_data(),
        .debug_trace_count(), .debug_trace_write_index(),
        .debug_controller_state(), .debug_fetch_region(),
        .debug_mem_region(), .ptw_timeout_error(ptw_timeout_error)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst)
            refill_count <= 0;
        else if (dut.itlb_refill || dut.itlb_super_refill)
            refill_count <= refill_count + 1;
    end

    task wait_for_read;
        input [31:0] expected_addr;
        integer guard;
        begin
            guard = 0;
            while (!(ptw_mem_req && !ptw_mem_we) && guard < 100) begin
                @(negedge clk);
                guard = guard + 1;
            end
            if (!(ptw_mem_req && !ptw_mem_we) ||
                ptw_mem_addr !== expected_addr) begin
                $display("[FAIL] PTW read got req=%b we=%b addr=%h expected=%h",
                         ptw_mem_req, ptw_mem_we, ptw_mem_addr, expected_addr);
                errors = errors + 1;
            end
        end
    endtask

    task respond_read;
        input [31:0] data;
        begin
            @(negedge clk);
            ptw_mem_rdata = data;
            ptw_mem_valid = 1'b1;
            @(negedge clk);
            ptw_mem_valid = 1'b0;
        end
    endtask

    task complete_mapping;
        input [19:0] root_ppn;
        input [19:0] l0_ppn;
        input [19:0] leaf_ppn;
        begin
            wait_for_read({root_ppn, va_fetch[31:22], 2'b00});
            respond_read({l0_ppn, 12'h001});
            wait_for_read({l0_ppn, va_fetch[21:12], 2'b00});
            respond_read({leaf_ppn, 12'h04B}); // supervisor V+R+X+A
        end
    endtask

    task check_pa;
        input [19:0] expected_ppn;
        input [511:0] name;
        begin
            while (busy) @(negedge clk);
            #1;
            if (fetch_fault || pa_fetch !== {expected_ppn, va_fetch[11:0]}) begin
                $display("[FAIL] %0s fault=%b pa=%h expected=%h",
                         name, fetch_fault, pa_fetch,
                         {expected_ppn, va_fetch[11:0]});
                errors = errors + 1;
            end
            else
                $display("[PASS] %0s", name);
            @(negedge clk); // let T_GATE retire before the next scenario
        end
    endtask

    initial begin
        clk=0; rst=1; mmu_enable=0; flush=0; satp_ppn=ROOT_A;
        current_priv=2'b01; mstatus_sum=0; mstatus_mxr=0;
        va_fetch=32'h0040_1234; ptw_mem_rdata=0; ptw_mem_valid=0;
        errors=0; refill_count=0;
        repeat (3) @(posedge clk);
        #1 rst=0; mmu_enable=1;

        // The first enabled address space fills from ROOT_A.
        complete_mapping(ROOT_A, L0_A, PPN_A);
        check_pa(PPN_A, "initial address space translated");

        // Changing Satp_PPN without an explicit flush must still make
        // the old TLB entry unusable in the change cycle and walk ROOT_B.
        satp_ppn=ROOT_B;
        complete_mapping(ROOT_B, L0_B, PPN_B);
        check_pa(PPN_B, "satp root change auto-invalidates TLBs");
        if (refill_count !== 2) begin
            $display("[FAIL] satp switch refill count=%0d expected=2", refill_count);
            errors=errors+1;
        end else $display("[PASS] stale ROOT_A entry was not reused");

        // Start another walk, then disable translation after the root
        // read. The in-flight transaction is drained, but its leaf result
        // must not refill or fault; VA=PA bypass becomes visible afterwards.
        flush=1'b1;
        @(negedge clk); flush=1'b0;
        wait_for_read({ROOT_B, va_fetch[31:22], 2'b00});
        respond_read({L0_B, 12'h001});
        wait_for_read({L0_B, va_fetch[21:12], 2'b00});
        mmu_enable=1'b0;
        respond_read({PPN_B, 12'h04B});
        while (busy) @(negedge clk);
        #1;
        if (fetch_fault || pa_fetch !== va_fetch || refill_count !== 2) begin
            $display("[FAIL] disable-mid-walk fault=%b pa=%h refills=%0d",
                     fetch_fault, pa_fetch, refill_count);
            errors=errors+1;
        end else $display("[PASS] disable-mid-walk drains and discards old response");
        @(negedge clk);

        // Re-enable and refill ROOT_B before the permission-context test.
        mmu_enable=1'b1;
        complete_mapping(ROOT_B, L0_B, PPN_B);
        check_pa(PPN_B, "re-enable starts from a clean TLB context");

        // Change S -> U while the old S-context walk is active. The first
        // supervisor leaf would have succeeded under S, but must be discarded;
        // the retry under U must return a permission fault and never refill.
        flush=1'b1;
        @(negedge clk); flush=1'b0;
        wait_for_read({ROOT_B, va_fetch[31:22], 2'b00});
        respond_read({L0_B, 12'h001});
        wait_for_read({L0_B, va_fetch[21:12], 2'b00});
        current_priv=2'b00;
        respond_read({PPN_B, 12'h04B});
        complete_mapping(ROOT_B, L0_B, PPN_B);
        while (busy) @(negedge clk);
        #1;
        if (!fetch_fault || fetch_fault_cause !== 2'd2 || refill_count !== 3) begin
            $display("[FAIL] permission-context retry fault=%b cause=%0d refills=%0d",
                     fetch_fault, fetch_fault_cause, refill_count);
            errors=errors+1;
        end else $display("[PASS] privilege change discards and rechecks PTW result");
        @(negedge clk);

        // The watchdog reports a stuck PTW without unsafely abandoning a
        // transaction that a cache/bus may already have accepted.
        current_priv=2'b01;
        flush=1'b1;
        @(negedge clk); flush=1'b0;
        wait_for_read({ROOT_B, va_fetch[31:22], 2'b00});
        repeat (8) @(posedge clk);
        #1;
        if (!ptw_timeout_error) begin
            $display("[FAIL] PTW watchdog did not latch");
            errors=errors+1;
        end else $display("[PASS] PTW watchdog flags a stalled walk");
        respond_read({L0_B, 12'h001});
        wait_for_read({L0_B, va_fetch[21:12], 2'b00});
        respond_read({PPN_B, 12'h04B});
        while (busy) @(negedge clk);

        if (errors==0) $display("MMU_CONTEXT_TB: PASS");
        else $display("MMU_CONTEXT_TB: FAIL (%0d checks)", errors);
        $finish;
    end

    initial begin
        #6000;
        $display("MMU_CONTEXT_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
