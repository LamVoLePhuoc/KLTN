`timescale 1ns / 1ps

// AXI4-Lite register file for soc_dma_controller.
//
//   0x00 CONTROL  W bit0=start, bit1=clear sticky done/error
//   0x04 STATUS   R bit0=busy, bit1=done, bit2=error, bits[10:8]=code
//   0x08 SRC_ADDR R/W
//   0x0C DST_ADDR R/W
//   0x10 LENGTH   R/W byte count (non-zero and bus-width aligned)
//
// AW and W are accepted independently, as required by AXI4-Lite.  A start
// request remains asserted until the cache/DMA coordinator accepts it.
module axi_lite_dma_regs (
    input  wire        clk,
    input  wire        rst,

    input  wire [5:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [5:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    output wire        request_valid,
    input  wire        request_ready,
    output reg  [31:0] request_src_addr,
    output reg  [31:0] request_dst_addr,
    output reg  [31:0] request_length_bytes,

    input  wire        status_busy,
    input  wire        status_done_pulse,
    input  wire        status_error,
    input  wire [2:0]  status_error_code,
    output wire        done_sticky,
    output wire        error_sticky,
    output wire [2:0]  error_code_sticky
);
    reg aw_hold;
    reg [5:0] awaddr_hold;
    reg w_hold;
    reg [31:0] wdata_hold;
    reg [3:0] wstrb_hold;
    reg start_pending;
    reg done_sticky_r;
    reg error_sticky_r;
    reg [2:0] error_code_sticky_r;

    assign s_axi_awready = !aw_hold && !s_axi_bvalid;
    assign s_axi_wready  = !w_hold && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    assign request_valid = start_pending;
    assign done_sticky = done_sticky_r;
    assign error_sticky = error_sticky_r;
    assign error_code_sticky = error_code_sticky_r;

    function [31:0] merge_wstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0] byte_enable;
        integer j;
        begin
            merge_wstrb = old_value;
            for (j = 0; j < 4; j = j + 1)
                if (byte_enable[j])
                    merge_wstrb[j*8 +: 8] = new_value[j*8 +: 8];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            aw_hold                 <= 1'b0;
            awaddr_hold             <= 6'd0;
            w_hold                  <= 1'b0;
            wdata_hold              <= 32'd0;
            wstrb_hold              <= 4'd0;
            s_axi_bresp             <= 2'b00;
            s_axi_bvalid            <= 1'b0;
            s_axi_rdata             <= 32'd0;
            s_axi_rresp             <= 2'b00;
            s_axi_rvalid            <= 1'b0;
            request_src_addr        <= 32'd0;
            request_dst_addr        <= 32'd0;
            request_length_bytes    <= 32'd0;
            start_pending           <= 1'b0;
            done_sticky_r           <= 1'b0;
            error_sticky_r          <= 1'b0;
            error_code_sticky_r     <= 3'd0;
        end
        else begin
            if (s_axi_awvalid && s_axi_awready) begin
                aw_hold     <= 1'b1;
                awaddr_hold <= s_axi_awaddr;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                w_hold     <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
            end

            if (aw_hold && w_hold && !s_axi_bvalid) begin
                aw_hold      <= 1'b0;
                w_hold       <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;

                case (awaddr_hold[5:2])
                    4'h0: begin
                        if (wstrb_hold[0] && wdata_hold[1]) begin
                            done_sticky_r       <= 1'b0;
                            error_sticky_r      <= 1'b0;
                            error_code_sticky_r <= 3'd0;
                        end
                        if (wstrb_hold[0] && wdata_hold[0]) begin
                            if (!status_busy && !start_pending)
                                start_pending <= 1'b1;
                            else begin
                                done_sticky_r       <= 1'b1;
                                error_sticky_r      <= 1'b1;
                                error_code_sticky_r <= 3'd5;
                            end
                        end
                    end
                    4'h2: request_src_addr <= merge_wstrb(request_src_addr,
                                                          wdata_hold, wstrb_hold);
                    4'h3: request_dst_addr <= merge_wstrb(request_dst_addr,
                                                          wdata_hold, wstrb_hold);
                    4'h4: request_length_bytes <= merge_wstrb(request_length_bytes,
                                                              wdata_hold, wstrb_hold);
                    default: s_axi_bresp <= 2'b10;
                endcase
            end
            else if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (start_pending && request_ready)
                start_pending <= 1'b0;

            if (status_done_pulse) begin
                done_sticky_r       <= 1'b1;
                error_sticky_r      <= status_error;
                error_code_sticky_r <= status_error ? status_error_code : 3'd0;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= 2'b00;
                case (s_axi_araddr[5:2])
                    4'h0: s_axi_rdata <= 32'd0;
                    4'h1: s_axi_rdata <= {21'd0, error_code_sticky_r,
                                           5'd0, error_sticky_r,
                                           done_sticky_r,
                                           (status_busy | start_pending)};
                    4'h2: s_axi_rdata <= request_src_addr;
                    4'h3: s_axi_rdata <= request_dst_addr;
                    4'h4: s_axi_rdata <= request_length_bytes;
                    default: begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= 2'b10;
                    end
                endcase
            end
            else if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end
endmodule
