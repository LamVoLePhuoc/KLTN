`timescale 1ns / 1ps

// APB4 programming/status register file for soc_dma_controller.
//
//   0x00 CONTROL  W bit0=start, bit1=clear sticky done/error
//   0x04 STATUS   R bit0=busy, bit1=done, bit2=error, bits[10:8]=code
//   0x08 SRC_ADDR R/W
//   0x0C DST_ADDR R/W
//   0x10 LENGTH   R/W byte count (non-zero and bus-width aligned)
//
// The slave is zero-wait-state: PREADY is permanently high.  State changes
// occur exactly once in the APB ACCESS phase (PSEL && PENABLE).  PSTRB makes
// the block APB4-compatible; an APB3 integration may tie it to 4'b1111.
module apb_dma_regs (
    input  wire        pclk,
    input  wire        presetn,

    input  wire [5:0]  paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    input  wire [3:0]  pstrb,
    input  wire [2:0]  pprot,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

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
    wire access_phase = psel && penable;
    wire aligned      = (paddr[1:0] == 2'b00);
    wire address_valid = aligned &&
                         ((paddr[5:2] == 4'h0) ||
                          (paddr[5:2] == 4'h1) ||
                          (paddr[5:2] == 4'h2) ||
                          (paddr[5:2] == 4'h3) ||
                          (paddr[5:2] == 4'h4));
    wire write_valid = (paddr[5:2] == 4'h0) ||
                       (paddr[5:2] == 4'h2) ||
                       (paddr[5:2] == 4'h3) ||
                       (paddr[5:2] == 4'h4);

    reg start_pending;
    reg done_sticky_r;
    reg error_sticky_r;
    reg [2:0] error_code_sticky_r;

    // PPROT is intentionally accepted for APB4 interface compatibility.  The
    // DMA control page has no privilege/security distinction in this design.
    wire unused_pprot = ^pprot;

    assign pready            = 1'b1;
    assign pslverr           = access_phase &&
                               (!address_valid || (pwrite && !write_valid));
    assign request_valid     = start_pending;
    assign done_sticky       = done_sticky_r;
    assign error_sticky      = error_sticky_r;
    assign error_code_sticky = error_code_sticky_r;

    function [31:0] merge_pstrb;
        input [31:0] old_value;
        input [31:0] new_value;
        input [3:0]  byte_enable;
        integer j;
        begin
            merge_pstrb = old_value;
            for (j = 0; j < 4; j = j + 1)
                if (byte_enable[j])
                    merge_pstrb[j*8 +: 8] = new_value[j*8 +: 8];
        end
    endfunction

    always @(*) begin
        case (paddr[5:2])
            4'h0: prdata = 32'd0;
            4'h1: prdata = {21'd0, error_code_sticky_r, 5'd0,
                             error_sticky_r, done_sticky_r,
                             (status_busy | start_pending)};
            4'h2: prdata = request_src_addr;
            4'h3: prdata = request_dst_addr;
            4'h4: prdata = request_length_bytes;
            default: prdata = 32'd0;
        endcase
    end

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            request_src_addr     <= 32'd0;
            request_dst_addr     <= 32'd0;
            request_length_bytes <= 32'd0;
            start_pending        <= 1'b0;
            done_sticky_r        <= 1'b0;
            error_sticky_r       <= 1'b0;
            error_code_sticky_r  <= 3'd0;
        end
        else begin
            if (access_phase && pwrite && address_valid && write_valid) begin
                case (paddr[5:2])
                    4'h0: begin
                        if (pstrb[0] && pwdata[1]) begin
                            done_sticky_r       <= 1'b0;
                            error_sticky_r      <= 1'b0;
                            error_code_sticky_r <= 3'd0;
                        end
                        if (pstrb[0] && pwdata[0]) begin
                            if (!status_busy && !start_pending)
                                start_pending <= 1'b1;
                            else begin
                                done_sticky_r       <= 1'b1;
                                error_sticky_r      <= 1'b1;
                                error_code_sticky_r <= 3'd5;
                            end
                        end
                    end
                    4'h2: request_src_addr <= merge_pstrb(request_src_addr,
                                                          pwdata, pstrb);
                    4'h3: request_dst_addr <= merge_pstrb(request_dst_addr,
                                                          pwdata, pstrb);
                    4'h4: request_length_bytes <= merge_pstrb(request_length_bytes,
                                                              pwdata, pstrb);
                    default: ;
                endcase
            end

            if (start_pending && request_ready)
                start_pending <= 1'b0;

            if (status_done_pulse) begin
                done_sticky_r       <= 1'b1;
                error_sticky_r      <= status_error;
                error_code_sticky_r <= status_error ? status_error_code : 3'd0;
            end
        end
    end

endmodule
