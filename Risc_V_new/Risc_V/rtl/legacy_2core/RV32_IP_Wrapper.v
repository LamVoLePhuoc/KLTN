`timescale 1ns / 1ps

module RV32IMA_IP_Wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_0000
)(
    input  wire        ACLK,
    input  wire        ARESETN,

    // ---------------- IMEM AXI READ ----------------
    output wire [31:0] M_AXI_IMEM_ARADDR,
    output wire        M_AXI_IMEM_ARVALID,
    input  wire        M_AXI_IMEM_ARREADY,
    input  wire [31:0] M_AXI_IMEM_RDATA,
    input  wire        M_AXI_IMEM_RVALID,
    output wire        M_AXI_IMEM_RREADY,

    // ---------------- DMEM AXI WRITE ADDRESS ----------------
    output wire [31:0] M_AXI_DMEM_AWADDR,
    output wire        M_AXI_DMEM_AWVALID,
    input  wire        M_AXI_DMEM_AWREADY,

    // ---------------- DMEM AXI WRITE DATA ----------------
    output wire [31:0] M_AXI_DMEM_WDATA,
    output wire [3:0]  M_AXI_DMEM_WSTRB,
    output wire        M_AXI_DMEM_WVALID,
    input  wire        M_AXI_DMEM_WREADY,

    // ---------------- DMEM AXI WRITE RESPONSE ----------------
    input  wire        M_AXI_DMEM_BVALID,
    output wire        M_AXI_DMEM_BREADY,

    // ---------------- DMEM AXI READ ADDRESS ----------------
    output wire [31:0] M_AXI_DMEM_ARADDR,
    output wire        M_AXI_DMEM_ARVALID,
    input  wire        M_AXI_DMEM_ARREADY,

    // ---------------- DMEM AXI READ DATA ----------------
    input  wire [31:0] M_AXI_DMEM_RDATA,
    input  wire        M_AXI_DMEM_RVALID,
    output wire        M_AXI_DMEM_RREADY
);

    // =========================================================
    // CORE INTERFACE
    // =========================================================
    wire [31:0] PCF;

    wire [31:0] Mem_AddrM;
    wire [31:0] Mem_WriteDataM;
    wire        Mem_WriteEnM;
    wire        Mem_ReadEnM;
    wire [2:0]  MemOpM;

    wire [31:0] InstrF_ToCore;
    wire [31:0] Mem_ReadDataM_ToCore;

    wire core_rst = ~ARESETN;

    // Chỉ stall khi store đang chờ phản hồi.
    // Load đọc combinational nên không cần stall.
    reg d_stall;

    RV32IMA  core (
        .clk                (ACLK),
        .rst                (core_rst),

        .Stall_Core_External(d_stall),

        .Snoop_Addr         (32'b0),
        .Snoop_WE           (1'b0),

        .PCF                (PCF),
        .InstrF             (InstrF_ToCore),

        .Mem_AddrM          (Mem_AddrM),
        .Mem_WriteDataM     (Mem_WriteDataM),
        .Mem_WriteEnM       (Mem_WriteEnM),
        .Mem_ReadEnM        (Mem_ReadEnM),
        .MemOpM             (MemOpM),

        .Mem_ReadDataM      (Mem_ReadDataM_ToCore),

        // NEW: see legacy_2core/RV32IMA_DualCore_Wrapper.v's identical
        // comment -- RV32IMA.v gained a trap/CSR unit with two new
        // required inputs this session; tied low here (no MMU in
        // front of this wrapper, so never a page fault to report) to
        // keep this file's behaviour exactly as it was.
        .Fetch_PageFault_In (1'b0),
        .Data_PageFault_In  (1'b0),

        .ResultW            (),
        .ALU_ResultE_Debug  ()
    );

    // =========================================================
    // IMEM READ - COMBINATIONAL MODEL
    //
    // Wrapper chỉ đưa PCF ra ngoài.
    // Testbench sẽ trả instruction ngay theo địa chỉ PCF.
    // =========================================================
    assign M_AXI_IMEM_ARADDR  = PCF;
    assign M_AXI_IMEM_ARVALID = 1'b1;
    assign M_AXI_IMEM_RREADY  = 1'b1;

    assign InstrF_ToCore = M_AXI_IMEM_RVALID ? M_AXI_IMEM_RDATA : 32'h0000_0013;

    // =========================================================
    // LOAD UNIT
    //
    // DMEM read là combinational, nên load_unit dùng trực tiếp:
    //   raw_data    = M_AXI_DMEM_RDATA
    //   addr_offset = Mem_AddrM[1:0]
    //   mem_op      = MemOpM
    // =========================================================
    load_unit u_load_unit (
        .raw_data    (M_AXI_DMEM_RDATA),
        .addr_offset (Mem_AddrM[1:0]),
        .mem_op      (MemOpM),
        .load_data   (Mem_ReadDataM_ToCore)
    );

    // =========================================================
    // STORE UNIT
    //
    // Store vẫn cần tạo WDATA/WSTRB đúng cho sb/sh/sw.
    // =========================================================
    wire [31:0] store_axi_wdata;
    wire [3:0]  store_axi_wstrb;

    store_unit u_store_unit (
        .store_data  (Mem_WriteDataM),
        .addr_offset (Mem_AddrM[1:0]),
        .mem_op      (MemOpM),
        .axi_wdata   (store_axi_wdata),
        .axi_wstrb   (store_axi_wstrb)
    );

    // =========================================================
    // DMEM READ - COMBINATIONAL MODEL
    //
    // Core đưa địa chỉ load ra Mem_AddrM.
    // Testbench trả dữ liệu ngay qua M_AXI_DMEM_RDATA.
    // =========================================================
    assign M_AXI_DMEM_ARADDR  = Mem_AddrM;
    assign M_AXI_DMEM_ARVALID = Mem_ReadEnM;
    assign M_AXI_DMEM_RREADY  = 1'b1;

    // =========================================================
    // DMEM WRITE - SINGLE OUTSTANDING STORE
    //
    // Store có thể giữ 1 request cho tới khi BVALID.
    // =========================================================
    reg        store_pending;
    reg [31:0] store_addr_reg;
    reg [31:0] store_wdata_reg;
    reg [3:0]  store_wstrb_reg;

    assign M_AXI_DMEM_AWADDR  = store_addr_reg;
    assign M_AXI_DMEM_AWVALID = store_pending;

    assign M_AXI_DMEM_WDATA   = store_wdata_reg;
    assign M_AXI_DMEM_WSTRB   = store_wstrb_reg;
    assign M_AXI_DMEM_WVALID  = store_pending;

    assign M_AXI_DMEM_BREADY  = 1'b1;

    always @(posedge ACLK) begin
        if (core_rst) begin
            store_pending  <= 1'b0;
            store_addr_reg <= 32'b0;
            store_wdata_reg <= 32'b0;
            store_wstrb_reg <= 4'b0000;
            d_stall        <= 1'b0;
        end
        else begin
            // Nếu đang chờ store response
            if (store_pending) begin
                d_stall <= 1'b1;

                if (M_AXI_DMEM_BVALID) begin
                    store_pending <= 1'b0;
                    d_stall       <= 1'b0;
                end
            end

            // Nếu rảnh và có store mới
            else begin
                d_stall <= 1'b0;

                if (Mem_WriteEnM) begin
                    store_pending   <= 1'b1;
                    store_addr_reg  <= Mem_AddrM;
                    store_wdata_reg <= store_axi_wdata;
                    store_wstrb_reg <= store_axi_wstrb;
                    d_stall         <= 1'b1;

                    // Debug, có thể xóa sau khi pass
                    $display("[DMEM WRITE REQ] t=%0t addr=%h memop=%b raw_wdata=%h axi_wdata=%h wstrb=%b",
                             $time, Mem_AddrM, MemOpM, Mem_WriteDataM, store_axi_wdata, store_axi_wstrb);
                end
            end
        end
    end

endmodule