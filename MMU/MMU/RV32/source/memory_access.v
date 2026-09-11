`timescale 1ps/1ps

module memory_access(
    clk, 
    rst_n, 
    ls_sel, 
    data_write, 
    addr, 
    data_read, 
    mem_rdata, 
    mem_ready,
    mem_req_addr, 
    mem_req_read, 
    mem_req_write, 
    mem_req_wdata
);
    input clk, rst_n;
    input [9:0] ls_sel;
    input [31:0] data_write;
    input [31:0] addr;
    output [31:0] data_read;
    output [31:0] mem_req_addr;
    output        mem_req_read;
    output        mem_req_write;
    output [255:0] mem_req_wdata;
    input  [255:0] mem_rdata;
    input         mem_ready;
    
    // Control signals for read/write based on ls_sel.
    reg [31:0] cpu_addr;
    reg [31:0] cpu_wdata;
    reg cpu_read, cpu_write;
    // Change cpu_rdata to a wire to connect with the Cache output.
    wire [31:0] cpu_rdata;

    always @(*) begin
        case (ls_sel)
            // Load instructions: set to read
            10'b0000011000: begin // lb
                cpu_addr  = addr;
                cpu_wdata = data_write; // Not used in read
                cpu_read  = 1'b1;
                cpu_write = 1'b0;
            end
            10'b0000011001: begin // lh
                cpu_addr  = addr;
                cpu_wdata = data_write;
                cpu_read  = 1'b1;
                cpu_write = 1'b0;
            end
            10'b0000011010: begin // lw
                cpu_addr  = addr;
                cpu_wdata = data_write;
                cpu_read  = 1'b1;
                cpu_write = 1'b0;
            end
            10'b0000011011: begin // lbu
                cpu_addr  = addr;
                cpu_wdata = data_write;
                cpu_read  = 1'b1;
                cpu_write = 1'b0;
            end
            10'b0000011100: begin // lhu
                cpu_addr  = addr;
                cpu_wdata = data_write;
                cpu_read  = 1'b1;
                cpu_write = 1'b0;
            end
            // Store instructions: set to write
            10'b0000011101: begin // sb
                cpu_addr  = addr;
                cpu_wdata = data_write;
                cpu_read  = 1'b0;
                cpu_write = 1'b1;
            end
            10'b0000011110: begin // sh
                cpu_addr  = addr;
                cpu_wdata = data_write;
                cpu_read  = 1'b0;
                cpu_write = 1'b1;
            end
            10'b0000011111: begin // sw
                cpu_addr  = addr;
                cpu_wdata = data_write;
                cpu_read  = 1'b0;
                cpu_write = 1'b1;
            end
            default: begin
                cpu_addr  = addr;
                cpu_wdata = data_write;
                cpu_read  = 1'b0;
                cpu_write = 1'b0;
            end
        endcase
    end

    // Connect to DCache module
    wire rst = ~rst_n;
    Cache DCache_inst(
        .clk(clk),
        .reset(rst),
        .cpu_addr(cpu_addr),
        .cpu_read(cpu_read),
        .cpu_write(cpu_write),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(mem_ready),
        .mem_req_addr(mem_req_addr),
        .mem_req_read(mem_req_read),
        .mem_req_write(mem_req_write),
        .mem_req_wdata(mem_req_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    assign data_read = cpu_rdata;

endmodule
