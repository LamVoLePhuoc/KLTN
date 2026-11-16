`timescale 1ns / 1ps

module memory_stage(
    input  wire        clk,
    input  wire        rst,
    input  wire        Stall_Core_External,

    // --- Control Signals ---
    input  wire        MemWriteM,
    input  wire        MemReadM,
    input  wire        AtomicM,
    input  wire [4:0]  AmoOpM,      // NEW: RV32A funct5
    input  wire [2:0]  MemOpM,

    // --- Data Inputs ---
    input  wire [31:0] ALU_ResultM,
    input  wire [31:0] WriteDataM,

    // --- Physical address of THIS M-stage access (see header note on
    // LR/SC RESERVATION below -- fixes the VA-vs-PA bug) ---
    input  wire [31:0] Mem_PhysAddrM,

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
    //
    // FIXED (previously a real, documented bug -- see
    // Risc_V_new/README.md's risk register, "LR/SC VA-vs-PA"):
    // reservation_addr/sc_success used to compare against ALU_ResultM,
    // which is a VIRTUAL address (this module lives entirely inside
    // RV32IMA.v, pre-MMU) -- while Snoop_Addr always was, and still
    // is, PHYSICAL (it comes from coherence_manager.v, post-MMU, L1
    // layer). Comparing a stored VA against an incoming PA only ever
    // worked by coincidence, when a core's own VA->PA mapping happened
    // to be the identity function. Fixed by tracking/comparing the
    // reservation in the PHYSICAL domain throughout: Mem_PhysAddrM
    // (new input, see port list above) is the physical address of
    // whatever THIS M-stage access resolved to -- for LR, that is the
    // reservation's real physical address; for SC, comparing
    // Mem_PhysAddrM (SC's own physical address) against the stored
    // (already physical) reservation_addr is now a same-domain,
    // apples-to-apples compare. ALU_ResultM is no longer read by any
    // of this logic; it is still used elsewhere below (bus_addr,
    // unrelated to LR/SC reservation tracking).
    //
    // Callers with no MMU at all (VA=PA transparently -- see every
    // RV32IMA instantiation site) simply loop Mem_PhysAddrM back to
    // the core's own Mem_AddrM output, which is exactly identity and
    // preserves prior behavior exactly. Callers with a real MMU
    // (mmu_core_wrapper.v) wire in the MMU's own already-computed
    // pa_mem instead -- see that file's header.
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
                        (Mem_PhysAddrM == reservation_addr);

    always @(posedge clk) begin
        if (rst) begin
            reservation_valid <= 1'b0;
            reservation_addr  <= 32'h00000000;
        end
        else begin
            // Change architectural reservation state only when the
            // M-stage instruction actually retires.  With a multi-cycle
            // cache, clearing an SC reservation as soon as it first enters
            // M would deassert sc_success while its RFO is still pending,
            // prematurely release the pipeline, and report failure for a
            // store that the D$ was already completing.
            if (!Stall_Core_External) begin
                // LR.W creates a reservation (physical, not virtual).
                if (is_LR) begin
                    reservation_valid <= 1'b1;
                    reservation_addr  <= Mem_PhysAddrM;
                end

                // SC.W consumes the reservation only on retirement.
                else if (is_SC) begin
                    reservation_valid <= 1'b0;
                end
            end

            // Nếu core khác ghi vào đúng địa chỉ đang reserve,
            // reservation bị hủy. Snoop_Addr vốn đã là địa chỉ vật lý,
            // giờ so khớp đúng miền với reservation_addr.
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
