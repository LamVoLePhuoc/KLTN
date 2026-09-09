`timescale 1ns / 1ps

module memory_stage(
    input  wire        clk,
    input  wire        rst,

    // --- Control Signals ---
    input  wire        MemWriteM,
    input  wire        MemReadM,
    input  wire        AtomicM,
    input  wire [4:0]  AmoOpM,      // NEW: RV32A funct5
    input  wire [2:0]  MemOpM,

    // --- Data Inputs ---
    input  wire [31:0] ALU_ResultM,
    input  wire [31:0] WriteDataM,

    // --- Snoop from other core ---
    input  wire [31:0] Snoop_Addr,
    input  wire        Snoop_WE,

    // --- Bus/Arbiter ---
    output wire [31:0] bus_addr,
    output wire [31:0] bus_write_data,
    output wire        bus_mem_write,
    output wire        bus_mem_read,
    output wire [2:0]  bus_mem_op,
    input  wire [31:0] bus_read_data,

    // --- Output to WB ---
    output wire [31:0] ReadDataM
);

    // ============================================================
    // RV32A AMO FUNCT5 ENCODING
    // Instr[31:27]
    // ============================================================
    localparam [4:0]
        AMO_ADD  = 5'b00000,   // AMOADD.W
        AMO_SWAP = 5'b00001,   // AMOSWAP.W
        AMO_LR   = 5'b00010,   // LR.W
        AMO_SC   = 5'b00011,   // SC.W
        AMO_XOR  = 5'b00100,   // AMOXOR.W
        AMO_OR   = 5'b01000,   // AMOOR.W
        AMO_AND  = 5'b01100,   // AMOAND.W
        AMO_MIN  = 5'b10000,   // AMOMIN.W
        AMO_MAX  = 5'b10100,   // AMOMAX.W
        AMO_MINU = 5'b11000,   // AMOMINU.W
        AMO_MAXU = 5'b11100;   // AMOMAXU.W

    // ============================================================
    // LR/SC RESERVATION
    // ============================================================
    reg [31:0] reservation_addr;
    reg        reservation_valid;

    wire is_LR;
    wire is_SC;
    wire is_AMO;

    assign is_LR  = AtomicM && (AmoOpM == AMO_LR);
    assign is_SC  = AtomicM && (AmoOpM == AMO_SC);

    assign is_AMO = AtomicM &&
                    (AmoOpM != AMO_LR) &&
                    (AmoOpM != AMO_SC);

    wire sc_success;
    assign sc_success = is_SC &&
                        reservation_valid &&
                        (ALU_ResultM == reservation_addr);

    always @(posedge clk) begin
        if (rst) begin
            reservation_valid <= 1'b0;
            reservation_addr  <= 32'h00000000;
        end
        else begin
            // LR.W tạo reservation
            if (is_LR) begin
                reservation_valid <= 1'b1;
                reservation_addr  <= ALU_ResultM;
            end

            // SC.W luôn xóa reservation sau khi thực hiện
            else if (is_SC) begin
                reservation_valid <= 1'b0;
            end

            // Nếu core khác ghi vào đúng địa chỉ đang reserve,
            // reservation bị hủy.
            if (reservation_valid && Snoop_WE && (Snoop_Addr == reservation_addr)) begin
                reservation_valid <= 1'b0;
            end
        end
    end

    // ============================================================
    // AMO READ-MODIFY-WRITE DATA
    //
    // bus_read_data = old memory value
    // WriteDataM    = rs2
    //
    // AMOxx.W:
    //   old = MEM[addr]
    //   MEM[addr] = old op rs2
    //   rd = old
    // ============================================================
    reg [31:0] amo_wdata;

    always @(*) begin
        case (AmoOpM)
            AMO_ADD: begin
                amo_wdata = bus_read_data + WriteDataM;
            end

            AMO_SWAP: begin
                amo_wdata = WriteDataM;
            end

            AMO_XOR: begin
                amo_wdata = bus_read_data ^ WriteDataM;
            end

            AMO_OR: begin
                amo_wdata = bus_read_data | WriteDataM;
            end

            AMO_AND: begin
                amo_wdata = bus_read_data & WriteDataM;
            end

            AMO_MIN: begin
                amo_wdata = ($signed(bus_read_data) < $signed(WriteDataM))
                            ? bus_read_data
                            : WriteDataM;
            end

            AMO_MAX: begin
                amo_wdata = ($signed(bus_read_data) > $signed(WriteDataM))
                            ? bus_read_data
                            : WriteDataM;
            end

            AMO_MINU: begin
                amo_wdata = (bus_read_data < WriteDataM)
                            ? bus_read_data
                            : WriteDataM;
            end

            AMO_MAXU: begin
                amo_wdata = (bus_read_data > WriteDataM)
                            ? bus_read_data
                            : WriteDataM;
            end

            default: begin
                amo_wdata = WriteDataM;
            end
        endcase
    end

    // ============================================================
    // BUS OUTPUTS
    // ============================================================
    assign bus_addr   = ALU_ResultM;
    assign bus_mem_op = MemOpM;

    // Store thường:
    //   ghi WriteDataM
    //
    // SC.W:
    //   nếu success thì ghi WriteDataM
    //
    // AMOxx.W:
    //   ghi amo_wdata
    assign bus_write_data =
        is_AMO ? amo_wdata :
                 WriteDataM;

    assign bus_mem_write =
        (!AtomicM && MemWriteM) ||
        is_AMO ||
        sc_success;

    // Load thường, LR.W, AMOxx.W cần đọc memory.
    // SC.W không cần đọc memory, chỉ trả status.
    assign bus_mem_read =
        (!AtomicM && MemReadM) ||
        is_LR ||
        is_AMO;

    // ============================================================
    // READ DATA TO WB
    //
    // LR.W:
    //   rd = old memory value
    //
    // SC.W:
    //   rd = 0 nếu success
    //   rd = 1 nếu fail
    //
    // AMOxx.W:
    //   rd = old memory value
    // ============================================================
    assign ReadDataM =
        is_SC ? {31'b0, ~sc_success} :
                bus_read_data;

endmodule