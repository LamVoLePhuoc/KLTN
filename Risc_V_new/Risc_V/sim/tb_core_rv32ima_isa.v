`timescale 1ns / 1ps

// Self-checking architectural smoke test for the bare RV32IMA pipeline.
// It deliberately bypasses the MMU/caches so an ISA/datapath regression can
// distinguish a core bug from a memory-system bug.  The program covers every
// RV32I integer ALU/branch/load/store/jump operation, all eight RV32M
// operations (including mandated corner cases), and every RV32A word AMO.
module tb_core_rv32ima_isa;
    localparam CLK_PERIOD = 10;
    localparam IMEM_WORDS = 512;
    localparam DMEM_WORDS = 1024;

    reg clk;
    reg rst;
    reg [31:0] imem [0:IMEM_WORDS-1];
    reg [31:0] dmem [0:DMEM_WORDS-1];

    wire [31:0] pcf;
    wire [31:0] instr_f;
    wire [31:0] mem_addr_m;
    wire [31:0] mem_wdata_m;
    wire        mem_we_m;
    wire        mem_re_m;
    wire [2:0]  mem_op_m;
    wire        mem_amo_m;
    wire [4:0]  mem_amo_op_m;
    wire [31:0] mem_amo_operand_m;
    wire        mem_request_m;
    wire        mem_store_intent_m;
    wire [31:0] mem_rdata_m;
    wire [31:0] result_w;
    wire [31:0] alu_debug;

    integer i;
    integer p;
    integer errors;
    integer cycles;
    integer auipc_pc;
    integer jal_pc;
    integer jalr_pc;

    function [31:0] enc_r;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin enc_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011}; end
    endfunction

    function [31:0] enc_i;
        input [11:0] imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_i = {imm, rs1, funct3, rd, opcode}; end
    endfunction

    function [31:0] enc_s;
        input [11:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin enc_s = {imm[11:5], rs2, rs1, funct3, imm[4:0], 7'b0100011}; end
    endfunction

    function [31:0] enc_b;
        input [12:0] imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        begin
            enc_b = {imm[12], imm[10:5], rs2, rs1, funct3,
                     imm[4:1], imm[11], 7'b1100011};
        end
    endfunction

    function [31:0] enc_u;
        input [19:0] imm20;
        input [4:0] rd;
        input [6:0] opcode;
        begin enc_u = {imm20, rd, opcode}; end
    endfunction

    function [31:0] enc_j;
        input [20:0] imm;
        input [4:0] rd;
        begin
            enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
        end
    endfunction

    function [31:0] enc_amo;
        input [4:0] funct5;
        input [4:0] rs2;
        input [4:0] rs1;
        input [4:0] rd;
        begin enc_amo = {funct5, 2'b00, rs2, rs1, 3'b010, rd, 7'b0101111}; end
    endfunction

    function [31:0] load_value;
        input [31:0] word;
        input [1:0] offset;
        input [2:0] op;
        reg [7:0] byte_v;
        reg [15:0] half_v;
        begin
            case (offset)
                2'd0: byte_v = word[7:0];
                2'd1: byte_v = word[15:8];
                2'd2: byte_v = word[23:16];
                default: byte_v = word[31:24];
            endcase
            half_v = offset[1] ? word[31:16] : word[15:0];
            case (op)
                3'b000: load_value = {{24{byte_v[7]}}, byte_v};
                3'b001: load_value = {{16{half_v[15]}}, half_v};
                3'b100: load_value = {24'd0, byte_v};
                3'b101: load_value = {16'd0, half_v};
                default: load_value = word;
            endcase
        end
    endfunction

    task emit;
        input [31:0] instruction;
        begin
            imem[p] = instruction;
            p = p + 1;
        end
    endtask

    task check_mem;
        input integer byte_addr;
        input [31:0] expected;
        input [8*48-1:0] label_text;
        begin
            if (dmem[byte_addr >> 2] !== expected) begin
                $display("[FAIL] %0s: got %08x expected %08x",
                         label_text, dmem[byte_addr >> 2], expected);
                errors = errors + 1;
            end
            else
                $display("[PASS] %0s = %08x", label_text, expected);
        end
    endtask

    assign instr_f = (pcf[31:2] < IMEM_WORDS) ? imem[pcf[31:2]] : 32'h0000_0013;
    assign mem_rdata_m = load_value(dmem[mem_addr_m[11:2]], mem_addr_m[1:0], mem_op_m);

    always @(posedge clk) begin
        if (mem_we_m) begin
            case (mem_op_m)
                3'b000: begin
                    case (mem_addr_m[1:0])
                        2'd0: dmem[mem_addr_m[11:2]][7:0]   <= mem_wdata_m[7:0];
                        2'd1: dmem[mem_addr_m[11:2]][15:8]  <= mem_wdata_m[7:0];
                        2'd2: dmem[mem_addr_m[11:2]][23:16] <= mem_wdata_m[7:0];
                        2'd3: dmem[mem_addr_m[11:2]][31:24] <= mem_wdata_m[7:0];
                    endcase
                end
                3'b001: begin
                    if (mem_addr_m[1])
                        dmem[mem_addr_m[11:2]][31:16] <= mem_wdata_m[15:0];
                    else
                        dmem[mem_addr_m[11:2]][15:0] <= mem_wdata_m[15:0];
                end
                default: dmem[mem_addr_m[11:2]] <= mem_wdata_m;
            endcase
        end
    end

    RV32IMA #(.RESET_ADDR(32'h0000_0000)) dut (
        .clk(clk), .rst(rst), .Stall_Core_External(1'b0),
        .Snoop_Addr(32'd0), .Snoop_WE(1'b0),
        .Mem_PhysAddrM(mem_addr_m),
        .PCF(pcf), .InstrF(instr_f),
        .Mem_AddrM(mem_addr_m), .Mem_WriteDataM(mem_wdata_m),
        .Mem_WriteEnM(mem_we_m), .Mem_ReadEnM(mem_re_m), .MemOpM(mem_op_m),
        .Mem_AmoRmwM(mem_amo_m), .Mem_AmoOpM(mem_amo_op_m),
        .Mem_AmoOperandM(mem_amo_operand_m), .Mem_RequestM(mem_request_m),
        .Mem_StoreIntentM(mem_store_intent_m), .Mem_ReadDataM(mem_rdata_m),
        .Fetch_PageFault_In(1'b0), .Data_PageFault_In(1'b0),
        .Fetch_AccessFault_In(1'b0), .Data_AccessFault_In(1'b0),
        .ResultW(result_w), .ALU_ResultE_Debug(alu_debug),
        .CurrentPriv(), .Mmu_Enable_Csr(), .Satp_PPN_Csr(),
        .Mstatus_Sum(), .Mstatus_Mxr(), .Mmu_Flush_Csr(), .FenceI_M()
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        errors = 0;
        cycles = 0;
        p = 0;
        for (i = 0; i < IMEM_WORDS; i = i + 1)
            imem[i] = 32'h0000_0013;
        for (i = 0; i < DMEM_WORDS; i = i + 1)
            dmem[i] = 32'd0;

        // RV32I register-register and immediate ALU operations.
        emit(enc_i(12'd5,   5'd0, 3'b000, 5'd1, 7'b0010011));
        emit(enc_i(12'hffd, 5'd0, 3'b000, 5'd2, 7'b0010011));
        emit(enc_i(12'd3,   5'd0, 3'b000, 5'd4, 7'b0010011));
        emit(enc_i(12'h400, 5'd0, 3'b000, 5'd20, 7'b0010011));
        emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3));
        emit(enc_s(12'h040, 5'd3, 5'd20, 3'b010));
        emit(enc_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3));
        emit(enc_s(12'h044, 5'd3, 5'd20, 3'b010));
        emit(enc_r(7'b0000000, 5'd4, 5'd1, 3'b001, 5'd3));
        emit(enc_s(12'h048, 5'd3, 5'd20, 3'b010));
        emit(enc_r(7'b0000000, 5'd1, 5'd2, 3'b010, 5'd3));
        emit(enc_s(12'h04c, 5'd3, 5'd20, 3'b010));
        emit(enc_r(7'b0000000, 5'd1, 5'd2, 3'b011, 5'd3));
        emit(enc_s(12'h050, 5'd3, 5'd20, 3'b010));
        emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd3));
        emit(enc_s(12'h054, 5'd3, 5'd20, 3'b010));
        emit(enc_u(20'h80000, 5'd5, 7'b0110111));
        emit(enc_r(7'b0000000, 5'd4, 5'd5, 3'b101, 5'd3));
        emit(enc_s(12'h058, 5'd3, 5'd20, 3'b010));
        emit(enc_r(7'b0100000, 5'd4, 5'd5, 3'b101, 5'd3));
        emit(enc_s(12'h05c, 5'd3, 5'd20, 3'b010));
        emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd3));
        emit(enc_s(12'h060, 5'd3, 5'd20, 3'b010));
        emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd3));
        emit(enc_s(12'h064, 5'd3, 5'd20, 3'b010));

        emit(enc_i(12'd7, 5'd2, 3'b000, 5'd3, 7'b0010011));
        emit(enc_s(12'h068, 5'd3, 5'd20, 3'b010));
        emit(enc_i(12'd0, 5'd2, 3'b010, 5'd3, 7'b0010011));
        emit(enc_s(12'h06c, 5'd3, 5'd20, 3'b010));
        emit(enc_i(12'd1, 5'd2, 3'b011, 5'd3, 7'b0010011));
        emit(enc_s(12'h070, 5'd3, 5'd20, 3'b010));
        emit(enc_i(12'h00f, 5'd1, 3'b100, 5'd3, 7'b0010011));
        emit(enc_s(12'h074, 5'd3, 5'd20, 3'b010));
        emit(enc_i(12'h00a, 5'd1, 3'b110, 5'd3, 7'b0010011));
        emit(enc_s(12'h078, 5'd3, 5'd20, 3'b010));
        emit(enc_i(12'h00f, 5'd1, 3'b111, 5'd3, 7'b0010011));
        emit(enc_s(12'h07c, 5'd3, 5'd20, 3'b010));
        emit(enc_i({7'b0000000,5'd4}, 5'd1, 3'b001, 5'd3, 7'b0010011));
        emit(enc_s(12'h080, 5'd3, 5'd20, 3'b010));
        emit(enc_i({7'b0000000,5'd4}, 5'd5, 3'b101, 5'd3, 7'b0010011));
        emit(enc_s(12'h084, 5'd3, 5'd20, 3'b010));
        emit(enc_i({7'b0100000,5'd4}, 5'd5, 3'b101, 5'd3, 7'b0010011));
        emit(enc_s(12'h088, 5'd3, 5'd20, 3'b010));
        emit(enc_u(20'h12345, 5'd11, 7'b0110111));
        emit(enc_s(12'h08c, 5'd11, 5'd20, 3'b010));
        auipc_pc = p * 4;
        emit(enc_u(20'h00001, 5'd12, 7'b0010111));
        emit(enc_s(12'h090, 5'd12, 5'd20, 3'b010));

        // All six conditional branches plus one explicitly not-taken case.
        emit(enc_i(12'd1, 5'd0, 3'b000, 5'd1, 7'b0010011));
        emit(enc_i(12'd2, 5'd0, 3'b000, 5'd2, 7'b0010011));
        emit(enc_i(12'hfff, 5'd0, 3'b000, 5'd3, 7'b0010011));
        emit(enc_i(12'd0, 5'd0, 3'b000, 5'd6, 7'b0010011));
        emit(enc_b(13'd8, 5'd1, 5'd1, 3'b000)); emit(enc_i(12'h200,5'd6,3'b000,5'd6,7'b0010011)); emit(enc_i(12'd1,5'd6,3'b000,5'd6,7'b0010011));
        emit(enc_b(13'd8, 5'd2, 5'd1, 3'b001)); emit(enc_i(12'h200,5'd6,3'b000,5'd6,7'b0010011)); emit(enc_i(12'd2,5'd6,3'b000,5'd6,7'b0010011));
        emit(enc_b(13'd8, 5'd1, 5'd3, 3'b100)); emit(enc_i(12'h200,5'd6,3'b000,5'd6,7'b0010011)); emit(enc_i(12'd4,5'd6,3'b000,5'd6,7'b0010011));
        emit(enc_b(13'd8, 5'd1, 5'd2, 3'b101)); emit(enc_i(12'h200,5'd6,3'b000,5'd6,7'b0010011)); emit(enc_i(12'd8,5'd6,3'b000,5'd6,7'b0010011));
        emit(enc_b(13'd8, 5'd3, 5'd1, 3'b110)); emit(enc_i(12'h200,5'd6,3'b000,5'd6,7'b0010011)); emit(enc_i(12'd16,5'd6,3'b000,5'd6,7'b0010011));
        emit(enc_b(13'd8, 5'd1, 5'd3, 3'b111)); emit(enc_i(12'h200,5'd6,3'b000,5'd6,7'b0010011)); emit(enc_i(12'd32,5'd6,3'b000,5'd6,7'b0010011));
        emit(enc_b(13'd8, 5'd2, 5'd1, 3'b000));
        emit(enc_i(12'd64, 5'd6, 3'b000, 5'd6, 7'b0010011));
        emit(enc_i(12'd128,5'd6, 3'b000, 5'd6, 7'b0010011));
        emit(enc_s(12'h094, 5'd6, 5'd20, 3'b010));

        jal_pc = p * 4;
        emit(enc_j(21'd8, 5'd7));
        emit(enc_i(12'h7ff, 5'd0, 3'b000, 5'd8, 7'b0010011));
        emit(enc_i(12'd1, 5'd0, 3'b000, 5'd8, 7'b0010011));
        emit(enc_s(12'h098, 5'd7, 5'd20, 3'b010));
        emit(enc_s(12'h09c, 5'd8, 5'd20, 3'b010));

        jalr_pc = p * 4;
        emit(enc_u(20'd0, 5'd9, 7'b0010111));
        emit(enc_i(12'd16, 5'd9, 3'b000, 5'd9, 7'b0010011));
        emit(enc_i(12'd0, 5'd9, 3'b000, 5'd10, 7'b1100111));
        emit(enc_i(12'h7ff, 5'd0, 3'b000, 5'd11, 7'b0010011));
        emit(enc_i(12'd2, 5'd0, 3'b000, 5'd11, 7'b0010011));
        emit(enc_s(12'h0a0, 5'd10, 5'd20, 3'b010));
        emit(enc_s(12'h0a4, 5'd11, 5'd20, 3'b010));

        // Byte/half/word stores and signed/unsigned loads.
        emit(enc_i(12'h500, 5'd0, 3'b000, 5'd20, 7'b0010011));
        emit(enc_i(12'hf80, 5'd0, 3'b000, 5'd21, 7'b0010011));
        emit(enc_s(12'd0, 5'd21, 5'd20, 3'b000));
        emit(enc_i(12'h07f, 5'd0, 3'b000, 5'd21, 7'b0010011));
        emit(enc_s(12'd1, 5'd21, 5'd20, 3'b000));
        emit(enc_u(20'h00008, 5'd21, 7'b0110111));
        emit(enc_i(12'd1, 5'd21, 3'b000, 5'd21, 7'b0010011));
        emit(enc_s(12'd2, 5'd21, 5'd20, 3'b001));
        emit(enc_i(12'd0, 5'd20, 3'b000, 5'd22, 7'b0000011)); emit(enc_s(12'h020,5'd22,5'd20,3'b010));
        emit(enc_i(12'd1, 5'd20, 3'b100, 5'd22, 7'b0000011)); emit(enc_s(12'h024,5'd22,5'd20,3'b010));
        emit(enc_i(12'd2, 5'd20, 3'b001, 5'd22, 7'b0000011)); emit(enc_s(12'h028,5'd22,5'd20,3'b010));
        emit(enc_i(12'd2, 5'd20, 3'b101, 5'd22, 7'b0000011)); emit(enc_s(12'h02c,5'd22,5'd20,3'b010));
        emit(enc_u(20'h12345, 5'd21, 7'b0110111));
        emit(enc_i(12'h678, 5'd21, 3'b000, 5'd21, 7'b0010011));
        emit(enc_s(12'd4, 5'd21, 5'd20, 3'b010));
        emit(enc_i(12'd4, 5'd20, 3'b010, 5'd22, 7'b0000011));
        emit(enc_s(12'h030, 5'd22, 5'd20, 3'b010));

        // RV32M, including divide-by-zero and signed overflow behavior.
        emit(enc_i(12'h540, 5'd0, 3'b000, 5'd20, 7'b0010011));
        emit(enc_i(12'hff9, 5'd0, 3'b000, 5'd1, 7'b0010011));
        emit(enc_i(12'd3, 5'd0, 3'b000, 5'd2, 7'b0010011));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b000,5'd3)); emit(enc_s(12'h000,5'd3,5'd20,3'b010));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b001,5'd3)); emit(enc_s(12'h004,5'd3,5'd20,3'b010));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b010,5'd3)); emit(enc_s(12'h008,5'd3,5'd20,3'b010));
        emit(enc_i(12'hfff,5'd0,3'b000,5'd1,7'b0010011)); emit(enc_i(12'd2,5'd0,3'b000,5'd2,7'b0010011));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b011,5'd3)); emit(enc_s(12'h00c,5'd3,5'd20,3'b010));
        emit(enc_i(12'hff9,5'd0,3'b000,5'd1,7'b0010011)); emit(enc_i(12'd3,5'd0,3'b000,5'd2,7'b0010011));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b100,5'd3)); emit(enc_s(12'h010,5'd3,5'd20,3'b010));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b101,5'd3)); emit(enc_s(12'h014,5'd3,5'd20,3'b010));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b110,5'd3)); emit(enc_s(12'h018,5'd3,5'd20,3'b010));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b111,5'd3)); emit(enc_s(12'h01c,5'd3,5'd20,3'b010));
        emit(enc_i(12'd123,5'd0,3'b000,5'd1,7'b0010011)); emit(enc_i(12'd0,5'd0,3'b000,5'd2,7'b0010011));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b100,5'd3)); emit(enc_s(12'h020,5'd3,5'd20,3'b010));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b110,5'd3)); emit(enc_s(12'h024,5'd3,5'd20,3'b010));
        emit(enc_u(20'h80000,5'd1,7'b0110111)); emit(enc_i(12'hfff,5'd0,3'b000,5'd2,7'b0010011));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b100,5'd3)); emit(enc_s(12'h028,5'd3,5'd20,3'b010));
        emit(enc_r(7'b0000001,5'd2,5'd1,3'b110,5'd3)); emit(enc_s(12'h02c,5'd3,5'd20,3'b010));

        // RV32A old-value return, RMW result, and LR/SC success/failure.
        emit(enc_i(12'h600,5'd0,3'b000,5'd20,7'b0010011));
        emit(enc_i(12'd5,5'd0,3'b000,5'd21,7'b0010011)); emit(enc_s(12'd0,5'd21,5'd20,3'b010));
        emit(enc_i(12'd3,5'd0,3'b000,5'd22,7'b0010011));
        emit(enc_amo(5'b00000,5'd22,5'd20,5'd23)); emit(enc_s(12'h040,5'd23,5'd20,3'b010));
        emit(enc_i(12'd2,5'd0,3'b000,5'd22,7'b0010011));
        emit(enc_amo(5'b00001,5'd22,5'd20,5'd23)); emit(enc_s(12'h044,5'd23,5'd20,3'b010));
        emit(enc_i(12'h00f,5'd0,3'b000,5'd22,7'b0010011));
        emit(enc_amo(5'b00100,5'd22,5'd20,5'd23)); emit(enc_s(12'h048,5'd23,5'd20,3'b010));
        emit(enc_i(12'd6,5'd0,3'b000,5'd22,7'b0010011));
        emit(enc_amo(5'b01100,5'd22,5'd20,5'd23)); emit(enc_s(12'h04c,5'd23,5'd20,3'b010));
        emit(enc_i(12'd1,5'd0,3'b000,5'd22,7'b0010011));
        emit(enc_amo(5'b01000,5'd22,5'd20,5'd23)); emit(enc_s(12'h050,5'd23,5'd20,3'b010));
        emit(enc_i(12'hffe,5'd0,3'b000,5'd22,7'b0010011));
        emit(enc_amo(5'b10000,5'd22,5'd20,5'd23)); emit(enc_s(12'h054,5'd23,5'd20,3'b010));
        emit(enc_i(12'd7,5'd0,3'b000,5'd22,7'b0010011));
        emit(enc_amo(5'b10100,5'd22,5'd20,5'd23)); emit(enc_s(12'h058,5'd23,5'd20,3'b010));
        emit(enc_i(12'd3,5'd0,3'b000,5'd22,7'b0010011));
        emit(enc_amo(5'b11000,5'd22,5'd20,5'd23)); emit(enc_s(12'h05c,5'd23,5'd20,3'b010));
        emit(enc_i(12'hfff,5'd0,3'b000,5'd22,7'b0010011));
        emit(enc_amo(5'b11100,5'd22,5'd20,5'd23)); emit(enc_s(12'h060,5'd23,5'd20,3'b010));
        emit(enc_amo(5'b00010,5'd0,5'd20,5'd24));
        emit(enc_i(12'd9,5'd0,3'b000,5'd25,7'b0010011));
        emit(enc_amo(5'b00011,5'd25,5'd20,5'd26));
        emit(enc_amo(5'b00011,5'd25,5'd20,5'd27));
        emit(enc_s(12'h064,5'd24,5'd20,3'b010)); emit(enc_s(12'h068,5'd26,5'd20,3'b010)); emit(enc_s(12'h06c,5'd27,5'd20,3'b010));

        // Completion signature and terminal self-loop.
        emit(enc_u(20'h600d6,5'd1,7'b0110111));
        emit(enc_i(12'h00d,5'd1,3'b000,5'd1,7'b0010011));
        emit(enc_i(12'h7fc,5'd0,3'b000,5'd20,7'b0010011));
        emit(enc_s(12'd0,5'd1,5'd20,3'b010));
        emit(enc_j(21'd0,5'd0));

        repeat (5) @(posedge clk);
        rst = 1'b0;

        while ((dmem[11'h1ff] !== 32'h600d_600d) && (cycles < 5000)) begin
            @(posedge clk);
            cycles = cycles + 1;
        end

        if (dmem[11'h1ff] !== 32'h600d_600d) begin
            $display("CORE_RV32IMA_ISA_TB: FAIL (timeout, PC=%08x)", pcf);
            $finish;
        end

        check_mem(16'h0440, 32'h0000_0002, "ADD");
        check_mem(16'h0444, 32'h0000_0008, "SUB");
        check_mem(16'h0448, 32'h0000_0028, "SLL");
        check_mem(16'h044c, 32'h0000_0001, "SLT");
        check_mem(16'h0450, 32'h0000_0000, "SLTU");
        check_mem(16'h0454, 32'hffff_fff8, "XOR");
        check_mem(16'h0458, 32'h1000_0000, "SRL");
        check_mem(16'h045c, 32'hf000_0000, "SRA");
        check_mem(16'h0460, 32'hffff_fffd, "OR");
        check_mem(16'h0464, 32'h0000_0005, "AND");
        check_mem(16'h0468, 32'h0000_0004, "ADDI");
        check_mem(16'h046c, 32'h0000_0001, "SLTI");
        check_mem(16'h0470, 32'h0000_0000, "SLTIU");
        check_mem(16'h0474, 32'h0000_000a, "XORI");
        check_mem(16'h0478, 32'h0000_000f, "ORI");
        check_mem(16'h047c, 32'h0000_0005, "ANDI");
        check_mem(16'h0480, 32'h0000_0050, "SLLI");
        check_mem(16'h0484, 32'h0800_0000, "SRLI");
        check_mem(16'h0488, 32'hf800_0000, "SRAI");
        check_mem(16'h048c, 32'h1234_5000, "LUI");
        check_mem(16'h0490, auipc_pc + 32'h1000, "AUIPC");
        check_mem(16'h0494, 32'd255, "conditional branches");
        check_mem(16'h0498, jal_pc + 4, "JAL link");
        check_mem(16'h049c, 32'd1, "JAL redirect");
        check_mem(16'h04a0, jalr_pc + 12, "JALR link");
        check_mem(16'h04a4, 32'd2, "JALR redirect");

        check_mem(16'h0500, 32'h8001_7f80, "SB/SH lane merge");
        check_mem(16'h0520, 32'hffff_ff80, "LB");
        check_mem(16'h0524, 32'h0000_007f, "LBU");
        check_mem(16'h0528, 32'hffff_8001, "LH");
        check_mem(16'h052c, 32'h0000_8001, "LHU");
        check_mem(16'h0530, 32'h1234_5678, "LW/SW");

        check_mem(16'h0540, 32'hffff_ffeb, "MUL");
        check_mem(16'h0544, 32'hffff_ffff, "MULH");
        check_mem(16'h0548, 32'hffff_ffff, "MULHSU");
        check_mem(16'h054c, 32'h0000_0001, "MULHU");
        check_mem(16'h0550, 32'hffff_fffe, "DIV");
        check_mem(16'h0554, 32'h5555_5553, "DIVU");
        check_mem(16'h0558, 32'hffff_ffff, "REM");
        check_mem(16'h055c, 32'h0000_0000, "REMU");
        check_mem(16'h0560, 32'hffff_ffff, "DIV by zero");
        check_mem(16'h0564, 32'd123, "REM by zero");
        check_mem(16'h0568, 32'h8000_0000, "DIV overflow");
        check_mem(16'h056c, 32'h0000_0000, "REM overflow");

        check_mem(16'h0640, 32'd5, "AMOADD old value");
        check_mem(16'h0644, 32'd8, "AMOSWAP old value");
        check_mem(16'h0648, 32'd2, "AMOXOR old value");
        check_mem(16'h064c, 32'd13, "AMOAND old value");
        check_mem(16'h0650, 32'd4, "AMOOR old value");
        check_mem(16'h0654, 32'd5, "AMOMIN old value");
        check_mem(16'h0658, 32'hffff_fffe, "AMOMAX old value");
        check_mem(16'h065c, 32'd7, "AMOMINU old value");
        check_mem(16'h0660, 32'd3, "AMOMAXU old value");
        check_mem(16'h0664, 32'hffff_ffff, "LR.W old value");
        check_mem(16'h0668, 32'd0, "SC.W success");
        check_mem(16'h066c, 32'd1, "SC.W failure without LR");
        check_mem(16'h0600, 32'd9, "final atomic word");

        if (errors == 0)
            $display("CORE_RV32IMA_ISA_TB: PASS");
        else
            $display("CORE_RV32IMA_ISA_TB: FAIL (%0d checks failed)", errors);
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 5500);
        $display("CORE_RV32IMA_ISA_TB: FAIL (global timeout)");
        $finish;
    end
endmodule
