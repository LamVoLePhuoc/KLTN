`timescale 1ns / 1ps

// Integration check for mmu_top's optional coarse-region guard and
// removable debug trace.  Forbidden-region accesses must fault in the
// controller without issuing a page-table read.
module tb_mmu_policy;

    reg clk;
    reg rst;
    reg mmu_enable;
    reg flush;
    reg [31:0] va_fetch;
    reg [31:0] va_mem;
    reg mem_req;
    reg mem_is_store;
    reg [3:0] trace_read_index;

    wire [31:0] pa_fetch;
    wire [31:0] pa_mem;
    wire fetch_fault;
    wire mem_fault;
    wire [1:0] fetch_fault_cause;
    wire [1:0] mem_fault_cause;
    wire ptw_mem_req;
    wire [31:0] ptw_mem_addr;
    wire busy;
    wire [79:0] trace_read_data;
    wire [4:0] trace_count;
    wire [3:0] trace_write_index;
    wire [1:0] controller_state;
    wire [2:0] fetch_region;
    wire [2:0] mem_region;

    integer errors;
    integer ptw_request_count;

    mmu_top #(
        .REGION_POLICY_ENABLE(1),
        .DEBUG_TRACE_ENABLE(1)
    ) dut (
        .clk(clk), .rst(rst),
        .mmu_enable(mmu_enable), .satp_ppn(20'b0), .flush(flush),
        .current_priv(2'b01), .mstatus_sum(1'b0), .mstatus_mxr(1'b0),
        .va_fetch(va_fetch), .pa_fetch(pa_fetch),
        .va_mem(va_mem), .mem_req(mem_req),
        .mem_is_store(mem_is_store), .pa_mem(pa_mem),
        .fetch_fault(fetch_fault), .mem_fault(mem_fault),
        .fetch_fault_cause(fetch_fault_cause),
        .mem_fault_cause(mem_fault_cause),
        .ptw_mem_req(ptw_mem_req), .ptw_mem_we(),
        .ptw_mem_addr(ptw_mem_addr), .ptw_mem_wdata(),
        .ptw_mem_rdata(32'b0), .ptw_mem_valid(1'b0),
        .busy(busy),
        .debug_trace_rd_index(trace_read_index),
        .debug_trace_rd_data(trace_read_data),
        .debug_trace_count(trace_count),
        .debug_trace_write_index(trace_write_index),
        .debug_controller_state(controller_state),
        .debug_fetch_region(fetch_region),
        .debug_mem_region(mem_region)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (rst)
            ptw_request_count <= 0;
        else if (ptw_mem_req)
            ptw_request_count <= ptw_request_count + 1;
    end

    initial begin
        errors            = 0;
        ptw_request_count = 0;
        rst               = 1'b1;
        mmu_enable        = 1'b0;
        flush             = 1'b0;
        va_fetch          = 32'h8000_0000;
        va_mem            = 32'h0000_1000;
        mem_req           = 1'b0;
        mem_is_store      = 1'b0;
        trace_read_index  = 4'b0;

        repeat (3) @(posedge clk);
        #1 rst = 1'b0;

        // Bare mode stays transparent even when the selected address
        // would be forbidden for fetch by the optional virtual map.
        #1;
        if (pa_fetch !== va_fetch || busy || fetch_fault) begin
            $display("[FAIL] Bare-mode bypass changed by region policy");
            errors = errors + 1;
        end
        else
            $display("[PASS] Bare-mode bypass ignores region guard");

        // User-data VA is RW but NX.  With translation on, fetch must
        // take the immediate permission-fault path (IDLE -> GATE), not
        // start the PTW.
        mmu_enable = 1'b1;
        #1;
        if (!busy || ptw_mem_req) begin
            $display("[FAIL] NX fetch did not enter immediate-fault path");
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        if (!fetch_fault || fetch_fault_cause !== 2'd2 || busy || ptw_mem_req) begin
            $display("[FAIL] NX fetch fault: fault=%b cause=%0d busy=%b ptw_req=%b",
                     fetch_fault, fetch_fault_cause, busy, ptw_mem_req);
            errors = errors + 1;
        end
        else
            $display("[PASS] NX fetch faults without a PTW access");

        // Stop the repeating fixed-VA request and let GATE return IDLE.
        mmu_enable = 1'b0;
        @(posedge clk);
        #1;

        // A store into the 1 MiB RX boot region is also rejected
        // before page-table access.  Data wins arbitration over the
        // simultaneous instruction-side problem.
        va_fetch     = 32'h8000_0000;
        va_mem       = 32'h000F_FFFC;
        mem_req      = 1'b1;
        mem_is_store = 1'b1;
        mmu_enable   = 1'b1;
        #1;
        if (!busy || ptw_mem_req) begin
            $display("[FAIL] Boot store did not enter immediate-fault path");
            errors = errors + 1;
        end
        @(posedge clk);
        #1;
        if (!mem_fault || mem_fault_cause !== 2'd2 || fetch_fault || ptw_mem_req) begin
            $display("[FAIL] Boot store fault/arbitration mismatch");
            errors = errors + 1;
        end
        else
            $display("[PASS] Boot store faults and data-side priority is preserved");

        mmu_enable = 1'b0;
        mem_req    = 1'b0;
        @(posedge clk);
        #1;

        if (ptw_request_count !== 0) begin
            $display("[FAIL] Forbidden-region tests issued %0d PTW request(s)", ptw_request_count);
            errors = errors + 1;
        end
        else
            $display("[PASS] Forbidden-region tests issued no PTW requests");

        // Each immediate-fault transaction produces START and GATE
        // records, so the two tests above must leave four entries.
        if (trace_count !== 5'd4) begin
            $display("[FAIL] MMU trace count=%0d expected=4", trace_count);
            errors = errors + 1;
        end
        else
            $display("[PASS] Optional MMU trace captured four controller events");

        trace_read_index = 4'd0;
        #1;
        if (trace_read_data[79:77] !== 3'd1 ||
            trace_read_data[72:41] !== 32'h8000_0000) begin
            $display("[FAIL] First trace record format/content mismatch");
            errors = errors + 1;
        end
        else
            $display("[PASS] Trace record exposes event type and VA");

        $display("---------------------------------------------");
        if (errors == 0)
            $display("MMU_POLICY_TB: PASS");
        else
            $display("MMU_POLICY_TB: FAIL (%0d checks)", errors);
        $display("---------------------------------------------");
        $finish;
    end

    initial begin
        #2000;
        $display("MMU_POLICY_TB: FAIL (timeout)");
        $finish;
    end

endmodule
