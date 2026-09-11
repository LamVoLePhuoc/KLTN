module if_master (
    // Clock and Reset
    input           clk,
    input           rst_n,

    // RV32I i-mem interface
    input  [31:0]   imem_req_addr,
    input           imem_req_read,
    input           imem_req_write,
    input  [255:0]  imem_req_wdata,
    output [255:0]  imem_rdata,
    output          imem_ready,

    // RV32I d-mem interface
    input  [31:0]   dmem_req_addr,
    input           dmem_req_read,
    input           dmem_req_write,
    input  [255:0]  dmem_req_wdata,
    output [255:0]  dmem_rdata,
    output          dmem_ready,

    // AXI-4 Master Write Channels
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

    // AXI-4 Master Read Channels
    output          ARVALID,
    input           ARREADY,
    output [31:0]   ARADDR,
    output [7:0]    ARLEN,
    output [2:0]    ARSIZE,
    output [1:0]    ARBURST,
    output [3:0]    ARID,
    // Read Data Channel
    input           RVALID,
    output          RREADY,
    input  [255:0]  RDATA,
    input  [1:0]    RRESP,
    input           RLAST,
    input  [3:0]    RID
);

    // Logic for i-mem and d-mem transactions
    reg [1:0] state; // States: 0 = idle, 1 = i-mem, 2 = d-mem
    localparam IDLE = 2'b00, IMEM = 2'b01, DMEM = 2'b10;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            case (state)
                IDLE: begin
                    if (imem_req_read || imem_req_write)
                        state <= IMEM;
                    else if (dmem_req_read || dmem_req_write)
                        state <= DMEM;
                end
                IMEM: begin
                    if ((imem_req_write && BVALID) || (imem_req_read && RVALID && RLAST))
                        state <= IDLE;
                end
                DMEM: begin
                    if ((dmem_req_write && BVALID) || (dmem_req_read && RVALID && RLAST))
                        state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end

    // Write Address Channel
    assign AWVALID = (state == IMEM) ? imem_req_write : (state == DMEM) ? dmem_req_write : 1'b0;
    assign AWADDR = (state == IMEM) ? imem_req_addr : dmem_req_addr;
    assign AWLEN = 8'b0;        // Burst length = 1
    assign AWSIZE = 3'b111;     // 256-bit (2^8 bytes = 32 bytes)
    assign AWBURST = 2'b00;     // FIXED burst type
    assign AWID = (state == IMEM) ? 4'b0000 : 4'b0001; // Different IDs for i-mem and d-mem

    // Write Data Channel
    assign WVALID = (state == IMEM) ? imem_req_write : (state == DMEM) ? dmem_req_write : 1'b0;
    assign WDATA = (state == IMEM) ? imem_req_wdata : dmem_req_wdata;
    assign WSTRB = 32'hFFFFFFFF; // Write entire 256-bit data
    assign WLAST = 1'b1;         // Single transaction
    assign WID = (state == IMEM) ? 4'b0000 : 4'b0001;

    // Write Response Channel
    assign BREADY = 1'b1; // Always ready to receive response

    // Read Address Channel
    assign ARVALID = (state == IMEM) ? imem_req_read : (state == DMEM) ? dmem_req_read : 1'b0;
    assign ARADDR = (state == IMEM) ? imem_req_addr : dmem_req_addr;
    assign ARLEN = 8'b0;        // Burst length = 1
    assign ARSIZE = 3'b111;     // 256-bit
    assign ARBURST = 2'b00;     // FIXED burst type
    assign ARID = (state == IMEM) ? 4'b0000 : 4'b0001;

    // Read Data Channel
    assign RREADY = 1'b1; // Always ready to receive data

    // Output to RV32I
    assign imem_rdata = (state == IMEM && RVALID) ? RDATA : 256'b0;
    assign dmem_rdata = (state == DMEM && RVALID) ? RDATA : 256'b0;
    assign imem_ready = (state == IMEM) && ((imem_req_read && RVALID && RLAST) || (imem_req_write && BVALID));
    assign dmem_ready = (state == DMEM) && ((dmem_req_read && RVALID && RLAST) || (dmem_req_write && BVALID));

endmodule
