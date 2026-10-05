`timescale 1ns / 1ps

// A failed physical access made by the page-table walker is an
// instruction/load/store access fault for the original virtual access,
// not a page fault. Cover failures at L1, L0, and A/D writeback.
module tb_mmu_bus_error;
    localparam [19:0] ROOT_PPN = 20'h00100;
    localparam [19:0] L0_PPN   = 20'h00200;
    localparam [19:0] LEAF_PPN = 20'h34567;

    reg clk, rst, mmu_enable, flush;
    reg [31:0] va_fetch, va_mem;
    reg mem_req, mem_is_store;
    reg [31:0] ptw_mem_rdata;
    reg ptw_mem_valid, ptw_mem_error;
    wire [31:0] pa_fetch, pa_mem;
    wire fetch_fault, mem_fault, fetch_access_fault, mem_access_fault;
    wire [1:0] fetch_fault_cause, mem_fault_cause;
    wire ptw_mem_req, ptw_mem_we, busy;
    wire [31:0] ptw_mem_addr, ptw_mem_wdata;
    integer errors, refill_count;

    mmu_top dut (
        .clk(clk), .rst(rst), .mmu_enable(mmu_enable),
        .satp_ppn(ROOT_PPN), .flush(flush),
        .current_priv(2'b01), .mstatus_sum(1'b0), .mstatus_mxr(1'b0),
        .va_fetch(va_fetch), .pa_fetch(pa_fetch),
        .va_mem(va_mem), .mem_req(mem_req), .mem_is_store(mem_is_store),
        .pa_mem(pa_mem),
        .fetch_fault(fetch_fault), .mem_fault(mem_fault),
        .fetch_access_fault(fetch_access_fault),
        .mem_access_fault(mem_access_fault),
        .fetch_fault_cause(fetch_fault_cause),
        .mem_fault_cause(mem_fault_cause),
        .ptw_mem_req(ptw_mem_req), .ptw_mem_we(ptw_mem_we),
        .ptw_mem_addr(ptw_mem_addr), .ptw_mem_wdata(ptw_mem_wdata),
        .ptw_mem_rdata(ptw_mem_rdata), .ptw_mem_valid(ptw_mem_valid),
        .ptw_mem_error(ptw_mem_error), .busy(busy),
        .debug_trace_rd_index(4'b0), .debug_trace_rd_data(),
        .debug_trace_count(), .debug_trace_write_index(),
        .debug_controller_state(), .debug_fetch_region(),
        .debug_mem_region(), .ptw_timeout_error()
    );

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (rst)
            refill_count <= 0;
        else if (dut.itlb_refill || dut.itlb_super_refill ||
                 dut.dtlb_refill || dut.dtlb_super_refill)
            refill_count <= refill_count + 1;
    end

    task reset_case;
        begin
            @(negedge clk);
            rst=1; mmu_enable=0; flush=0; mem_req=0; mem_is_store=0;
            ptw_mem_valid=0; ptw_mem_error=0; ptw_mem_rdata=0;
            repeat (2) @(posedge clk);
            @(negedge clk); rst=0; mmu_enable=1;
        end
    endtask

    task wait_request;
        input expected_we;
        input [31:0] expected_addr;
        integer guard;
        begin
            guard=0;
            while (!(ptw_mem_req && (ptw_mem_we == expected_we)) && guard<100) begin
                @(negedge clk); guard=guard+1;
            end
            if (!ptw_mem_req || ptw_mem_we !== expected_we ||
                ptw_mem_addr !== expected_addr) begin
                $display("[FAIL] PTW request we=%b addr=%h expected=%b/%h",
                         ptw_mem_we, ptw_mem_addr, expected_we, expected_addr);
                errors=errors+1;
            end
        end
    endtask

    task respond;
        input [31:0] data;
        input error_response;
        begin
            @(negedge clk);
            ptw_mem_rdata=data; ptw_mem_error=error_response; ptw_mem_valid=1;
            @(negedge clk);
            ptw_mem_valid=0; ptw_mem_error=0;
        end
    endtask

    task expect_fetch_access_fault;
        input [511:0] name;
        begin
            while (busy) @(negedge clk);
            #1;
            if (!fetch_access_fault || fetch_fault || mem_access_fault || mem_fault) begin
                $display("[FAIL] %0s fp=%b fa=%b mp=%b ma=%b",
                         name, fetch_fault, fetch_access_fault,
                         mem_fault, mem_access_fault);
                errors=errors+1;
            end else $display("[PASS] %0s", name);
        end
    endtask

    initial begin
        clk=0; rst=1; mmu_enable=0; flush=0;
        va_fetch=32'h0040_1234; va_mem=32'h0080_0568;
        mem_req=0; mem_is_store=0; ptw_mem_rdata=0;
        ptw_mem_valid=0; ptw_mem_error=0; errors=0; refill_count=0;

        // Root page-table memory error -> instruction access fault.
        reset_case();
        wait_request(1'b0, {ROOT_PPN, va_fetch[31:22], 2'b00});
        respond(32'b0, 1'b1);
        expect_fetch_access_fault("L1 PTE read error becomes instruction access fault");

        // Data-side request has priority. Root succeeds, L0 physical
        // read fails, and the original load receives load access fault.
        reset_case();
        mem_req=1;
        wait_request(1'b0, {ROOT_PPN, va_mem[31:22], 2'b00});
        respond({L0_PPN, 12'h001}, 1'b0);
        wait_request(1'b0, {L0_PPN, va_mem[21:12], 2'b00});
        respond(32'b0, 1'b1);
        while (busy) @(negedge clk);
        #1;
        if (!mem_access_fault || mem_fault || fetch_access_fault || fetch_fault) begin
            $display("[FAIL] L0 PTE read error fp=%b fa=%b mp=%b ma=%b",
                     fetch_fault, fetch_access_fault, mem_fault, mem_access_fault);
            errors=errors+1;
        end else $display("[PASS] L0 PTE read error becomes load access fault");
        mem_req=0;

        // Leaf is valid but A=0. If the hardware A-bit write fails,
        // translation must not refill and the fetch gets access fault.
        reset_case();
        wait_request(1'b0, {ROOT_PPN, va_fetch[31:22], 2'b00});
        respond({L0_PPN, 12'h001}, 1'b0);
        wait_request(1'b0, {L0_PPN, va_fetch[21:12], 2'b00});
        respond({LEAF_PPN, 12'h00B}, 1'b0); // V+R+X, A=0
        wait_request(1'b1, {L0_PPN, va_fetch[21:12], 2'b00});
        if (!ptw_mem_wdata[6]) begin
            $display("[FAIL] A/D write request did not set A");
            errors=errors+1;
        end
        respond(32'b0, 1'b1);
        expect_fetch_access_fault("A-bit write error becomes instruction access fault");
        if (refill_count != 0) begin
            $display("[FAIL] bus-error cases refilled %0d TLB entries", refill_count);
            errors=errors+1;
        end else $display("[PASS] failed page-table accesses never refill a TLB");

        if (errors==0) $display("MMU_BUS_ERROR_TB: PASS");
        else $display("MMU_BUS_ERROR_TB: FAIL (%0d checks)", errors);
        $finish;
    end

    initial begin
        #5000;
        $display("MMU_BUS_ERROR_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
