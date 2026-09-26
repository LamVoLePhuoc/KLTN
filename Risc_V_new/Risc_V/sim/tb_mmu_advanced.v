`timescale 1ns / 1ps

// Directed checks for the MMU features that are easy to regress:
// U/S+SUM/MXR permission rules, hardware A/D updates, aligned 4 MiB
// leaves, and superpage-TLB matching across different VPN[9:0].
module tb_mmu_advanced;
    localparam [19:0] SUPER_PPN = 20'hABC00;
    reg clk, rst;
    reg req_valid, req_is_store, req_is_fetch, req_sum, req_mxr;
    reg [19:0] req_vpn;
    reg [1:0] req_priv;
    reg [19:0] satp_ppn;
    wire ready, resp_valid, resp_fault, resp_superpage;
    wire [1:0] resp_fault_cause;
    wire [19:0] resp_ppn;
    wire resp_r, resp_w, resp_x, resp_u, resp_g, resp_a, resp_d;
    wire mem_req, mem_we;
    wire [31:0] mem_addr, mem_wdata;
    reg [31:0] root_pte, leaf_pte;
    wire [31:0] root_addr = {satp_ppn, req_vpn[19:10], 2'b00};
    wire [31:0] leaf_addr = {20'h00200, req_vpn[9:0], 2'b00};
    wire [31:0] mem_rdata = (mem_addr == root_addr) ? root_pte :
                            (mem_addr == leaf_addr) ? leaf_pte : 32'b0;
    wire mem_valid = mem_req;
    integer errors, write_count;

    mmu_ptw dut (
        .clk(clk), .rst(rst), .req_valid(req_valid), .req_vpn(req_vpn),
        .req_is_store(req_is_store), .req_is_fetch(req_is_fetch),
        .req_priv(req_priv), .req_sum(req_sum), .req_mxr(req_mxr),
        .satp_ppn(satp_ppn), .ready(ready),
        .resp_valid(resp_valid), .resp_fault(resp_fault),
        .resp_fault_cause(resp_fault_cause), .resp_ppn(resp_ppn),
        .resp_superpage(resp_superpage), .resp_r(resp_r), .resp_w(resp_w),
        .resp_x(resp_x), .resp_u(resp_u), .resp_g(resp_g),
        .resp_a(resp_a), .resp_d(resp_d),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_valid(mem_valid)
    );

    always #5 clk = ~clk;
    always @(posedge clk) begin
        if (rst) write_count <= 0;
        else if (mem_req && mem_we) begin
            write_count <= write_count + 1;
            if (mem_addr == root_addr) root_pte <= mem_wdata;
            if (mem_addr == leaf_addr) leaf_pte <= mem_wdata;
        end
    end

    task start_request;
        input is_store, is_fetch;
        input [1:0] priv;
        input sum, mxr;
        begin
            @(negedge clk);
            req_is_store = is_store; req_is_fetch = is_fetch;
            req_priv = priv; req_sum = sum; req_mxr = mxr;
            req_valid = 1'b1;
            @(negedge clk);
            req_valid = 1'b0;
            while (!resp_valid) @(negedge clk);
            #1;
        end
    endtask

    task expect_ok;
        input [255:0] name;
        begin
            if (resp_fault) begin
                $display("[FAIL] %0s fault cause=%0d", name, resp_fault_cause);
                errors = errors + 1;
            end else $display("[PASS] %0s", name);
        end
    endtask

    task expect_fault;
        input [255:0] name;
        input [1:0] cause;
        begin
            if (!resp_fault || resp_fault_cause !== cause) begin
                $display("[FAIL] %0s fault=%b cause=%0d", name, resp_fault, resp_fault_cause);
                errors = errors + 1;
            end else $display("[PASS] %0s", name);
        end
    endtask

    // Separate superpage TLB instance.
    reg stlb_flush, stlb_lookup_valid, stlb_refill_valid;
    reg [19:0] stlb_lookup_vpn, stlb_refill_vpn, stlb_refill_ppn;
    wire stlb_hit;
    wire [19:0] stlb_hit_ppn;
    mmu_super_tlb stlb (
        .clk(clk), .rst(rst), .flush(stlb_flush),
        .lookup_valid(stlb_lookup_valid), .lookup_vpn(stlb_lookup_vpn),
        .hit(stlb_hit), .hit_ppn(stlb_hit_ppn),
        .hit_r(), .hit_w(), .hit_x(), .hit_u(), .hit_g(), .hit_a(), .hit_d(),
        .refill_valid(stlb_refill_valid), .refill_vpn(stlb_refill_vpn),
        .refill_ppn(stlb_refill_ppn), .refill_r(1'b1), .refill_w(1'b1),
        .refill_x(1'b0), .refill_u(1'b0), .refill_g(1'b0),
        .refill_a(1'b1), .refill_d(1'b1)
    );

    initial begin
        clk=0; rst=1; errors=0; write_count=0; req_valid=0;
        req_is_store=0; req_is_fetch=0; req_priv=2'b01;
        req_sum=0; req_mxr=0; req_vpn=20'h12355; satp_ppn=20'h00100;
        root_pte=0; leaf_pte=0; stlb_flush=0; stlb_lookup_valid=0;
        stlb_refill_valid=0; stlb_lookup_vpn=0; stlb_refill_vpn=0;
        stlb_refill_ppn=0;
        repeat (3) @(posedge clk); #1 rst=0;

        // L1 pointer to page table at PPN 0x00200.
        root_pte = {20'h00200, 12'h001};

        // Supervisor load repairs A=0 before returning success.
        leaf_pte = {20'h34567, 12'h003}; // V+R, A=0
        start_request(0, 0, 2'b01, 0, 0);
        expect_ok("4KiB load updates A");
        if (!leaf_pte[6] || !resp_a || resp_d || write_count != 1) begin
            $display("[FAIL] A update pte=%h resp_a/d=%b/%b writes=%0d",
                     leaf_pte, resp_a, resp_d, write_count); errors=errors+1;
        end

        // Store with D=0 repairs D and keeps A set.
        leaf_pte = {20'h34567, 12'h047}; // V+R+W+A
        start_request(1, 0, 2'b01, 0, 0);
        expect_ok("4KiB store updates D");
        if (!leaf_pte[7] || !resp_d || write_count != 2) begin
            $display("[FAIL] D update pte=%h resp_d=%b writes=%0d",
                     leaf_pte, resp_d, write_count); errors=errors+1;
        end

        // U/S and SUM rules.
        leaf_pte = {20'h34567, 12'h043}; // supervisor V+R+A
        start_request(0, 0, 2'b00, 0, 0);
        expect_fault("U load rejects supervisor page", 2'd2);
        leaf_pte = {20'h34567, 12'h053}; // user V+R+U+A
        start_request(0, 0, 2'b00, 0, 0);
        expect_ok("U load accepts user page");
        start_request(0, 0, 2'b01, 0, 0);
        expect_fault("S load rejects user page when SUM=0", 2'd2);
        start_request(0, 0, 2'b01, 1, 0);
        expect_ok("S load accepts user page when SUM=1");

        // MXR only extends load permission; SUM never allows S fetch of U.
        leaf_pte = {20'h34567, 12'h049}; // supervisor V+X+A
        start_request(0, 0, 2'b01, 0, 0);
        expect_fault("load rejects execute-only page when MXR=0", 2'd2);
        start_request(0, 0, 2'b01, 0, 1);
        expect_ok("load accepts execute-only page when MXR=1");
        leaf_pte = {20'h34567, 12'h059}; // user V+X+U+A
        start_request(0, 1, 2'b01, 1, 0);
        expect_fault("S fetch rejects user page even with SUM=1", 2'd2);

        // Aligned level-1 leaf maps a 4 MiB superpage and updates A.
        root_pte = {SUPER_PPN, 12'h00B}; // V+R+X, aligned, A=0
        start_request(0, 1, 2'b01, 0, 0);
        expect_ok("aligned 4MiB leaf supported");
        if (!resp_superpage || resp_ppn !== {SUPER_PPN[19:10], req_vpn[9:0]} ||
            !root_pte[6]) begin
            $display("[FAIL] superpage response super=%b ppn=%h pte=%h",
                     resp_superpage, resp_ppn, root_pte); errors=errors+1;
        end

        root_pte = {20'hABC01, 12'h04B}; // low PPN bits violate alignment
        start_request(0, 1, 2'b01, 0, 0);
        expect_fault("misaligned 4MiB leaf rejected", 2'd3);

        // One super-TLB entry must hit every 4 KiB subpage in its 4 MiB range.
        @(negedge clk); stlb_refill_vpn=20'h12000; stlb_refill_ppn=SUPER_PPN;
        stlb_refill_valid=1;
        @(negedge clk); stlb_refill_valid=0; stlb_lookup_valid=1;
        stlb_lookup_vpn=20'h12355; #1;
        if (!stlb_hit || stlb_hit_ppn !== {SUPER_PPN[19:10], 10'h355}) begin
            $display("[FAIL] super-TLB cross-subpage hit=%b ppn=%h", stlb_hit, stlb_hit_ppn);
            errors=errors+1;
        end else $display("[PASS] super-TLB matches all VPN[9:0] subpages");

        $display("---------------------------------------------");
        if (errors==0) $display("MMU_ADVANCED_TB: PASS");
        else $display("MMU_ADVANCED_TB: FAIL (%0d checks)", errors);
        $display("---------------------------------------------");
        $finish;
    end

    initial begin #5000; $display("MMU_ADVANCED_TB: FAIL (timeout)"); $finish; end
endmodule
