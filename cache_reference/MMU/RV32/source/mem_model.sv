`timescale 1ps / 1ps
//
// mem_model256: simple behavioral backing memory for simulation only.
// Presents the same 256-bit "AXI-like" request/response interface that
// MMU.sv's I_Cache / D_Cache drive (mem_req_addr/read/write/wdata ->
// mem_rdata/mem_ready), with a fixed multi-cycle latency so the core's
// stall logic (see core_top.sv) is actually exercised in simulation.
// Not meant to represent the final DRAM/L2 timing — only to unblock
// Phase-1 bring-up without the (currently broken) AXI crossbar in
// AXI_Interconnect.v / sdram_wrapper.v.
//
module mem_model256 #(
    parameter LINES      = 256,   // number of 32-byte lines => 8KB
    parameter LAT_CYCLES = 2      // extra wait cycles before mem_ready (>=0)
) (
    input               clk,
    input               rst_n,

    input        [31:0] mem_req_addr,
    input               mem_req_read,
    input               mem_req_write,
    input        [255:0] mem_req_wdata,
    output       [255:0] mem_rdata,
    output               mem_ready
);

    localparam IDX_W = $clog2(LINES);

    reg [255:0] line_mem [0:LINES-1];

    reg               busy;
    reg [7:0]         cnt;
    reg               ready_r;
    wire [IDX_W-1:0]  line_idx = mem_req_addr[IDX_W+4:5];

    assign mem_rdata = line_mem[line_idx];
    assign mem_ready = ready_r;

    integer ri;
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            busy    <= 1'b0;
            cnt     <= 8'd0;
            ready_r <= 1'b0;
            // Phase-2 fix: without this, every never-yet-written line
            // stays X (Verilog's default for an uninitialized reg array),
            // and an X read back into a branch condition (e.g. the
            // multicore coherence testbench's SHARED_FLAG spin-wait)
            // produces undefined control flow instead of "flag not set
            // yet." Real DRAM/BRAM doesn't guarantee zero on power-up
            // either, but for a simulation model this is much closer to
            // sane behavior than leaving everything X.
            for (ri = 0; ri < LINES; ri = ri + 1) line_mem[ri] <= 256'b0;
        end else begin
            ready_r <= 1'b0;
            if (!busy) begin
                if (mem_req_read || mem_req_write) begin
                    busy <= 1'b1;
                    cnt  <= LAT_CYCLES[7:0];
                end
            end else begin
                if (cnt == 8'd0) begin
                    busy    <= 1'b0;
                    ready_r <= 1'b1;
                    if (mem_req_write) begin
                        line_mem[line_idx] <= mem_req_wdata;
                    end
                end else begin
                    cnt <= cnt - 8'd1;
                end
            end
        end
    end

    // Test helper: preload one 32-bit word at a byte address, respecting
    // the big-endian-within-line word layout used by I_CacheController /
    // D_CacheController (offset 0 -> bits[255:224], offset 7 -> bits[31:0]).
    task automatic preload_word(input [31:0] addr, input [31:0] word);
        integer li, off;
        begin
            li  = addr[IDX_W+4:5];
            off = addr[4:2];
            line_mem[li][255 - 32*off -: 32] = word;
        end
    endtask

endmodule
