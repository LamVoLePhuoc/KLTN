`timescale 1ns / 1ps

// Architectural cause/tval checks for bus errors propagated from the
// MMU/AXI boundary: instruction=1, load=5, store/AMO=7.
module tb_csr_access_fault;
    reg clk, rst, csr_op;
    reg [2:0] funct3;
    reg [11:0] csr_addr;
    reg [31:0] csr_wdata;
    reg mem_read, mem_write;
    reg fetch_access_fault, data_access_fault;
    reg [31:0] pc_m, mem_addr;
    wire [31:0] csr_rdata, trap_pc;
    wire trap_taken;
    integer errors;

    csr_trap_unit dut (
        .clk(clk), .rst(rst), .Stall_Core_External(1'b0),
        .CsrOpM(csr_op), .CsrFunct3M(funct3), .CsrAddrM(csr_addr),
        .CsrWDataM(csr_wdata), .CsrRDataM(csr_rdata),
        .IsEcallM(1'b0), .IsEbreakM(1'b0), .IsMretM(1'b0),
        .IsSretM(1'b0), .IsSfenceVmaM(1'b0), .IsPrivIllegalM(1'b0),
        .IsIllegalOpM(1'b0), .MemReadM(mem_read), .MemWriteM(mem_write),
        .FetchPageFaultM(1'b0), .DataPageFaultM(1'b0),
        .FetchAccessFaultM(fetch_access_fault),
        .DataAccessFaultM(data_access_fault),
        .PCM(pc_m), .InstrM(32'h0000_0013), .MemAddrM(mem_addr),
        .TrapTakenM(trap_taken), .TrapPCM(trap_pc), .CurrentPriv(),
        .Mmu_Enable_Csr(), .Satp_PPN_Csr(), .Mstatus_Sum(),
        .Mstatus_Mxr(), .Mmu_Flush_Csr()
    );

    always #5 clk = ~clk;

    task csr_write;
        input [11:0] address;
        input [31:0] value;
        begin
            @(negedge clk);
            csr_addr=address; csr_wdata=value; funct3=3'b001; csr_op=1;
            @(negedge clk); csr_op=0;
        end
    endtask

    task check_csr;
        input [511:0] name;
        input [11:0] address;
        input [31:0] expected;
        begin
            csr_addr=address; #1;
            if (csr_rdata !== expected) begin
                $display("[FAIL] %0s got=%h expected=%h", name, csr_rdata, expected);
                errors=errors+1;
            end else $display("[PASS] %0s", name);
        end
    endtask

    task raise_fault;
        input is_fetch;
        input is_store;
        input [31:0] fault_pc;
        input [31:0] fault_addr;
        input [3:0] expected_cause;
        input [511:0] name;
        begin
            @(negedge clk);
            pc_m=fault_pc; mem_addr=fault_addr;
            mem_read=!is_fetch && !is_store;
            mem_write=!is_fetch && is_store;
            fetch_access_fault=is_fetch;
            data_access_fault=!is_fetch;
            #1;
            if (!trap_taken || trap_pc !== 32'h0000_0100) begin
                $display("[FAIL] %0s redirect taken=%b pc=%h",
                         name, trap_taken, trap_pc);
                errors=errors+1;
            end
            @(negedge clk);
            fetch_access_fault=0; data_access_fault=0;
            mem_read=0; mem_write=0;
            check_csr(name, 12'h342, {28'b0, expected_cause});
            check_csr("mepc captures faulting instruction", 12'h341, fault_pc);
            check_csr("mtval captures fault address", 12'h343,
                      is_fetch ? fault_pc : fault_addr);
        end
    endtask

    initial begin
        clk=0; rst=1; csr_op=0; funct3=3'b001; csr_addr=0; csr_wdata=0;
        mem_read=0; mem_write=0; fetch_access_fault=0; data_access_fault=0;
        pc_m=0; mem_addr=0; errors=0;
        repeat (3) @(posedge clk); #1 rst=0;
        csr_write(12'h305, 32'h0000_0100); // mtvec

        raise_fault(1, 0, 32'h0000_2000, 32'b0, 4'd1,
                    "instruction access fault cause=1");
        raise_fault(0, 0, 32'h0000_2010, 32'hDEAD_1000, 4'd5,
                    "load access fault cause=5");
        raise_fault(0, 1, 32'h0000_2020, 32'hDEAD_2000, 4'd7,
                    "store access fault cause=7");

        if (errors==0) $display("CSR_ACCESS_FAULT_TB: PASS");
        else $display("CSR_ACCESS_FAULT_TB: FAIL (%0d checks)", errors);
        $finish;
    end

    initial begin
        #3000;
        $display("CSR_ACCESS_FAULT_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
