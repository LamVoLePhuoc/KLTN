`timescale 1ps/1ps

module write_back(
    input [31:0] alu_result, data_mem, pc_plus_4,
    input [1:0] wb_sel,
    output reg [31:0] wb_data_out
);
    // Phase-1 fix: aligned with decode.v's Controller encoding, which was
    // previously mismatched (LOAD used wb_sel=2'b10 expecting data_mem,
    // but this module returned pc_plus_4 for that code; JAL/JALR used
    // wb_sel=2'b11 expecting pc_plus_4, but this module's default
    // returned 0). Both bugs silently broke loads and jump-and-link.
    always @(*) begin
        case(wb_sel)
            2'b00: wb_data_out = data_mem;    // unused today (S/B-type don't write rd)
            2'b01: wb_data_out = alu_result;  // R/I/LUI/AUIPC
            2'b10: wb_data_out = data_mem;    // LOAD
            2'b11: wb_data_out = pc_plus_4;   // JAL / JALR
            default: wb_data_out = 32'h0;
        endcase
    end

endmodule