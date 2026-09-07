    `timescale 1ns / 1ps
// from Lee Min Hunz with luv
// ============================================================================
// FIFO - First-In-First-Out Buffer
// ============================================================================
// Synchronous FIFO with configurable width and depth.
// Uses wrap-around pointers with MSB for full/empty detection.
// ============================================================================
module FIFO #(
    parameter DATA_W = 32,
    parameter DEPTH  = 8,
    parameter ADDR_W = $clog2(DEPTH)
)(
    input               clk, rst_n
,   input               push
,   input               pop
,   input [DATA_W-1:0]  din

,   output              empty
,   output              full
,   output [DATA_W-1:0] dout
);
        reg [DATA_W-1:0]    mem [0:DEPTH-1];
        reg [ADDR_W:0]      wptr, rptr;

        integer i;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                wptr <= 0;
                rptr <= 0;
                for (i = 0; i < DEPTH; i = i + 1) begin
                    mem[i] <= 0;
                end
            end 
            // else begin
            //     if (push && !full) begin
            //         mem[wptr]   <= din;
            //         wptr        <= wptr + 1;
            //     end
            //     if (pop && !empty) begin
            //         // dout <= mem[rptr];
            //         rptr <= rptr + 1;
            //     end
            // end
            else begin
                if (push && !full) begin
                    // CHỈ SỬ DỤNG CÁC BIT ĐỊA CHỈ: [ADDR_W-1:0]
                    mem[wptr[ADDR_W-1:0]]   <= din;
                    wptr                    <= wptr + 1;
                end
                if (pop && !empty) begin
                    rptr <= rptr + 1;
                end
            end
        end

        // Full: pointers differ only in MSB (write wrapped, read hasn't)
        assign full     = (wptr[ADDR_W] != rptr[ADDR_W]) && (wptr[ADDR_W-1:0] == rptr[ADDR_W-1:0]);
        // Empty: pointers are equal
        assign empty    = (wptr == rptr);
        // Combinational read output
        assign dout     = mem[rptr[ADDR_W-1:0]];
        
        wire [31:0] test = rptr[ADDR_W-1:0];
    endmodule 