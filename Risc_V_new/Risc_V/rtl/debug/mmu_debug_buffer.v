`timescale 1ns / 1ps

// ============================================================
// mmu_debug_buffer
//
// Small circular trace buffer for MMU bring-up.  mmu_top places this
// module in a generate block only when DEBUG_TRACE_ENABLE=1.  Board
// builds use the default value 0, so the buffer is absent from the
// synthesized design instead of consuming RAM/logic permanently.
//
// Record format is intentionally opaque here; mmu_top documents how
// it packs each 80-bit translation event.  The read port is
// combinational so a testbench or an ILA-facing wrapper can inspect
// records without disturbing capture.
// ============================================================
module mmu_debug_buffer #(
    parameter integer DEPTH = 16,
    parameter integer ADDR_WIDTH = 4,
    parameter integer DATA_WIDTH = 80
)(
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  event_valid,
    input  wire [DATA_WIDTH-1:0] event_data,
    input  wire [ADDR_WIDTH-1:0] read_index,
    output wire [DATA_WIDTH-1:0] read_data,
    output wire [ADDR_WIDTH:0]   record_count,
    output wire [ADDR_WIDTH-1:0] write_index
);

    (* ram_style = "distributed" *) reg [DATA_WIDTH-1:0] trace_mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] write_ptr_r;
    reg [ADDR_WIDTH:0]   count_r;

    assign read_data    = trace_mem[read_index];
    assign record_count = count_r;
    assign write_index  = write_ptr_r;

    always @(posedge clk) begin
        if (rst) begin
            write_ptr_r <= {ADDR_WIDTH{1'b0}};
            count_r     <= {(ADDR_WIDTH+1){1'b0}};
        end
        else if (event_valid) begin
            trace_mem[write_ptr_r] <= event_data;
            write_ptr_r <= write_ptr_r + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
            if (count_r < DEPTH)
                count_r <= count_r + {{ADDR_WIDTH{1'b0}}, 1'b1};
        end
    end

endmodule
