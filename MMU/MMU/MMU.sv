module MMU (
    input          clk,
    input          rst_n,
    
    // CPU interface
    input  [31:0]  i_cpu_addr,
    output [31:0]  i_cpu_rdata,
    output         i_cpu_ready,

    input          d_cpu_mem_st_en,
    input          d_cpu_mem_ld_en,
    input  [11:0]  d_cpu_mem_addr,
    input  [3:0]   d_cpu_mem_byte_en,
    input  [2:0]   d_cpu_mem_ld_sel,
    input  [63:0]  d_cpu_mem_st_data,
    output [63:0]  d_cpu_mem_ld_data,

    input          d_fpu_mem_ld_sel,
    input          d_fpu_mem_wren,
    input  [11:0]  d_fpu_mem_addr,
    input  [63:0]  d_fpu_mem_din,
    output [63:0]  d_fpu_mem_dout,

    // D-side ready (asserted when the load/store issued this cycle has
    // completed: cache hit in the same cycle, or miss handling finished).
    output         d_cpu_ready,

    // Module Wrapper interface (AXI-4)
    output [31:0]  i_mem_req_addr,
    output         i_mem_req_read,
    output         i_mem_req_write,
    output [255:0] i_mem_req_wdata,
    input  [255:0] i_mem_rdata,
    input          i_mem_ready,

    output [31:0]  d_mem_req_addr,
    output         d_mem_req_read,
    output         d_mem_req_write,
    output [255:0] d_mem_req_wdata,
    input  [255:0] d_mem_rdata,
    input          d_mem_ready,

    // Phase-2 coherence snoop-invalidate passthrough to the private
    // D-cache (see TagArray.sv / D_Cache.sv). Driven by the interconnect
    // when a sibling core writes a line this core may have cached.
    input          snoop_en,
    input  [31:0]  snoop_addr
);
    
    timeunit 1ns; timeprecision 1ps;

    wire reset;
    wire [31:0] i_cpu_wdata;
    wire i_cpu_read, i_cpu_write;

    logic [31:0] d_cpu_addr;
    logic        d_cpu_read;
    logic        d_cpu_write;
    logic [63:0] d_cpu_wdata;
    logic [63:0] d_cpu_rdata;

    assign reset = ~rst_n;
    assign i_cpu_read = 1'b1;
    assign i_cpu_write = 1'b0;
    assign i_cpu_wdata = 32'h00000000;

    I_Cache I_Cache (
        .clk(clk),
        .reset(reset),
        .cpu_addr(i_cpu_addr),
        .cpu_read(i_cpu_read),
        .cpu_write(i_cpu_write),
        .cpu_wdata(i_cpu_wdata),
        .cpu_rdata(i_cpu_rdata),
        .cpu_ready(i_cpu_ready),
        .mem_req_addr(i_mem_req_addr),
        .mem_req_read(i_mem_req_read),
        .mem_req_write(i_mem_req_write),
        .mem_req_wdata(i_mem_req_wdata),
        .mem_rdata(i_mem_rdata),
        .mem_ready(i_mem_ready)
    );

    lsu_controller lsu_ctrl (
        .cpu_mem_st_en(d_cpu_mem_st_en),
        .cpu_mem_ld_en(d_cpu_mem_ld_en),
        .cpu_mem_addr(d_cpu_mem_addr),
        .cpu_mem_byte_en(d_cpu_mem_byte_en),
        .cpu_mem_ld_sel(d_cpu_mem_ld_sel),
        .cpu_mem_st_data(d_cpu_mem_st_data),
        .cpu_mem_ld_data(d_cpu_mem_ld_data),
        .fpu_mem_ld_sel(d_fpu_mem_ld_sel),
        .fpu_mem_wren(d_fpu_mem_wren),
        .fpu_mem_addr(d_fpu_mem_addr),
        .fpu_mem_din(d_fpu_mem_din),
        .fpu_mem_dout(d_fpu_mem_dout),
        .d_cpu_addr(d_cpu_addr),
        .d_cpu_read(d_cpu_read),
        .d_cpu_write(d_cpu_write),
        .d_cpu_wdata(d_cpu_wdata),
        .d_cpu_rdata(d_cpu_rdata)
    );

    D_Cache D_Cache (
        .clk(clk),
        .reset(reset),
        .cpu_addr(d_cpu_addr),
        .cpu_read(d_cpu_read),
        .cpu_write(d_cpu_write),
        .cpu_wdata(d_cpu_wdata),
        .cpu_rdata(d_cpu_rdata),
        .cpu_ready(d_cpu_ready),
        .mem_req_addr(d_mem_req_addr),
        .mem_req_read(d_mem_req_read),
        .mem_req_write(d_mem_req_write),
        .mem_req_wdata(d_mem_req_wdata),
        .mem_rdata(d_mem_rdata),
        .mem_ready(d_mem_ready),
        .snoop_en(snoop_en),
        .snoop_addr(snoop_addr)
    );

endmodule: MMU

module lsu_controller (
    input  logic        cpu_mem_st_en,
    input  logic        cpu_mem_ld_en,
    input  logic [11:0] cpu_mem_addr,
    input  logic [3:0]  cpu_mem_byte_en,
    input  logic [2:0]  cpu_mem_ld_sel,
    input  logic [63:0] cpu_mem_st_data,
    output logic [63:0] cpu_mem_ld_data,

    input  logic        fpu_mem_ld_sel,
    input  logic        fpu_mem_wren,
    input  logic [11:0] fpu_mem_addr,
    input  logic [63:0] fpu_mem_din,
    output logic [63:0] fpu_mem_dout,

    output logic [31:0] d_cpu_addr,
    output logic        d_cpu_read,
    input  logic [63:0] d_cpu_rdata,
    output logic        d_cpu_write,
    output logic [63:0] d_cpu_wdata
);

    timeunit 1ns; timeprecision 1ps;

    logic [3:0]  byte_en;
    logic [2:0]  ld_sel;
    logic [63:0] st_data;
    logic [63:0] ld_data;
    
    logic [63:0] LD;
    logic [31:0] LW, LWU;
    logic [7:0]  LB, LBU;
    logic [15:0] LH, LHU;

    assign d_cpu_write     = cpu_mem_st_en | fpu_mem_wren;
    assign d_cpu_read      = cpu_mem_ld_en | fpu_mem_ld_sel;
    assign d_cpu_addr      = (fpu_mem_ld_sel | fpu_mem_wren) ? {20'd0, fpu_mem_addr} : {20'd0, cpu_mem_addr};
    assign byte_en         = (fpu_mem_wren) ? 4'b0111 : cpu_mem_byte_en;
    assign ld_sel          = (fpu_mem_ld_sel) ? 3'h3 : cpu_mem_ld_sel;
    assign st_data         = (fpu_mem_wren) ? fpu_mem_din : cpu_mem_st_data;
    assign cpu_mem_ld_data = (cpu_mem_ld_en) ? ld_data : '0;
    assign fpu_mem_dout    = (fpu_mem_ld_sel) ? ld_data : '0;

    always_comb begin
        if (cpu_mem_st_en | fpu_mem_wren) begin
            if (byte_en == 4'b0001) begin
                d_cpu_wdata = st_data[7:0];
            end
            else if (byte_en == 4'b0011) begin
                d_cpu_wdata = st_data[15:0];
            end
            else if (byte_en == 4'b1111) begin
                d_cpu_wdata = st_data[31:0];
            end
            else if (byte_en == 4'b0111) begin
                d_cpu_wdata = st_data[63:0];
            end
            else begin
                d_cpu_wdata = st_data;
            end
        end 
        else begin 
            d_cpu_wdata = st_data;
        end                   
    end

    assign LD  = d_cpu_rdata;
    assign LW  = d_cpu_rdata[31:0];
    assign LWU = d_cpu_rdata[31:0];
    assign LB  = d_cpu_rdata[7:0];
    assign LBU = d_cpu_rdata[7:0];
    assign LH  = d_cpu_rdata[15:0];
    assign LHU = d_cpu_rdata[15:0];
    
    always_comb begin
        if (ld_sel == 3'h0) begin
            ld_data = {56'b0, LBU};
        end 
        else if (ld_sel == 3'h1) begin
            ld_data = {48'b0, LHU};
        end 
        else if (ld_sel == 3'h2) begin
            ld_data = {{56{LB[7]}}, LB};
        end 
        else if (ld_sel == 3'h3) begin
            ld_data = LD;
        end 
        else if (ld_sel == 3'h4) begin
            ld_data = {{48{LH[15]}}, LH};
        end 
        else if (ld_sel == 3'h5) begin
            ld_data = {32'b0, LWU};
        end 
        else if (ld_sel == 3'h6) begin
            ld_data = {{32{LW[31]}}, LW};
        end 
        else begin
            ld_data = LD;
        end
    end

endmodule: lsu_controller