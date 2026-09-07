`timescale 1ns / 1ps

module tb_top();

    // ============================================================
    // CLOCK / RESET
    // ============================================================
    reg clk;
    reg rst;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    initial begin
        rst = 1'b1;
        #100;
        rst = 1'b0;
        $display("[%0t] --- DUAL CORE SIMULATION STARTED ---", $time);
    end

    // ============================================================
    // DUT WIRES
    // ============================================================

    wire [31:0] PC0F;
    wire [31:0] PC1F;
    reg  [31:0] Instr0F;
    reg  [31:0] Instr1F;

    wire [31:0] Shared_Mem_Addr;
    wire [31:0] Shared_Mem_WriteData;
    wire        Shared_Mem_WriteEn;
    wire        Shared_Mem_ReadEn;
    wire [2:0]  Shared_MemOp;
    reg  [31:0] Shared_Mem_ReadData;

    wire [31:0] Core0_ResultW;
    wire [31:0] Core1_ResultW;
    wire [31:0] Core0_ALU_ResultE_Debug;
    wire [31:0] Core1_ALU_ResultE_Debug;
    wire        Grant0_Debug;
    wire        Grant1_Debug;
    wire        Turn_Debug;

    // ============================================================
    // MEMORY MODEL
    // ============================================================
    localparam MEM_WORDS = 4096;

    reg [31:0] ram [0:MEM_WORDS-1];

    integer i;

    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            ram[i] = 32'h00000013; // NOP
        end

        $readmemh("program.mem", ram);
        $display("[%0t] Loaded program.mem", $time);
    end

    // ============================================================
    // INSTRUCTION FETCH MODEL
    // ============================================================
    always @(*) begin
        if (rst) begin
            Instr0F = 32'h00000013;
            Instr1F = 32'h00000013;
        end
        else begin
            Instr0F = ram[PC0F[13:2]];
            Instr1F = ram[PC1F[13:2]];
        end
    end

    // ============================================================
    // SHARED DATA MEMORY READ
    // ============================================================
    always @(*) begin
        if (rst) begin
            Shared_Mem_ReadData = 32'b0;
        end
        else begin
            if (Shared_Mem_ReadEn)
                Shared_Mem_ReadData = ram[Shared_Mem_Addr[13:2]];
            else
                Shared_Mem_ReadData = 32'b0;
        end
    end

    // ============================================================
    // SHARED DATA MEMORY WRITE
    // ============================================================
    always @(posedge clk) begin
        if (!rst) begin
            if (Shared_Mem_WriteEn) begin
                case (Shared_MemOp)

                    // SB
                    3'b000: begin
                        case (Shared_Mem_Addr[1:0])
                            2'b00: ram[Shared_Mem_Addr[13:2]][7:0]   <= Shared_Mem_WriteData[7:0];
                            2'b01: ram[Shared_Mem_Addr[13:2]][15:8]  <= Shared_Mem_WriteData[7:0];
                            2'b10: ram[Shared_Mem_Addr[13:2]][23:16] <= Shared_Mem_WriteData[7:0];
                            2'b11: ram[Shared_Mem_Addr[13:2]][31:24] <= Shared_Mem_WriteData[7:0];
                        endcase
                    end

                    // SH
                    3'b001: begin
                        if (Shared_Mem_Addr[1] == 1'b0)
                            ram[Shared_Mem_Addr[13:2]][15:0] <= Shared_Mem_WriteData[15:0];
                        else
                            ram[Shared_Mem_Addr[13:2]][31:16] <= Shared_Mem_WriteData[15:0];
                    end

                    // SW / AMO.W
                    3'b010: begin
                        ram[Shared_Mem_Addr[13:2]] <= Shared_Mem_WriteData;
                    end

                    default: begin
                        ram[Shared_Mem_Addr[13:2]] <= Shared_Mem_WriteData;
                    end

                endcase

                $display("[SHARED WRITE] t=%0t g0=%b g1=%b addr=%h memop=%b wdata=%h",
                         $time,
                         Grant0_Debug,
                         Grant1_Debug,
                         Shared_Mem_Addr,
                         Shared_MemOp,
                         Shared_Mem_WriteData);
            end
        end
    end

    // ============================================================
    // DUT
    // ============================================================
    RV32IMA_DualCore_Wrapper #(
        .CORE0_RESET_ADDR(32'h0000_0000),
        .CORE1_RESET_ADDR(32'h0000_0100)
    ) dut (
        .clk                    (clk),
        .rst                    (rst),

        .PC0F                   (PC0F),
        .Instr0F                (Instr0F),

        .PC1F                   (PC1F),
        .Instr1F                (Instr1F),

        .Shared_Mem_Addr        (Shared_Mem_Addr),
        .Shared_Mem_WriteData   (Shared_Mem_WriteData),
        .Shared_Mem_WriteEn     (Shared_Mem_WriteEn),
        .Shared_Mem_ReadEn      (Shared_Mem_ReadEn),
        .Shared_MemOp           (Shared_MemOp),
        .Shared_Mem_ReadData    (Shared_Mem_ReadData),

        .Core0_ResultW          (Core0_ResultW),
        .Core1_ResultW          (Core1_ResultW),
        .Core0_ALU_ResultE_Debug(Core0_ALU_ResultE_Debug),
        .Core1_ALU_ResultE_Debug(Core1_ALU_ResultE_Debug),
        .Grant0_Debug           (Grant0_Debug),
        .Grant1_Debug           (Grant1_Debug),
        .Turn_Debug             (Turn_Debug)
    );

    // ============================================================
    // DONE DETECTOR
    // Core0 done: SW 1 -> 0x00000F00
    // Core1 done: SW 1 -> 0x00000F04
    // ============================================================
    localparam DONE0_ADDR = 32'h0000_0F00;
    localparam DONE1_ADDR = 32'h0000_0F04;
    localparam DONE_DATA  = 32'h0000_0001;

    reg done0;
    reg done1;

    always @(posedge clk) begin
        if (rst) begin
            done0 <= 1'b0;
            done1 <= 1'b0;
        end
        else begin
            if (Shared_Mem_WriteEn &&
                (Shared_Mem_Addr == DONE0_ADDR) &&
                (Shared_Mem_WriteData == DONE_DATA) &&
                (Shared_MemOp == 3'b010)) begin
                done0 <= 1'b1;
                $display("[%0t] CORE0 DONE", $time);
            end

            if (Shared_Mem_WriteEn &&
                (Shared_Mem_Addr == DONE1_ADDR) &&
                (Shared_Mem_WriteData == DONE_DATA) &&
                (Shared_MemOp == 3'b010)) begin
                done1 <= 1'b1;
                $display("[%0t] CORE1 DONE", $time);
            end

            if (done0 && done1) begin
                #20;
                dump_core0_regs();
                dump_core1_regs();
                dump_memory();

                $display("");
                $display("--- DUAL CORE SIMULATION FINISHED ---");
                $finish;
            end
        end
    end

    // ============================================================
    // DUMP CORE0 REGS
    // ============================================================
    task dump_core0_regs;
        integer k;
        begin
            $display("");
            $display("=================================================");
            $display(" CORE 0 REGISTER FILE");
            $display("=================================================");
            $display("c0.x0  = 0x00000000");

            for (k = 1; k < 32; k = k + 1) begin
                $display("c0.x%0d = 0x%08h",
                         k,
                         dut.core0.decode_unit.rf.Register[k]);
            end
        end
    endtask

    // ============================================================
    // DUMP CORE1 REGS
    // ============================================================
    task dump_core1_regs;
        integer k;
        begin
            $display("");
            $display("=================================================");
            $display(" CORE 1 REGISTER FILE");
            $display("=================================================");
            $display("c1.x0  = 0x00000000");

            for (k = 1; k < 32; k = k + 1) begin
                $display("c1.x%0d = 0x%08h",
                         k,
                         dut.core1.decode_unit.rf.Register[k]);
            end
        end
    endtask

    // ============================================================
    // DUMP MEMORY
    // ============================================================
    task dump_memory;
        integer k;
        begin
            $display("");
            $display("=================================================");
            $display(" SELECTED MEMORY DUMP");
            $display("=================================================");

            $display("");
            $display("# Shared data region: 0x00001000 - 0x0000107C");

            for (k = 32'h00000400; k < 32'h00000420; k = k + 1) begin
                $display("mem[0x%08h] = 0x%08h", k << 2, ram[k]);
            end

            $display("");
            $display("# Done flags:");
            $display("mem[0x%08h] = 0x%08h", DONE0_ADDR, ram[DONE0_ADDR[13:2]]);
            $display("mem[0x%08h] = 0x%08h", DONE1_ADDR, ram[DONE1_ADDR[13:2]]);
        end
    endtask

    // ============================================================
    // DEBUG MONITOR
    // ============================================================
    always @(posedge clk) begin
        if (!rst) begin
            if (Grant0_Debug || Grant1_Debug || Shared_Mem_WriteEn || Shared_Mem_ReadEn) begin
                $display("[ARB] t=%0t g0=%b g1=%b turn=%b re=%b we=%b addr=%h rdata=%h wdata=%h",
                         $time,
                         Grant0_Debug,
                         Grant1_Debug,
                         Turn_Debug,
                         Shared_Mem_ReadEn,
                         Shared_Mem_WriteEn,
                         Shared_Mem_Addr,
                         Shared_Mem_ReadData,
                         Shared_Mem_WriteData);
            end
        end
    end

    // ============================================================
    // TIMEOUT
    // ============================================================
    initial begin
        #5000000;
        $display("");
        $display("ERROR: TIMEOUT - dual-core program did not finish.");

        dump_core0_regs();
        dump_core1_regs();
        dump_memory();

        $finish;
    end

endmodule