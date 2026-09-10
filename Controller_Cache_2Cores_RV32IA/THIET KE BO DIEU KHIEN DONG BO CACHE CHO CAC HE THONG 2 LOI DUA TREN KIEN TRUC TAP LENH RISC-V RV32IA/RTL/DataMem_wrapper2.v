`timescale 1ns/1ps
// from Lee Min Hunz with luv
module DataMem_wrapper2 #(
    parameter FF_DEPTH      = 32            
,   parameter RAM_ADDR_W    = 16   
,   parameter DATA_W        = 32
,   parameter ADDR_W        = 32
,   parameter RESET_VALUE   = 0
,   parameter STRB_W        = DATA_W / 8
,   parameter INIT_FILE_A   = ""
,   parameter INIT_FILE_B   = ""
,   parameter INIT_IDX_A    = 0
,   parameter INIT_IDX_B    = 0
)(
    input   ACLK
,   input   ARESETn

    // =========================================================
    // NEW: AXI4-Lite Slave Channel (For Vitis overwrite RAM)
    // =========================================================
,   input  [ADDR_W-1:0] s_axi_lite_awaddr
,   input               s_axi_lite_awvalid
,   output              s_axi_lite_awready
,   input  [DATA_W-1:0] s_axi_lite_wdata
,   input  [STRB_W-1:0] s_axi_lite_wstrb
,   input               s_axi_lite_wvalid
,   output              s_axi_lite_wready
,   output [1:0]        s_axi_lite_bresp
,   output              s_axi_lite_bvalid
,   input               s_axi_lite_bready
,   input  [ADDR_W-1:0] s_axi_lite_araddr
,   input               s_axi_lite_arvalid
,   output              s_axi_lite_arready
,   output [DATA_W-1:0] s_axi_lite_rdata
,   output [1:0]        s_axi_lite_rresp
,   output              s_axi_lite_rvalid
,   input               s_axi_lite_rready

    // =========================================================
    // ORIGINAL: AXI4-Full Slave Channel (For Core)
    // =========================================================
,   input  [ADDR_W-1:0] i_axi_awaddr
,   input  [7:0]        i_axi_awlen
,   input  [2:0]        i_axi_awsize
,   input  [1:0]        i_axi_awburst
,   input               i_axi_awvalid
,   output              o_axi_awready
,   output              o_axi_wready
,   input  [DATA_W-1:0] i_axi_wdata
,   input  [STRB_W-1:0] i_axi_wstrb
,   input               i_axi_wlast
,   input               i_axi_wvalid
,   output [1:0]        o_axi_bresp
,   output              o_axi_bvalid
,   input               i_axi_bready
,   output              o_axi_arready
,   input  [ADDR_W-1:0] i_axi_araddr
,   input  [7:0]        i_axi_arlen
,   input  [2:0]        i_axi_arsize
,   input  [1:0]        i_axi_arburst
,   input               i_axi_arvalid
,   output [DATA_W-1:0] o_axi_rdata
,   output [1:0]        o_axi_rresp
,   output              o_axi_rlast
,   output              o_axi_rvalid
,   input               i_axi_rready
);

    // =========================================================
    // LOGIC AXI4-LITE SLAVE (Kết nối vào Port A của RAM)
    // =========================================================
    reg axi_awready, axi_wready, axi_bvalid;
    reg axi_arready, axi_rvalid;
    
    // Write handshake
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            axi_awready <= 0; 
            axi_wready  <= 0; 
            axi_bvalid  <= 0;
        end else begin
            if (~axi_awready && s_axi_lite_awvalid && s_axi_lite_wvalid) begin
                axi_awready <= 1'b1; 
                axi_wready  <= 1'b1;
            end 
            else begin
                axi_awready <= 1'b0; 
                axi_wready  <= 1'b0;
            end
        end
    end

    // Read handshake
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            axi_arready <= 0; 
            axi_rvalid <= 0;
        end else begin
            if (~axi_arready && s_axi_lite_arvalid) axi_arready <= 1'b1;
            else axi_arready <= 1'b0;
            
            if (axi_arready && s_axi_lite_arvalid && ~axi_rvalid) axi_rvalid <= 1'b1;
            else if (axi_rvalid && s_axi_lite_rready) axi_rvalid <= 1'b0;
        end
    end

    assign s_axi_lite_awready = axi_awready;
    assign s_axi_lite_wready  = axi_wready;
    assign s_axi_lite_bvalid  = s_axi_lite_bready;
    assign s_axi_lite_bresp   = 2'b00; // OKAY
    assign s_axi_lite_arready = axi_arready;
    assign s_axi_lite_rvalid  = axi_rvalid;
    assign s_axi_lite_rresp   = 2'b00; // OKAY

    // Cấp write enable cho RAM Port A
    wire lite_we = (axi_awready && s_axi_lite_awvalid && axi_wready && s_axi_lite_wvalid);
    wire [RAM_ADDR_W-1:0] lite_waddr = s_axi_lite_awaddr[RAM_ADDR_W-1+2 : 2]; // Dịch 2 bit vì địa chỉ AXI là Byte, RAM là Word
    wire [RAM_ADDR_W-1:0] lite_raddr = s_axi_lite_araddr[RAM_ADDR_W-1+2 : 2];


    // =========================================================
    // LOGIC CŨ CHO AXI4-FULL (Giữ nguyên, không đổi một dòng)
    // =========================================================
    localparam FF_AW_W = DATA_W + 8 + 3 + 2;
    localparam FF_W_W  = DATA_W + STRB_W + 1;
    localparam FF_B_W  = 2;
    localparam FF_AR_W = DATA_W + 8 + 3 + 2;
    localparam FF_R_W  = DATA_W + 2 + 1;

    wire [FF_AW_W - 1:0] fifo_aw_dout;
    wire [FF_W_W - 1:0]  fifo_w_dout; 
    wire [FF_B_W - 1:0]  fifo_b_dout;
    wire [FF_AR_W - 1:0] fifo_ar_dout;
    wire [FF_R_W - 1:0]  fifo_r_dout;

    wire fifo_aw_full, fifo_w_full, fifo_b_full, fifo_ar_full, fifo_r_full;
    wire fifo_aw_empty, fifo_w_empty, fifo_b_empty, fifo_ar_empty, fifo_r_empty;
    wire fifo_aw_pop, fifo_w_pop, fifo_b_pop, fifo_b_push, fifo_ar_pop, fifo_r_pop;
    wire fifo_aw_push, fifo_w_push, fifo_ar_push, fifo_r_push;

    wire control_awready, control_arready;
    wire core_write_en, core_read_en;
    wire [DATA_W-1:0] cnt_addr_write, cnt_addr_read;
    wire [DATA_W-1:0] ram_r_data_b;
    wire rvalid_from_mem, last_data_from_mem, ctrl_w_ready;

    wire [DATA_W-1:0] fifo_awaddr  = fifo_aw_dout[FF_AW_W-1 -: DATA_W];
    wire [1:0]        fifo_awburst = fifo_aw_dout[FF_AW_W-1 - DATA_W - 8 - 3 -: 2];
    wire [DATA_W-1:0] fifo_wdata   = fifo_w_dout[FF_W_W-1 -: DATA_W];
    wire [STRB_W-1:0] fifo_wstrb   = fifo_w_dout[FF_W_W-1 - DATA_W  -: STRB_W];
    wire              fifo_wlast   = fifo_w_dout[0];
    wire [DATA_W-1:0] fifo_araddr  = fifo_ar_dout[FF_AR_W-1 -: DATA_W];
    wire [7:0]        fifo_arlen   = fifo_ar_dout[FF_AR_W-1 - DATA_W -: 8];
    wire [2:0]        fifo_arsize  = fifo_ar_dout[FF_AR_W-1 - DATA_W - 8 -: 3];
    wire [1:0]        fifo_arburst = fifo_ar_dout[FF_AR_W-1 - DATA_W - 8 - 3 -: 2];

    assign o_axi_awready = ~fifo_aw_full;
    assign o_axi_wready  = ~fifo_w_full;
    assign o_axi_arready = ~fifo_ar_full;
    assign o_axi_bvalid  = ~fifo_b_empty;
    assign o_axi_bresp   = 2'b00; 
    assign o_axi_rvalid  = ~fifo_r_empty;
    assign o_axi_rdata   = fifo_r_dout[FF_R_W-1 -: DATA_W];
    assign o_axi_rresp   = fifo_r_dout[2:1];
    assign o_axi_rlast   = fifo_r_dout[0];

    assign fifo_aw_push  = ~fifo_aw_full & i_axi_awvalid;
    assign fifo_w_push   = ~fifo_w_full  & i_axi_wvalid;
    assign fifo_ar_push  = ~fifo_ar_full & i_axi_arvalid;

    assign fifo_w_pop       = core_write_en & ctrl_w_ready;
    wire write_burst_done   = core_write_en && fifo_wlast;
    assign fifo_b_push      = write_burst_done & ~fifo_b_full;
    assign fifo_aw_pop      = write_burst_done & ~fifo_b_full;
    assign fifo_b_pop       = i_axi_bready & ~fifo_b_empty;

    assign fifo_r_push   = rvalid_from_mem & ~fifo_r_full;
    assign fifo_ar_pop   = fifo_r_push && last_data_from_mem;
    assign fifo_r_pop    = i_axi_rready & ~fifo_r_empty;

    control_write #(.DATA_W(DATA_W)) u_control_write(
        .clk(ACLK), .rst_n(ARESETn), .awvalid(~fifo_aw_empty), .awready(control_awready),
        .awburst(fifo_awburst), .awaddr(fifo_awaddr), .wvalid(~fifo_w_empty), .wlast(fifo_wlast),
        .wready(ctrl_w_ready), .w_addr(cnt_addr_write), .write_en(core_write_en)
    );

    control_read #(.DATA_W(DATA_W)) u_control_read(
        .clk(ACLK), .rst_n(ARESETn), .arvalid(~fifo_ar_empty), .arready(control_arready),
        .arburst(fifo_arburst), .arlen(fifo_arlen), .araddr(fifo_araddr), .fifo_r_push_able(~fifo_r_full),
        .fifo_ar_full(fifo_ar_full), .r_addr(cnt_addr_read), .read_en(core_read_en), .last_data_from_mem(last_data_from_mem)
    );

    FIFO #(.DATA_W(FF_AW_W),    .DEPTH(FF_DEPTH)) u_AW_FIFO (.clk(ACLK), .rst_n(ARESETn), .push(fifo_aw_push),  .pop(fifo_aw_pop), .din({i_axi_awaddr, i_axi_awlen, i_axi_awsize, i_axi_awburst}), .empty(fifo_aw_empty), .full(fifo_aw_full), .dout(fifo_aw_dout));
    FIFO #(.DATA_W(FF_W_W),     .DEPTH(FF_DEPTH)) u_W_FIFO  (.clk(ACLK), .rst_n(ARESETn), .push(fifo_w_push),   .pop(fifo_w_pop), .din({i_axi_wdata, i_axi_wstrb, i_axi_wlast}), .empty(fifo_w_empty), .full(fifo_w_full), .dout(fifo_w_dout));
    FIFO #(.DATA_W(FF_B_W),     .DEPTH(FF_DEPTH)) u_B_FIFO  (.clk(ACLK), .rst_n(ARESETn), .push(fifo_b_push),   .pop(fifo_b_pop), .din(2'b00), .empty(fifo_b_empty), .full(fifo_b_full), .dout(fifo_b_dout));
    FIFO #(.DATA_W(FF_AR_W),    .DEPTH(FF_DEPTH)) u_AR_FIFO (.clk(ACLK), .rst_n(ARESETn), .push(fifo_ar_push),  .pop(fifo_ar_pop), .din({i_axi_araddr, i_axi_arlen, i_axi_arsize, i_axi_arburst}), .empty(fifo_ar_empty), .full(fifo_ar_full), .dout(fifo_ar_dout));
    FIFO #(.DATA_W(FF_R_W),     .DEPTH(FF_DEPTH)) u_R_FIFO  (.clk(ACLK), .rst_n(ARESETn), .push(fifo_r_push),   .pop(fifo_r_pop), .din({ram_r_data_b, 2'b00, last_data_from_mem}), .empty(fifo_r_empty), .full(fifo_r_full), .dout(fifo_r_dout));

    // =========================================================
    // INSTANTIATE TRUE DUAL-PORT RAM
    // =========================================================
    ram #(
        .ADDR_W         (RAM_ADDR_W)
    ,   .DATA_W         (DATA_W)
    ,   .RESET_VALUE    (RESET_VALUE)
    ,   .INIT_FILE_A    (INIT_FILE_A)
    ,   .INIT_FILE_B    (INIT_FILE_B)
    ,   .INIT_IDX_A     (INIT_IDX_A)
    ,   .INIT_IDX_B     (INIT_IDX_B)
    ) u_DataMem (
        .clk        (ACLK)
        
        // Port A: Giao tiếp với AXI4-Lite (Vitis)
    ,   .we_a       ({STRB_W{lite_we}} & s_axi_lite_wstrb)
    ,   .re_a       (axi_arready)
    ,   .addr_a     (lite_we ? lite_waddr : lite_raddr) // Dung chung cho Write/Read
    ,   .wdata_a    (s_axi_lite_wdata)
    ,   .rdata_a    (s_axi_lite_rdata)
    ,   .valid_a    () // Bỏ qua vi da dung AXI handshake

        // Port B: Giao tiếp với Core (AXI4-Full)
    ,   .we_b       ({STRB_W{core_write_en}} & fifo_wstrb)
    ,   .re_b       (core_read_en)
    ,   .addr_b     (core_write_en ? cnt_addr_write[RAM_ADDR_W-1:0] : cnt_addr_read[RAM_ADDR_W-1:0])
    ,   .wdata_b    (fifo_wdata)
    ,   .rdata_b    (ram_r_data_b)
    ,   .valid_b    (rvalid_from_mem)
    );

endmodule