`timescale 1ps/1ps

module fetch(
    input             clk,          // Clock
    input             rst_n,    // Reset (active low)
    input   [1:0]     pc_sel,    // Select PC source
    input   [31:0]    branch_taken,  // Branch taken
    input   [31:0]    wb_data,  // ALU result from Execute
    output  [31:0]    pc,          // PC hiện tại
    output  [31:0]    instr,       // Instruction fetched từ I-Cache
    output  [31:0]    pc_plus_4,  // PC + 4

    input  [255:0]   mem_rdata,  // Memory read data
    input            mem_ready,  // Memory ready
    output [31:0]    mem_req_addr,  // Memory request address
    output           mem_req_read,  // Memory request read
    output           mem_req_write,  // Memory request write
    output [255:0]   mem_req_wdata  // Memory request write data

);

    reg [31:0] pc_reg;
    wire [31:0] pc_src;

    assign pc_plus_4 = pc_reg + 32'h00000004;
    // assign pc_src = (pc_sel == 2'b00) ? pc_plus_4 : 
    //                 (pc_sel == 2'b01) ? wb_data : 
    //                 (pc_sel == 2'b10) ? branch_taken : pc_reg;

    mux_pc mux_pc_inst(
        .pc_plus_4(pc_plus_4),
        .wb_data(wb_data),
        .branch_taken(branch_taken),
        .pc_sel(pc_sel),
        .pc_src(pc_src)
    );

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            pc_reg <= 32'h00000000;
        end else begin
            pc_reg <= pc_src;
        end
    end

    assign pc = pc_reg;

    wire [31:0] cpu_addr;
    wire [31:0] cpu_wdata;
    wire cpu_read, cpu_write;
    wire [31:0] cpu_rdata;
    wire cpu_ready;

    assign cpu_read = 1'b1;
    assign cpu_write = 1'b0;
    assign cpu_addr = pc_reg;
    assign cpu_wdata = 32'h00000000;

    wire rst = ~rst_n;

    Cache ICache_inst(
        .clk(clk),
        .reset(rst),
        .cpu_addr(cpu_addr),
        .cpu_read(cpu_read),
        .cpu_write(cpu_write),
        .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata),
        .cpu_ready(cpu_ready),
        .mem_req_addr(mem_req_addr),
        .mem_req_read(mem_req_read),
        .mem_req_write(mem_req_write),
        .mem_req_wdata(mem_req_wdata),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    assign instr = cpu_rdata;

endmodule

module mux_pc(
    input [31:0] pc_plus_4,
    input [31:0] wb_data,
    input [31:0] branch_taken,
    input [1:0] pc_sel,
    output [31:0] pc_src
);
    reg [31:0] pc_src;
    always @(*) begin
        case(pc_sel)
            2'b00: pc_src = pc_plus_4;
            2'b01: pc_src = wb_data;
            2'b10: pc_src = branch_taken;
            2'b11: pc_src = 32'h00000000;
            default: pc_src = 32'h00000000;
        endcase
    end
endmodule

//reg_file[0] <= 32'b0;
//            reg_file[1] <= 32'b0;
//            reg_file[2] <= 32'b0;
//            reg_file[3] <= 32'b0;
//            reg_file[4] <= 32'b0;
//            reg_file[5] <= 32'b0;
//            reg_file[6] <= 32'b0;
//            reg_file[7] <= 32'b0;
//            reg_file[8] <= 32'b0;
//            reg_file[9] <= 32'b0;
//            reg_file[10] <= 32'b0;
//            reg_file[11] <= 32'b0;
//            reg_file[12] <= 32'b0;
//            reg_file[13] <= 32'b0;
//            reg_file[14] <= 32'b0;
//            reg_file[15] <= 32'b0;
//            reg_file[16] <= 32'b0;
//            reg_file[17] <= 32'b0;
//            reg_file[18] <= 32'b0;
//            reg_file[19] <= 32'b0;
//            reg_file[20] <= 32'b0;
//            reg_file[21] <= 32'b0;
//            reg_file[22] <= 32'b0;
//            reg_file[23] <= 32'b0;
//            reg_file[24] <= 32'b0;
//            reg_file[25] <= 32'b0;
//            reg_file[26] <= 32'b0;
//            reg_file[27] <= 32'b0;
//            reg_file[28] <= 32'b0;
//            reg_file[29] <= 32'b0;
//            reg_file[30] <= 32'b0;
//            reg_file[31] <= 32'b0;
