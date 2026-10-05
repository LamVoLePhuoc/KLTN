`timescale 1ns / 1ps

// End-to-end LR/SC test through RV32IMA, MMU wrapper and MSI D-cache.
// LR cold-fills a Shared line; the following successful SC must retain its
// reservation while the S->M RFO is pending, return zero, and publish rs2.
module tb_cache_lrsc;
    localparam CLK_PERIOD = 10;

    reg clk, rst;
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    wire [31:0] result_w, alu_debug;
    wire fetch_pf, data_pf;
    wire [1:0] fetch_cause, data_cause;
    wire ibus_req_valid;
    wire [31:0] ibus_req_addr;
    reg ibus_resp_valid;
    reg [255:0] ibus_resp_line;
    wire dbus_req_valid;
    wire [1:0] dbus_req_type;
    wire [31:0] dbus_req_addr;
    wire [255:0] dbus_req_line;
    reg dbus_resp_valid;
    reg [255:0] dbus_resp_line;
    reg [1:0] dbus_resp_state;

    core_l1_wrapper #(
        .RESET_ADDR(32'h0000_1000),
        .MMU_REGION_POLICY_ENABLE(0)
    ) dut (
        .clk(clk), .rst(rst), .Mmu_Flush(1'b0), .Cache_Flush(1'b0),
        .ResultW(result_w), .ALU_ResultE_Debug(alu_debug),
        .Fetch_PageFault(fetch_pf), .Data_PageFault(data_pf),
        .Fetch_PageFault_Cause(fetch_cause), .Data_PageFault_Cause(data_cause),
        .ibus_req_valid(ibus_req_valid), .ibus_req_addr(ibus_req_addr),
        .ibus_resp_valid(ibus_resp_valid), .ibus_resp_error(1'b0), .ibus_resp_line(ibus_resp_line),
        .dbus_req_valid(dbus_req_valid), .dbus_req_type(dbus_req_type),
        .dbus_req_addr(dbus_req_addr), .dbus_req_line(dbus_req_line),
        .dbus_resp_valid(dbus_resp_valid), .dbus_resp_error(1'b0), .dbus_resp_line(dbus_resp_line),
        .dbus_resp_state(dbus_resp_state),
        .dsnoop_valid(1'b0), .dsnoop_type(1'b0), .dsnoop_addr(32'b0),
        .dsnoop_ack_valid(), .dsnoop_ack_hit(), .dsnoop_ack_dirty(), .dsnoop_ack_line()
    );

    reg prev_ibus_req;
    reg prev_dbus_req;
    integer busrd_count;
    integer rfo_count;
    integer unexpected_dreq_count;

    // Program at 0x1000:
    //   lui    x1, 0x3             // x1 = 0x3000
    //   addi   x2, x0, 7
    //   nop
    //   nop
    //   lr.w   x5, (x1)           // x5 = 21, line enters S
    //   sc.w   x6, x2, (x1)       // x6 = 0, line enters M, word = 7
    //   lw     x7, 0(x1)           // x7 = 7
    //   jal    x0, 0
    always @(posedge clk) begin
        if (rst) begin
            prev_ibus_req         <= 1'b0;
            prev_dbus_req         <= 1'b0;
            ibus_resp_valid       <= 1'b0;
            dbus_resp_valid       <= 1'b0;
            ibus_resp_line        <= 256'b0;
            dbus_resp_line        <= 256'b0;
            dbus_resp_state       <= 2'b01;
            busrd_count           <= 0;
            rfo_count             <= 0;
            unexpected_dreq_count <= 0;
        end
        else begin
            ibus_resp_valid <= 1'b0;
            dbus_resp_valid <= 1'b0;

            if (ibus_req_valid && !prev_ibus_req) begin
                if (ibus_req_addr == 32'h0000_1000) begin
                    ibus_resp_line <= {
                        32'h0000_006f, // jal x0, 0
                        32'h0000_a383, // lw x7, 0(x1)
                        32'h1820_a32f, // sc.w x6, x2, (x1)
                        32'h1000_a2af, // lr.w x5, (x1)
                        32'h0000_0013,
                        32'h0000_0013,
                        32'h0070_0113, // addi x2, x0, 7
                        32'h0000_30b7  // lui x1, 0x3
                    };
                end
                else begin
                    ibus_resp_line <= {8{32'h0000_006f}};
                end
                ibus_resp_valid <= 1'b1;
            end

            if (dbus_req_valid && !prev_dbus_req) begin
                dbus_resp_line       <= 256'b0;
                dbus_resp_line[31:0] <= 32'd21;
                dbus_resp_state      <= (dbus_req_type == 2'b01) ? 2'b11 : 2'b01;
                dbus_resp_valid      <= 1'b1;
                if ((dbus_req_addr == 32'h0000_3000) && (dbus_req_type == 2'b00))
                    busrd_count <= busrd_count + 1;
                else if ((dbus_req_addr == 32'h0000_3000) && (dbus_req_type == 2'b01))
                    rfo_count <= rfo_count + 1;
                else
                    unexpected_dreq_count <= unexpected_dreq_count + 1;
            end

            prev_ibus_req <= ibus_req_valid;
            prev_dbus_req <= dbus_req_valid;
        end
    end

    reg saw_lr_value;
    reg saw_sc_success;
    reg saw_sc_store;
    integer errors;
    integer cycles;

    always @(posedge clk) begin
        if (rst) begin
            saw_lr_value   <= 1'b0;
            saw_sc_success <= 1'b0;
            saw_sc_store   <= 1'b0;
        end
        else if (dut.mmu_core.core.RegWriteW) begin
            if ((dut.mmu_core.core.RD_W == 5'd5) && (result_w == 32'd21))
                saw_lr_value <= 1'b1;
            if ((dut.mmu_core.core.RD_W == 5'd6) && (result_w == 32'd0))
                saw_sc_success <= 1'b1;
            if ((dut.mmu_core.core.RD_W == 5'd7) && (result_w == 32'd7))
                saw_sc_store <= 1'b1;
        end
    end

    initial begin
        saw_lr_value = 1'b0;
        saw_sc_success = 1'b0;
        saw_sc_store = 1'b0;
        errors = 0;
        cycles = 0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        while (!(saw_lr_value && saw_sc_success && saw_sc_store) && cycles < 300) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (!saw_lr_value) begin
            $display("[FAIL] LR.W did not return the cold-filled word");
            errors = errors + 1;
        end
        else
            $display("[PASS] LR.W returned old value 21 and established a reservation");

        if (!saw_sc_success) begin
            $display("[FAIL] SC.W lost its reservation while RFO was pending");
            errors = errors + 1;
        end
        else
            $display("[PASS] SC.W retained reservation through S->M and returned success");

        if (!saw_sc_store) begin
            $display("[FAIL] load after successful SC.W did not observe rs2");
            errors = errors + 1;
        end
        else
            $display("[PASS] following LW observed SC.W value 7");

        if ((busrd_count != 1) || (rfo_count != 1)) begin
            $display("[FAIL] LR/SC traffic BusRd=%0d RFO=%0d, expected 1/1",
                     busrd_count, rfo_count);
            errors = errors + 1;
        end
        else
            $display("[PASS] LR cold fill and SC upgrade issued exactly BusRd then RFO");

        if (unexpected_dreq_count != 0) begin
            $display("[FAIL] observed %0d unexpected D$ request(s)", unexpected_dreq_count);
            errors = errors + 1;
        end

        if (fetch_pf || data_pf) begin
            $display("[FAIL] LR/SC smoke program raised an unexpected page fault");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("CACHE_LRSC_TB: PASS");
        else
            $display("CACHE_LRSC_TB: FAIL (%0d check(s) failed)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 500);
        $display("CACHE_LRSC_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
