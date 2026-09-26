`timescale 1ns / 1ps

module load_unit (
    input  wire [31:0] raw_data,     // dữ liệu 32-bit đọc từ RAM
    input  wire [1:0]  addr_offset,  // địa chỉ byte: addr[1:0]
    input  wire [2:0]  mem_op,       // funct3 của load
    output reg  [31:0] load_data
);

    reg [7:0]  selected_byte;
    reg [15:0] selected_half;

    always @(*) begin
        case (addr_offset)
            2'b00: selected_byte = raw_data[7:0];
            2'b01: selected_byte = raw_data[15:8];
            2'b10: selected_byte = raw_data[23:16];
            2'b11: selected_byte = raw_data[31:24];
            default: selected_byte = 8'b0;
        endcase

        case (addr_offset[1])
            1'b0: selected_half = raw_data[15:0];
            1'b1: selected_half = raw_data[31:16];
            default: selected_half = 16'b0;
        endcase

        case (mem_op)
            3'b000: load_data = {{24{selected_byte[7]}}, selected_byte}; // LB
            3'b001: load_data = {{16{selected_half[15]}}, selected_half}; // LH
            3'b010: load_data = raw_data;                                // LW
            3'b100: load_data = {24'b0, selected_byte};                   // LBU
            3'b101: load_data = {16'b0, selected_half};                   // LHU
            default: load_data = raw_data;
        endcase
    end

endmodule