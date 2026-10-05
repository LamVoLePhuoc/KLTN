`timescale 1ns / 1ps

// Direct CSR check for the mstatus/sstatus bits consumed by mmu_top.
module tb_csr_mmu_bits;
    reg clk, rst, csr_op;
    reg [2:0] funct3;
    reg [11:0] addr;
    reg [31:0] wdata;
    wire [31:0] rdata;
    wire sum, mxr;
    integer errors;

    csr_trap_unit dut (
        .clk(clk), .rst(rst), .Stall_Core_External(1'b0),
        .CsrOpM(csr_op), .CsrFunct3M(funct3), .CsrAddrM(addr),
        .CsrWDataM(wdata), .CsrRDataM(rdata),
        .IsEcallM(1'b0), .IsEbreakM(1'b0), .IsMretM(1'b0),
        .IsSretM(1'b0), .IsSfenceVmaM(1'b0), .IsPrivIllegalM(1'b0),
        .IsIllegalOpM(1'b0), .MemReadM(1'b0), .MemWriteM(1'b0),
        .FetchPageFaultM(1'b0), .DataPageFaultM(1'b0),
        .FetchAccessFaultM(1'b0), .DataAccessFaultM(1'b0),
        .PCM(32'b0), .InstrM(32'b0), .MemAddrM(32'b0),
        .TrapTakenM(), .TrapPCM(), .CurrentPriv(), .Mmu_Enable_Csr(),
        .Satp_PPN_Csr(), .Mstatus_Sum(sum), .Mstatus_Mxr(mxr),
        .Mmu_Flush_Csr()
    );

    always #5 clk = ~clk;

    task csr_write;
        input [11:0] csr_addr;
        input [31:0] value;
        begin
            @(negedge clk); addr=csr_addr; wdata=value; funct3=3'b001; csr_op=1;
            @(negedge clk); csr_op=0; #1;
        end
    endtask

    initial begin
        clk=0; rst=1; csr_op=0; funct3=3'b001; addr=0; wdata=0; errors=0;
        repeat (3) @(posedge clk); #1 rst=0;
        if (sum || mxr) begin $display("[FAIL] SUM/MXR reset"); errors=errors+1; end
        else $display("[PASS] SUM/MXR reset clear");

        csr_write(12'h300, 32'h000C_0000);
        if (!sum || !mxr) begin $display("[FAIL] mstatus writes SUM/MXR"); errors=errors+1; end
        else $display("[PASS] mstatus writes SUM/MXR");

        csr_write(12'h100, 32'h0008_0000); // SSTATUS: MXR=1, SUM=0
        if (sum || !mxr) begin $display("[FAIL] sstatus writes SUM/MXR"); errors=errors+1; end
        else $display("[PASS] sstatus independently updates SUM/MXR");

        if (errors==0) $display("CSR_MMU_BITS_TB: PASS");
        else $display("CSR_MMU_BITS_TB: FAIL (%0d)", errors);
        $finish;
    end
endmodule
