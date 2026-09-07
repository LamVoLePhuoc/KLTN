`timescale 1ps/1ps

module rv32i(
    input           clk, 
    input           rst_n,
    // i-mem interface
    input [255:0]   imem_rdata,
    input           imem_ready,
    output [31:0]   imem_req_addr,
    output          imem_req_read,
    output          imem_req_write,
    output [255:0]  imem_req_wdata,
    // d-mem interfacce
    input  [255:0]  dmem_rdata,
    input           dmem_ready,
    output [31:0]   dmem_req_addr,
    output          dmem_req_read,
    output          dmem_req_write,
    output [255:0]  dmem_req_wdata

);

    // Khai báo các tín hiệu nội bộ
    // Các tín hiệu từ Fetch
    wire [31:0] alu_result, pc_plus_4, pc, instr;
    // Các tín hiệu từ Decode
    wire [31:0] wb_data, rs1_data, rs2_data, imm;
    wire        reg_write_en;
    wire [1:0]  pc_sel;
    // Các tín hiệu liên quan đến control từ Decode/Controller
    wire [31:0]	branch_taken;
    wire [3:0]  alu_op;          // Giả sử alu_op 4 bit, có thể đi�?u chỉnh theo yêu cầu
    wire        mem_read, mem_write;
    wire [1:0]  wb_sel;          // Giả sử wb_sel 2 bit
    wire        a_sel, b_sel, br_un;
    wire [9:0]  branch_signal, ls_sel;
    // Các tín hiệu từ Memory Access và Write Back
    wire [31:0] data_mem;
    wire [31:0] wb_data_out;

    // Module Fetch: Lấy lệnh từ bộ nhớ và cập nhật PC
    fetch fetch_inst(
        .clk(clk),
        .rst_n(rst_n),
        .pc_sel(pc_sel),
        .branch_taken(branch_taken),
        .wb_data(wb_data_out),
        .pc(pc),
        .instr(instr),
        .pc_plus_4(pc_plus_4),
        // Kết nối với bộ nhớ bên ngoài
        .mem_rdata(imem_rdata),
        .mem_ready(imem_ready),
        .mem_req_addr(imem_req_addr),
        .mem_req_read(imem_req_read),
        .mem_req_write(imem_req_write),
        .mem_req_wdata(imem_req_wdata)
    );

    // Module Decode: Giải mã lệnh và đi�?u khiển tín hiệu
    decode decode_inst(
        .clk(clk),
        .rst_n(rst_n),
        .reg_write_en(reg_write_en),
        .instr(instr),
        .wb_data(wb_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .imm(imm),
        // Các tín hiệu đi�?u khiển cho các module tiếp theo
        .alu_op(alu_op),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .wb_sel(wb_sel),
        .pc_sel(pc_sel),
        .a_sel(a_sel),
        .b_sel(b_sel),
        .ls_sel(ls_sel),
        .branch_signal(branch_signal),
        .br_un(br_un)
    );

    // Module Execute: Thực hiện các phép tính và tính toán nhánh
    execute execute_inst(
        .DataA(rs1_data),
        .DataB(rs2_data),
        .alu_op(alu_op),
        .Imm(imm),
        .PC(pc),
        .a_sel(a_sel),
        .b_sel(b_sel),
        .br_un(br_un),
        .alu_result(alu_result),
        .branch_taken(branch_taken),
        .branch_signal(branch_signal)
    );

    // Module Memory Access: Truy cập bộ nhớ dữ liệu
    memory_access memory_access_inst(
        .clk(clk),
        .rst_n(rst_n),
        .ls_sel(ls_sel),
        .data_write(rs2_data),
        .addr(alu_result),
        .data_read(data_mem),
        // Kết nối với bộ nhớ bên ngoài
        .mem_req_addr(dmem_req_addr),
        .mem_req_read(dmem_req_read),
        .mem_req_write(dmem_req_write),
        .mem_req_wdata(dmem_req_wdata),
        .mem_rdata(dmem_rdata),
        .mem_ready(dmem_ready)
    );

    // Module Write Back: Ghi dữ liệu kết quả vào thanh ghi     
    write_back write_back_inst(
        .alu_result(alu_result),
        .data_mem(data_mem),
        .pc_plus_4(pc_plus_4),
        .wb_sel(wb_sel),
        .wb_data_out(wb_data_out)
    );

endmodule
