`timescale 1ns / 1ps

// Self-checking unit test for the MMU architecture upgrade:
//   - 4-set x 4-way TLB lookup/refill/update/PLRU/flush
//   - explicit virtual-address region boundaries and permissions
//   - optional debug buffer saturation and circular overwrite
//
// Vivado simulation sources:
//   rtl/mmu_tlb.v rtl/mmu_region_decode.v rtl/mmu_debug_buffer.v
//   sim/tb_mmu_upgrade.v
// Expected final line: MMU_UPGRADE_TB: PASS
module tb_mmu_upgrade;

    reg clk;
    reg rst;
    reg flush;

    reg         lookup_valid;
    reg  [19:0] lookup_vpn;
    wire        hit;
    wire [19:0] hit_ppn;
    wire        hit_r, hit_w, hit_x, hit_u, hit_g, hit_a, hit_d;

    reg         refill_valid;
    reg  [19:0] refill_vpn;
    reg  [19:0] refill_ppn;
    reg         refill_r, refill_w, refill_x;
    reg         refill_u, refill_g, refill_a, refill_d;

    reg  [31:0] region_va;
    wire [2:0]  region;
    wire        allow_fetch, allow_load, allow_store;

    reg         trace_valid;
    reg  [79:0] trace_data;
    reg  [3:0]  trace_read_index;
    wire [79:0] trace_read_data;
    wire [4:0]  trace_count;
    wire [3:0]  trace_write_index;

    integer errors;
    integer n;

    mmu_tlb dut_tlb (
        .clk(clk), .rst(rst), .flush(flush),
        .lookup_valid(lookup_valid), .lookup_vpn(lookup_vpn),
        .hit(hit), .hit_ppn(hit_ppn),
        .hit_r(hit_r), .hit_w(hit_w), .hit_x(hit_x),
        .hit_u(hit_u), .hit_g(hit_g), .hit_a(hit_a), .hit_d(hit_d),
        .refill_valid(refill_valid),
        .refill_vpn(refill_vpn), .refill_ppn(refill_ppn),
        .refill_r(refill_r), .refill_w(refill_w), .refill_x(refill_x),
        .refill_u(refill_u), .refill_g(refill_g),
        .refill_a(refill_a), .refill_d(refill_d)
    );

    mmu_region_decode dut_region (
        .va(region_va), .region(region),
        .allow_fetch(allow_fetch), .allow_load(allow_load),
        .allow_store(allow_store)
    );

    mmu_debug_buffer dut_trace (
        .clk(clk), .rst(rst),
        .event_valid(trace_valid), .event_data(trace_data),
        .read_index(trace_read_index), .read_data(trace_read_data),
        .record_count(trace_count), .write_index(trace_write_index)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task refill_entry;
        input [19:0] vpn;
        input [19:0] ppn;
        input [6:0]  flags;
        begin
            @(negedge clk);
            refill_vpn   = vpn;
            refill_ppn   = ppn;
            {refill_d, refill_a, refill_g, refill_u,
             refill_x, refill_w, refill_r} = flags;
            refill_valid = 1'b1;
            @(posedge clk);
            #1 refill_valid = 1'b0;
        end
    endtask

    task expect_hit;
        input [19:0] vpn;
        input [19:0] ppn;
        input [6:0]  flags;
        begin
            lookup_valid = 1'b1;
            lookup_vpn   = vpn;
            #1;
            if (!hit || hit_ppn !== ppn ||
                {hit_d, hit_a, hit_g, hit_u, hit_x, hit_w, hit_r} !== flags) begin
                $display("[FAIL] TLB hit VPN=%05h hit=%b PPN=%05h flags=%02h expected PPN=%05h flags=%02h",
                         vpn, hit, hit_ppn,
                         {hit_d, hit_a, hit_g, hit_u, hit_x, hit_w, hit_r},
                         ppn, flags);
                errors = errors + 1;
            end
            else
                $display("[PASS] TLB hit VPN=%05h -> PPN=%05h", vpn, ppn);
        end
    endtask

    task expect_miss;
        input [19:0] vpn;
        begin
            lookup_valid = 1'b1;
            lookup_vpn   = vpn;
            #1;
            if (hit) begin
                $display("[FAIL] TLB miss expected for VPN=%05h, got PPN=%05h", vpn, hit_ppn);
                errors = errors + 1;
            end
            else
                $display("[PASS] TLB miss VPN=%05h", vpn);
        end
    endtask

    task touch_entry;
        input [19:0] vpn;
        begin
            lookup_valid = 1'b1;
            lookup_vpn   = vpn;
            #1;
            if (!hit) begin
                $display("[FAIL] Cannot touch missing VPN=%05h", vpn);
                errors = errors + 1;
            end
            @(posedge clk);
            #1;
        end
    endtask

    task expect_region;
        input [31:0] va;
        input [2:0]  expected_region;
        input [2:0]  expected_perm; // {fetch,load,store}
        begin
            region_va = va;
            #1;
            if (region !== expected_region ||
                {allow_fetch, allow_load, allow_store} !== expected_perm) begin
                $display("[FAIL] Region VA=%08h got region=%0d perm=%03b expected region=%0d perm=%03b",
                         va, region, {allow_fetch, allow_load, allow_store},
                         expected_region, expected_perm);
                errors = errors + 1;
            end
            else
                $display("[PASS] Region VA=%08h region=%0d perm=%03b",
                         va, region, expected_perm);
        end
    endtask

    initial begin
        errors           = 0;
        rst              = 1'b1;
        flush            = 1'b0;
        lookup_valid     = 1'b0;
        lookup_vpn       = 20'b0;
        refill_valid     = 1'b0;
        refill_vpn       = 20'b0;
        refill_ppn       = 20'b0;
        refill_r         = 1'b0;
        refill_w         = 1'b0;
        refill_x         = 1'b0;
        refill_u         = 1'b0;
        refill_g         = 1'b0;
        refill_a         = 1'b0;
        refill_d         = 1'b0;
        region_va        = 32'b0;
        trace_valid      = 1'b0;
        trace_data       = 80'b0;
        trace_read_index = 4'b0;

        repeat (3) @(posedge clk);
        #1 rst = 1'b0;

        // lookup_valid must gate both hit output and PLRU activity.
        lookup_vpn = 20'h00101;
        #1;
        if (hit !== 1'b0) begin
            $display("[FAIL] lookup_valid=0 did not suppress a lookup");
            errors = errors + 1;
        end
        else
            $display("[PASS] lookup_valid gates idle lookup");

        // Four VPNs with VPN[1:0]=01 fill all four ways of set 1.
        refill_entry(20'h00101, 20'h10101, 7'b110_0111);
        refill_entry(20'h00105, 20'h10105, 7'b010_0011);
        refill_entry(20'h00109, 20'h10109, 7'b001_0101);
        refill_entry(20'h0010D, 20'h1010D, 7'b111_0001);

        expect_hit(20'h00101, 20'h10101, 7'b110_0111);
        expect_hit(20'h00105, 20'h10105, 7'b010_0011);
        expect_hit(20'h00109, 20'h10109, 7'b001_0101);
        expect_hit(20'h0010D, 20'h1010D, 7'b111_0001);

        // After the fill order above PLRU initially points at way 0.
        // Touch ways 0 then 1, making the right pair old and way 2 the
        // deterministic victim.  A fifth same-set refill must evict C.
        touch_entry(20'h00101);
        touch_entry(20'h00105);
        refill_entry(20'h00111, 20'h10111, 7'b000_0111);
        expect_hit (20'h00101, 20'h10101, 7'b110_0111);
        expect_hit (20'h00105, 20'h10105, 7'b010_0011);
        expect_miss(20'h00109);
        expect_hit (20'h0010D, 20'h1010D, 7'b111_0001);
        expect_hit (20'h00111, 20'h10111, 7'b000_0111);

        // Refilling an existing VPN updates in place rather than
        // allocating a duplicate entry.
        refill_entry(20'h00111, 20'hABCDE, 7'b101_0101);
        expect_hit(20'h00111, 20'hABCDE, 7'b101_0101);

        // Another set is independent.
        refill_entry(20'h00202, 20'h20202, 7'b000_0011);
        expect_hit(20'h00202, 20'h20202, 7'b000_0011);
        expect_hit(20'h00111, 20'hABCDE, 7'b101_0101);

        @(negedge clk);
        flush = 1'b1;
        @(posedge clk);
        #1 flush = 1'b0;
        expect_miss(20'h00101);
        expect_miss(20'h00111);
        expect_miss(20'h00202);

        // Boundary checks for the agreed 32-bit virtual map.
        expect_region(32'h0000_0000, 3'd0, 3'b110);
        expect_region(32'h000F_FFFF, 3'd0, 3'b110);
        expect_region(32'h0010_0000, 3'd1, 3'b111);
        expect_region(32'h3FFF_FFFF, 3'd1, 3'b111);
        expect_region(32'h4000_0000, 3'd2, 3'b110);
        expect_region(32'h7FFF_FFFF, 3'd2, 3'b110);
        expect_region(32'h8000_0000, 3'd3, 3'b011);
        expect_region(32'hBFFF_FFFF, 3'd3, 3'b011);
        expect_region(32'hC000_0000, 3'd4, 3'b011);
        expect_region(32'hFFFF_FFFF, 3'd4, 3'b011);

        // Write 18 records into a 16-record ring: count saturates,
        // pointer wraps to 2, and entries 0/1 contain records 16/17.
        for (n = 0; n < 18; n = n + 1) begin
            @(negedge clk);
            trace_data  = n;
            trace_valid = 1'b1;
            @(posedge clk);
            #1 trace_valid = 1'b0;
        end
        if (trace_count !== 5'd16 || trace_write_index !== 4'd2) begin
            $display("[FAIL] Debug buffer count/pointer got count=%0d ptr=%0d expected 16/2",
                     trace_count, trace_write_index);
            errors = errors + 1;
        end
        else
            $display("[PASS] Debug buffer saturates and wraps");

        trace_read_index = 4'd0;
        #1;
        if (trace_read_data !== 80'd16) begin
            $display("[FAIL] Debug buffer index 0 got %0d expected 16", trace_read_data);
            errors = errors + 1;
        end
        trace_read_index = 4'd1;
        #1;
        if (trace_read_data !== 80'd17) begin
            $display("[FAIL] Debug buffer index 1 got %0d expected 17", trace_read_data);
            errors = errors + 1;
        end
        if (trace_read_data === 80'd17)
            $display("[PASS] Debug buffer circular overwrite data");

        $display("---------------------------------------------");
        if (errors == 0)
            $display("MMU_UPGRADE_TB: PASS");
        else
            $display("MMU_UPGRADE_TB: FAIL (%0d checks)", errors);
        $display("---------------------------------------------");
        $finish;
    end

    initial begin
        #10000;
        $display("MMU_UPGRADE_TB: FAIL (timeout)");
        $finish;
    end

endmodule
