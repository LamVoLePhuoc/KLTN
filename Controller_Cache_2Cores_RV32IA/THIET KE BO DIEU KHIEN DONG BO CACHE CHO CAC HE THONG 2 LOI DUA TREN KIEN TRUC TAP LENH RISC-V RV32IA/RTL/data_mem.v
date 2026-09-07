`timescale 1ns/1ps
// from Lee Min Hunz with luv
module data_mem #(
    parameter DATA_W        = 32,
    parameter NUM_SETS      = 16,
    parameter WORD_OFF_W   = 4,
    parameter INDEX_W       = $clog2(NUM_SETS),
    parameter CACHE_DATA_W  = (1<<WORD_OFF_W) * 32,
    parameter STRB_W        = (DATA_W/8)
)(
    input                           clk
// ,   input                           rst_n 
,   input   [INDEX_W-1:0]           read_index
,   input   [INDEX_W-1:0]           write_index

    // refill nguyen 1 line
,   input                           refill_we
,   input   [CACHE_DATA_W-1:0]      refill_din

    // ghi 32 bit
,   input                           cpu_we
,   input   [DATA_W-1:0]            cpu_din
,   input   [STRB_W-1:0]            cpu_wstrb
,   input   [WORD_OFF_W-1:0]        cpu_offset
    
,   output reg  [CACHE_DATA_W-1:0]  dout
);

    reg [CACHE_DATA_W-1:0] data_mem [0:NUM_SETS-1];
    integer i;
    // always @(posedge clk or negedge rst_n) begin
    //     if (~rst_n) begin
    //         for (i = 0; i < NUM_SETS; i = i + 1) begin
    //             data_mem[i] <= {CACHE_DATA_W{1'b0}};
    //         end
    //         dout <= {CACHE_DATA_W{1'b0}};
    //     end 
    //     else begin
    //         if (refill_we) begin
    //             data_mem[write_index] <= refill_din;
    //         end 
    //         else begin
    //             if (cpu_we) begin
    //                 if (cpu_wstrb[0]) 
    //                     data_mem[write_index][cpu_offset*DATA_W + 0 +: 8]   <= cpu_din[7:0];
    //                 if (cpu_wstrb[1]) 
    //                     data_mem[write_index][cpu_offset*DATA_W + 8 +: 8]   <= cpu_din[15:8];
    //                 if (cpu_wstrb[2]) 
    //                     data_mem[write_index][cpu_offset*DATA_W + 16 +: 8]  <= cpu_din[23:16];
    //                 if (cpu_wstrb[3]) 
    //                     data_mem[write_index][cpu_offset*DATA_W + 24 +: 8]  <= cpu_din[31:24];
    //             end 
    //         end 
    //         dout <= data_mem[read_index];
    //     end
    // end

    initial begin
        for (i = 0; i < NUM_SETS; i = i + 1) begin
            data_mem[i] = {CACHE_DATA_W{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (refill_we) begin
            data_mem[write_index] <= refill_din;
        end 
        else begin
            if (cpu_we) begin
                if (cpu_wstrb[0]) 
                    data_mem[write_index][cpu_offset*DATA_W + 0 +: 8]   <= cpu_din[7:0];
                if (cpu_wstrb[1]) 
                    data_mem[write_index][cpu_offset*DATA_W + 8 +: 8]   <= cpu_din[15:8];
                if (cpu_wstrb[2]) 
                    data_mem[write_index][cpu_offset*DATA_W + 16 +: 8]  <= cpu_din[23:16];
                if (cpu_wstrb[3]) 
                    data_mem[write_index][cpu_offset*DATA_W + 24 +: 8]  <= cpu_din[31:24];
            end 
        end 
        dout <= data_mem[read_index];
    
    end

    // assign dout = cache_data_mem[index];
endmodule