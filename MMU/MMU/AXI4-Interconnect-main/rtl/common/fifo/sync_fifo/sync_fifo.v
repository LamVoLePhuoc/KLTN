// Second, separately-named synchronous FIFO used by sa_Ax_channel.v (as
// opposed to the plain "fifo" module dsp_Ax_channel.v uses -- this repo's
// original AXI4-Interconnect-main source refers to two distinct module
// names, "fifo" and "sync_fifo", both of which were missing; see fifo.v in
// this same directory for the other one). FIFO_TYPE is accepted for
// interface compatibility (callers pass 2, "Full flop") but does not
// change behavior here -- this implementation is already fully registered.
// wr_ready_o/rd_ready_o are the natural complements of full_o/empty_o.
module sync_fifo #(
    parameter FIFO_TYPE  = 2,
    parameter DATA_WIDTH = 8,
    parameter FIFO_DEPTH = 8,
    parameter ADDR_W     = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH),
    parameter CNT_W      = ADDR_W + 1
)(
    input                        clk,
    input                        rst_n,
    input      [DATA_WIDTH-1:0]  data_i,
    input                        wr_valid_i,
    input                        rd_valid_i,
    output     [DATA_WIDTH-1:0]  data_o,
    output                       empty_o,
    output                       full_o,
    output                       wr_ready_o,
    output                       rd_ready_o,
    output                       almost_empty_o,
    output                       almost_full_o,
    output     [CNT_W-1:0]       counter
);

    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    reg [ADDR_W-1:0]     wr_ptr;
    reg [ADDR_W-1:0]     rd_ptr;
    reg [CNT_W-1:0]      cnt;

    wire wr_en = wr_valid_i & ~full_o;
    wire rd_en = rd_valid_i & ~empty_o;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_W{1'b0}};
            rd_ptr <= {ADDR_W{1'b0}};
            cnt    <= {CNT_W{1'b0}};
        end else begin
            if (wr_en) begin
                mem[wr_ptr] <= data_i;
                wr_ptr      <= (wr_ptr == FIFO_DEPTH-1) ? {ADDR_W{1'b0}} : wr_ptr + 1'b1;
            end
            if (rd_en) begin
                rd_ptr <= (rd_ptr == FIFO_DEPTH-1) ? {ADDR_W{1'b0}} : rd_ptr + 1'b1;
            end
            case ({wr_en, rd_en})
                2'b10:   cnt <= cnt + 1'b1;
                2'b01:   cnt <= cnt - 1'b1;
                default: cnt <= cnt;
            endcase
        end
    end

    assign data_o         = mem[rd_ptr];
    assign empty_o        = (cnt == {CNT_W{1'b0}});
    assign full_o         = (cnt == FIFO_DEPTH[CNT_W-1:0]);
    assign wr_ready_o     = ~full_o;
    assign rd_ready_o     = ~empty_o;
    assign almost_empty_o = (cnt == {{(CNT_W-1){1'b0}}, 1'b1});
    assign almost_full_o  = (cnt == FIFO_DEPTH[CNT_W-1:0] - 1'b1);
    assign counter        = cnt;

endmodule
