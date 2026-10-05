module if_master (
    // Clock and Reset
    input           clk,
    input           rst_n,
    // i-mem interface
    input  [31:0]   imem_req_addr,
    input           imem_req_read,
    input           imem_req_write,
    input  [255:0]  imem_req_wdata,
    output [255:0]  imem_rdata,
    output          imem_ready,

    // d-mem interface
    input  [31:0]   dmem_req_addr,
    input           dmem_req_read,
    input           dmem_req_write,
    input  [255:0]  dmem_req_wdata,
    output [255:0]  dmem_rdata,
    output          dmem_ready,

    // Write Address Channel
    output          AWVALID,
    input           AWREADY,
    output [31:0]   AWADDR,
    output [7:0]    AWLEN,
    output [2:0]    AWSIZE,
    output [1:0]    AWBURST,
    output [3:0]    AWID,

    // Write Data Channel
    output          WVALID,
    input           WREADY,
    output [255:0]  WDATA,
    output [31:0]   WSTRB,
    output          WLAST,
    output [3:0]    WID,

    // Write Response Channel
    input           BVALID,
    output          BREADY,
    input  [1:0]    BRESP,
    input  [3:0]    BID,

    // Read Address Channel
    output          ARVALID,
    input           ARREADY,
    output [63:0]   ARADDR, // 63->32: i-mem, 31->0: d-mem
    output [7:0]    ARLEN,
    output [2:0]    ARSIZE,
    output [1:0]    ARBURST,
    output [3:0]    ARID,

    // Read Data Channel
    input           RVALID,
    output          RREADY,
    input  [511:0]  RDATA, // 511->256: i-mem, 255->0: d-mem
    input  [1:0]    RRESP,
    input           RLAST,
    input  [3:0]    RID
);

    timeunit 1ns; timeprecision 1ps;	

    // Logic for i-mem and d-mem transactions
    reg [1:0] state; // States: 0 = idle, 1 = i-mem, 2 = d-mem, 3 = both i-mem & d-mem read
    localparam IDLE = 2'b00, IMEM = 2'b01, DMEM = 2'b10, BOTH = 2'b11;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end 
        else begin
            case (state)
                IDLE: begin
                    if ((imem_req_read || imem_req_write) && !(dmem_req_read || dmem_req_write)) begin
                        state <= IMEM;
                    end
                    else if (!(imem_req_read || imem_req_write) && (dmem_req_read || dmem_req_write)) begin
                        state <= DMEM;
                    end
                    else if ((imem_req_read || imem_req_write) && (dmem_req_read || dmem_req_write)) begin
                        state <= BOTH;
                    end
                    else begin
                        state <= IDLE;
                    end
                end
                IMEM: begin
                    if ((imem_req_write && BVALID) || (imem_req_read && RVALID && RLAST)) begin
                        state <= IDLE;
                    end
                end
                DMEM: begin
                    if ((dmem_req_write && BVALID) || (dmem_req_read && RVALID && RLAST)) begin
                        state <= IDLE;
                    end
                end
                BOTH: begin
                    if ((imem_req_read && dmem_req_read && RVALID && RLAST) || (imem_req_read && dmem_req_write && RVALID && RLAST && BVALID)) begin
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

    // Write Address Channel
    assign AWVALID = (state == IMEM) ? imem_req_write : ((state == DMEM) | (state == BOTH)) ? dmem_req_write : 1'b0;
    assign AWADDR = (state == IMEM) ? imem_req_addr : dmem_req_addr;
    assign AWLEN = 8'b0;
    assign AWSIZE = 3'b101;
    assign AWBURST = 2'b00;
    assign AWID = (state == IMEM) ? 4'b0000 : 4'b0001; // Different IDs for i-mem and d-mem

    // Write Data Channel
    assign WVALID = (state == IMEM) ? imem_req_write : ((state == DMEM) | (state == BOTH)) ? dmem_req_write : 1'b0;
    assign WDATA = (state == IMEM) ? imem_req_wdata : dmem_req_wdata;
    assign WSTRB = 32'hFFFFFFFF; 
    assign WLAST = 1'b1;
    assign WID = (state == IMEM) ? 4'b0000 : 4'b0001;

    // Write Response Channel
    assign BREADY = 1'b1; // Always ready to receive response

    // Read Address Channel
    assign ARVALID = (state == IMEM) ? imem_req_read : ((state == DMEM) ? dmem_req_read : ((state == BOTH) ? (imem_req_read | dmem_req_read) : 1'b0));
    assign ARADDR[63:32] = ((state == IMEM) | (state == BOTH)) ? imem_req_addr : 32'd0;
    assign ARADDR[31:0]  = ((state == DMEM) | (state == BOTH)) ? dmem_req_addr : 32'd0;
    assign ARLEN = 8'b0;        // Burst length = 1
    assign ARSIZE = 3'b110;     // 2^6 bytes = 64 bytes = 512 bit
    assign ARBURST = 2'b00;     // FIXED burst type
    assign ARID = (state == IMEM) ? 4'b0000 : ((state == DMEM) ? 4'b0001 : 4'b0010);

    // Read Data Channel
    assign RREADY = 1'b1; // Always ready to receive data

    // Output to core
    assign imem_rdata = (((state == IMEM) || (state == BOTH)) && RVALID) ? RDATA[511:256] : 256'b0;
    assign dmem_rdata = (((state == DMEM) || (state == BOTH)) && RVALID) ? RDATA[255:0]   : 256'b0;
    assign imem_ready = ((state == IMEM) || (state == BOTH)) && ((imem_req_read && RVALID && RLAST) || (imem_req_write && BVALID)); 
    assign dmem_ready = ((state == DMEM) || (state == BOTH)) && ((dmem_req_read && RVALID && RLAST) || (dmem_req_write && BVALID)); 

endmodule
