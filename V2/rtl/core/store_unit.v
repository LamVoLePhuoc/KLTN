`timescale 1ns / 1ps

module store_unit (
    input  wire [31:0] store_data,   // dữ liệu cần ghi từ core
    input  wire [1:0]  addr_offset,  // địa chỉ byte: addr[1:0]
    input  wire [2:0]  mem_op,       // funct3 của store
    output reg  [31:0] axi_wdata,
    output reg  [3:0]  axi_wstrb
);

    always @(*) begin
        axi_wdata = store_data;
        axi_wstrb = 4'b0000;

        case (mem_op)
            3'b000: begin // SB
                axi_wstrb = 4'b0001 << addr_offset;
                axi_wdata = store_data << (8 * addr_offset);
            end

            3'b001: begin // SH
                if (addr_offset[1] == 1'b0) begin
                    axi_wstrb = 4'b0011;
                    axi_wdata = store_data;
                end else begin
                    axi_wstrb = 4'b1100;
                    axi_wdata = store_data << 16;
                end
            end

            3'b010: begin // SW
                axi_wstrb = 4'b1111;
                axi_wdata = store_data;
            end

            default: begin
                axi_wstrb = 4'b0000;
                axi_wdata = store_data;
            end
        endcase
    end

endmodule