`timescale 1ns / 1ps

module RV32IMFA_IP_Wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_0000
)(
    // ==========================================================
    // 1. GLOBAL SIGNALS (Chuẩn AXI dùng Active-Low Reset)
    // ==========================================================
    input wire ACLK,
    input wire ARESETN,

    // ==========================================================
    // 2. DUAL-CORE SNOOPING & DEBUG (Thò ra ngoài)
    // ==========================================================
    input  wire [31:0] Snoop_Addr,
    input  wire        Snoop_WE,
  

    // ==========================================================
    // 3. AXI4 MASTER INTERFACE: INSTRUCTION MEMORY (READ ONLY)
    // ==========================================================
    // -- Read Address Channel (AR)
    output wire [31:0] M_AXI_IMEM_ARADDR,
    output wire [7:0]  M_AXI_IMEM_ARLEN,
    output wire [2:0]  M_AXI_IMEM_ARSIZE,
    output wire [1:0]  M_AXI_IMEM_ARBURST,
    output wire        M_AXI_IMEM_ARVALID,
    input  wire        M_AXI_IMEM_ARREADY,
    // -- Read Data Channel (R)
    input  wire [31:0] M_AXI_IMEM_RDATA,
    input  wire [1:0]  M_AXI_IMEM_RRESP,
    input  wire        M_AXI_IMEM_RLAST,
    input  wire        M_AXI_IMEM_RVALID,
    output wire        M_AXI_IMEM_RREADY,

    // ==========================================================
    // 4. AXI4 MASTER INTERFACE: DATA MEMORY (READ/WRITE)
    // ==========================================================
    // -- Write Address Channel (AW)
    output wire [31:0] M_AXI_DMEM_AWADDR,
    output wire [7:0]  M_AXI_DMEM_AWLEN,
    output wire [2:0]  M_AXI_DMEM_AWSIZE,
    output wire [1:0]  M_AXI_DMEM_AWBURST,
    output wire        M_AXI_DMEM_AWVALID,
    input  wire        M_AXI_DMEM_AWREADY,
    // -- Write Data Channel (W)
    output wire [31:0] M_AXI_DMEM_WDATA,
    output wire [3:0]  M_AXI_DMEM_WSTRB,
    output wire        M_AXI_DMEM_WLAST,
    output wire        M_AXI_DMEM_WVALID,
    input  wire        M_AXI_DMEM_WREADY,
    // -- Write Response Channel (B)
    input  wire [1:0]  M_AXI_DMEM_BRESP,
    input  wire        M_AXI_DMEM_BVALID,
    output wire        M_AXI_DMEM_BREADY,
    // -- Read Address Channel (AR)
    output wire [31:0] M_AXI_DMEM_ARADDR,
    output wire [7:0]  M_AXI_DMEM_ARLEN,
    output wire [2:0]  M_AXI_DMEM_ARSIZE,
    output wire [1:0]  M_AXI_DMEM_ARBURST,
    output wire        M_AXI_DMEM_ARVALID,
    input  wire        M_AXI_DMEM_ARREADY,
    // -- Read Data Channel (R)
    input  wire [31:0] M_AXI_DMEM_RDATA,
    input  wire [1:0]  M_AXI_DMEM_RRESP,
    input  wire        M_AXI_DMEM_RLAST,
    input  wire        M_AXI_DMEM_RVALID,
    output wire        M_AXI_DMEM_RREADY
);

    // ==========================================================
    // SIGNALS NỘI BỘ NỐI VỚI CPU
    // ==========================================================
    wire rst = ~ARESETN; // CPU dùng Active-High reset
    
    wire [31:0] PCF;
    reg  [31:0] InstrF_reg;
    
    wire [31:0] Mem_AddrM;
    wire [31:0] Mem_WriteDataM;
    wire        Mem_WriteEnM;
    wire        Mem_ReadEnM;
    reg  [31:0] Mem_ReadDataM_reg;

    wire        Stall_Core_External;
    reg         i_stall; // Stall do Instruction Cache/Bus
    reg         d_stall; // Stall do Data Cache/Bus

    // Core dừng khi 1 trong 2 Bus đang bận xử lý
    assign Stall_Core_External = i_stall | d_stall;

    // ==========================================================
    // KHỞI TẠO LÕI CPU CỦA BẠN (INSTANCE)
    // ==========================================================
    RV32IMFA #(
        .RESET_ADDR(RESET_ADDR)
    ) core (
        .clk(ACLK),
        .rst(rst),
        .Stall_Core_External(Stall_Core_External),
        .Snoop_Addr(Snoop_Addr),
        .Snoop_WE(Snoop_WE),
        
        .PCF(PCF),
        .InstrF(M_AXI_IMEM_RVALID ? M_AXI_IMEM_RDATA : InstrF_reg), // Lấy data trực tiếp nếu Valid, không thì lấy trong Reg
        
        .Mem_AddrM(Mem_AddrM),
        .Mem_WriteDataM(Mem_WriteDataM),
        .Mem_WriteEnM(Mem_WriteEnM),
        .Mem_ReadEnM(Mem_ReadEnM),
        .Mem_ReadDataM(M_AXI_DMEM_RVALID ? M_AXI_DMEM_RDATA : Mem_ReadDataM_reg),
        
        .ResultW(ResultW),
        .ALU_ResultE_Debug(ALU_ResultE_Debug)
    );

    // ==========================================================
    // BRIDGE 1: INSTRUCTION MEMORY AXI MASTER (FSM)
    // ==========================================================
    assign M_AXI_IMEM_ARLEN   = 8'd0;    // Single beat
    assign M_AXI_IMEM_ARSIZE  = 3'b010;  // 4 bytes
    assign M_AXI_IMEM_ARBURST = 2'b01;   // INCR
    
    reg imem_arvalid;
    assign M_AXI_IMEM_ARVALID = imem_arvalid;
    assign M_AXI_IMEM_ARADDR  = PCF;
    assign M_AXI_IMEM_RREADY  = 1'b1; // Luôn sẵn sàng nhận lệnh

    reg [31:0] last_pcf;

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            imem_arvalid <= 1'b0;
            i_stall      <= 1'b1;
            last_pcf     <= 32'hFFFF_FFFF;
            InstrF_reg   <= 32'd0;
        end else begin
            // Nếu địa chỉ PC thay đổi, bắt đầu yêu cầu mới
            if (PCF != last_pcf && !Stall_Core_External) begin
                imem_arvalid <= 1'b1;
                i_stall      <= 1'b1;
                last_pcf     <= PCF;
            end 
            // Tắt ARVALID khi Slave đã nhận ARADDR
            else if (M_AXI_IMEM_ARREADY && imem_arvalid) begin
                imem_arvalid <= 1'b0;
            end

            // Khi Slave trả Data về
            if (M_AXI_IMEM_RVALID) begin
                InstrF_reg <= M_AXI_IMEM_RDATA; // Lưu lại lệnh
                i_stall    <= 1'b0;             // Hết stall
            end
        end
    end

    // ==========================================================
    // BRIDGE 2: DATA MEMORY AXI MASTER (FSM)
    // ==========================================================
    // Cài đặt cứng các tham số cho Single-Beat
    assign M_AXI_DMEM_AWLEN   = 8'd0;
    assign M_AXI_DMEM_AWSIZE  = 3'b010; // 32-bit = 4 bytes
    assign M_AXI_DMEM_AWBURST = 2'b01;
    assign M_AXI_DMEM_ARLEN   = 8'd0;
    assign M_AXI_DMEM_ARSIZE  = 3'b010;
    assign M_AXI_DMEM_ARBURST = 2'b01;
    
    // Gán dữ liệu Ghi
    assign M_AXI_DMEM_AWADDR  = Mem_AddrM;
    assign M_AXI_DMEM_WDATA   = Mem_WriteDataM;
    assign M_AXI_DMEM_WSTRB   = 4'b1111; // Ghi toàn bộ 32-bit (Vì core của bạn dùng Mem_WriteEnM 1 bit)
    assign M_AXI_DMEM_WLAST   = 1'b1;
    assign M_AXI_DMEM_ARADDR  = Mem_AddrM;

    reg dmem_awvalid, dmem_wvalid, dmem_bready;
    reg dmem_arvalid, dmem_rready;

    assign M_AXI_DMEM_AWVALID = dmem_awvalid;
    assign M_AXI_DMEM_WVALID  = dmem_wvalid;
    assign M_AXI_DMEM_BREADY  = dmem_bready;
    assign M_AXI_DMEM_ARVALID = dmem_arvalid;
    assign M_AXI_DMEM_RREADY  = dmem_rready;

    // FSM Trạng thái Data Memory
    localparam D_IDLE = 3'd0, D_WRITE_ADDR_DATA = 3'd1, D_WRITE_RESP = 3'd2;
    localparam D_READ_REQ = 3'd3, D_READ_WAIT = 3'd4;
    reg [2:0] d_state;

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            d_state      <= D_IDLE;
            dmem_awvalid <= 1'b0;
            dmem_wvalid  <= 1'b0;
            dmem_bready  <= 1'b0;
            dmem_arvalid <= 1'b0;
            dmem_rready  <= 1'b0;
            d_stall      <= 1'b0;
            Mem_ReadDataM_reg <= 32'd0;
        end else begin
            case (d_state)
                D_IDLE: begin
                    d_stall <= 1'b0;
                    if (Mem_WriteEnM) begin
                        // Khởi tạo quy trình Ghi
                        d_stall      <= 1'b1; // Bắt CPU đứng im
                        dmem_awvalid <= 1'b1;
                        dmem_wvalid  <= 1'b1;
                        d_state      <= D_WRITE_ADDR_DATA;
                    end else if (Mem_ReadEnM) begin
                        // Khởi tạo quy trình Đọc
                        d_stall      <= 1'b1; // Bắt CPU đứng im
                        dmem_arvalid <= 1'b1;
                        dmem_rready  <= 1'b1;
                        d_state      <= D_READ_REQ;
                    end
                end

                // --- LUỒNG GHI ---
                D_WRITE_ADDR_DATA: begin
                    if (M_AXI_DMEM_AWREADY) dmem_awvalid <= 1'b0;
                    if (M_AXI_DMEM_WREADY)  dmem_wvalid  <= 1'b0;
                    
                    if ((!dmem_awvalid || M_AXI_DMEM_AWREADY) && (!dmem_wvalid || M_AXI_DMEM_WREADY)) begin
                        dmem_bready <= 1'b1;
                        d_state     <= D_WRITE_RESP;
                    end
                end
                
                D_WRITE_RESP: begin
                    if (M_AXI_DMEM_BVALID) begin
                        dmem_bready <= 1'b0;
                        d_stall     <= 1'b0; // Giải phóng CPU
                        d_state     <= D_IDLE;
                    end
                end

                // --- LUỒNG ĐỌC ---
                D_READ_REQ: begin
                    if (M_AXI_DMEM_ARREADY) begin
                        dmem_arvalid <= 1'b0;
                        d_state      <= D_READ_WAIT;
                    end
                end

                D_READ_WAIT: begin
                    if (M_AXI_DMEM_RVALID) begin
                        Mem_ReadDataM_reg <= M_AXI_DMEM_RDATA;
                        dmem_rready       <= 1'b0;
                        d_stall           <= 1'b0; // Giải phóng CPU
                        d_state           <= D_IDLE;
                    end
                end
            endcase
        end
    end

endmodule