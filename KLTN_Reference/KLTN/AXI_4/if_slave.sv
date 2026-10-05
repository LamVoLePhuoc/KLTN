module if_slave (
    // Clock and Reset
    input           clk,
    input           rst_n,
    
    // Write Address Channel (AW)
    input           AWVALID,
    output reg      AWREADY,
    input  [31:0]   AWADDR,
    input  [7:0]    AWLEN,
    input  [2:0]    AWSIZE,
    input  [1:0]    AWBURST,
    input  [3:0]    AWID,
    input  [2:0]    AWPROT,
    input  [3:0]    AWCACHE,
    input           AWLOCK,
    input  [3:0]    AWQOS,
    input  [3:0]    AWREGION,
    
    // Write Data Channel (W)
    input           WVALID,
    output reg      WREADY,
    input  [255:0]  WDATA,
    input  [31:0]   WSTRB,
    input           WLAST,
    input  [3:0]    WID,
    
    // Write Response Channel (B)
    output reg      BVALID,
    input           BREADY,
    output [1:0]    BRESP,
    output [3:0]    BID,
    
    // Read Address Channel (AR)
    input           ARVALID,
    output reg      ARREADY,
    input  [63:0]   ARADDR,  // 63->32: i-mem, 31->0: d-mem
    input  [7:0]    ARLEN,
    input  [2:0]    ARSIZE,
    input  [1:0]    ARBURST,
    input  [3:0]    ARID,
    input  [2:0]    ARPROT,
    input  [3:0]    ARCACHE,
    input           ARLOCK,
    input  [3:0]    ARQOS,
    input  [3:0]    ARREGION,
    
    // Read Data Channel (R)
    output reg      RVALID,
    input           RREADY,
    output [511:0]  RDATA,  // 511->256: i-mem, 255->0: d-mem
    output [1:0]    RRESP,
    output          RLAST,
    output [3:0]    RID,
    
    // Connection to I Main Memory
    output reg          i_mem_ren,
    output reg [31:0]   i_mem_addr,
    input  [255:0]      i_mem_rdata,
    // Connection to D Main Memory
    output reg          d_mem_wen,
    output reg          d_mem_ren,
    output reg [31:0]   d_mem_addr,
    output reg [255:0]  d_mem_wdata,
    input  [255:0]      d_mem_rdata
);

    timeunit 1ns; timeprecision 1ps;	

    // Default response
    assign BRESP = 2'b00; // OKAY
    assign RRESP = 2'b00; // OKAY
    
    // State variables for write transaction
    reg [31:0] write_addr;
    reg [7:0]  write_len;
    reg [2:0]  write_size;
    reg [1:0]  write_burst;
    reg [3:0]  write_id;
    reg [7:0]  write_count;

    // State variables for read transaction
    reg [63:0] read_addr;    // 63->32: i-mem, 31->0: d-mem
    reg [7:0]  read_len;
    reg [2:0]  read_size;
    reg [1:0]  read_burst;
    reg [3:0]  read_id;
    reg [7:0]  read_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            AWREADY <= 1'b0;
            WREADY  <= 1'b0;
            BVALID  <= 1'b0;
            d_mem_wen <= 1'b0;
            write_count <= 8'b0;
            ARREADY <= 1'b0;
            RVALID  <= 1'b0;
            i_mem_ren <= 1'b0;
            d_mem_ren <= 1'b0;
            read_count <= 8'b0;
            d_mem_addr <= '0;
            d_mem_wdata <= '0;
            i_mem_addr <= '0;
        end 
        else begin
            // Handle AW channel
            if (AWVALID && !AWREADY) begin
                AWREADY <= 1'b1;
                write_addr <= AWADDR;
                write_len  <= AWLEN;
                write_size <= AWSIZE;
                write_burst <= AWBURST;
                write_id   <= AWID;
                write_count <= 8'b0;
                WREADY <= 1'b1; // Ready to receive data
            end else begin
                AWREADY <= 1'b0;
            end
            
            // Handle W channel
            if (WVALID && WREADY) begin
                d_mem_wen <= 1'b1;
                d_mem_addr <= write_addr;
                // Handle WSTRB to perform byte-wise write
                d_mem_wdata <= WDATA & {
                    {8{WSTRB[31]}},
                    {8{WSTRB[30]}},
                    {8{WSTRB[29]}},
                    {8{WSTRB[28]}},
                    {8{WSTRB[27]}},
                    {8{WSTRB[26]}},
                    {8{WSTRB[25]}},
                    {8{WSTRB[24]}},
                    {8{WSTRB[23]}},
                    {8{WSTRB[22]}},
                    {8{WSTRB[21]}},
                    {8{WSTRB[20]}},
                    {8{WSTRB[19]}},
                    {8{WSTRB[18]}},
                    {8{WSTRB[17]}},
                    {8{WSTRB[16]}},
                    {8{WSTRB[15]}},
                    {8{WSTRB[14]}},
                    {8{WSTRB[13]}},
                    {8{WSTRB[12]}},
                    {8{WSTRB[11]}},
                    {8{WSTRB[10]}},
                    {8{WSTRB[9]}},
                    {8{WSTRB[8]}},
                    {8{WSTRB[7]}},
                    {8{WSTRB[6]}},
                    {8{WSTRB[5]}},
                    {8{WSTRB[4]}},
                    {8{WSTRB[3]}},
                    {8{WSTRB[2]}},
                    {8{WSTRB[1]}},
                    {8{WSTRB[0]}}
                };
                // Update address based on burst type
                case (write_burst)
                    2'b00: write_addr <= write_addr; // FIXED
                    2'b01: write_addr <= write_addr + (1 << write_size); // INCR
                    2'b10: begin // WRAP (simple assumption)
                        if (write_count == write_len)
                            write_addr <= write_addr - (write_len << write_size);
                        else
                            write_addr <= write_addr + (1 << write_size);
                    end
                    default: write_addr <= write_addr;
                endcase
                write_count <= write_count + 1;
                if (WLAST) begin
                    WREADY <= 1'b0;
                    BVALID <= 1'b1;
                end
            end else begin
                d_mem_wen <= 1'b0;
            end
            
            // Handle B channel
            if (BVALID && BREADY) begin   
                BVALID <= 1'b0;
            end

            // Handle AR channel
            if (ARVALID && !ARREADY) begin
                ARREADY <= 1'b1;
                read_addr <= ARADDR;
                read_len  <= ARLEN;
                read_size <= ARSIZE;
                read_burst <= ARBURST;
                read_id   <= ARID;
                read_count <= 8'b0;
                RVALID <= 1'b1; // Ready to send data
            end 
            else begin
                ARREADY <= 1'b0;
            end
            
            // Handle R channel
            if (RVALID && RREADY) begin
                i_mem_ren <= 1'b1;
                d_mem_ren <= 1'b1;
                i_mem_addr <= read_addr[63:32];
                d_mem_addr <= read_addr[31:0];
                // Update address based on burst type
                case (read_burst)
                    2'b00: read_addr <= read_addr; // FIXED
                    2'b01: read_addr <= read_addr + (1 << read_size); // INCR
                    2'b10: begin // WRAP (simple assumption)
                        if (read_count == read_len)
                            read_addr <= read_addr - (read_len << read_size);
                        else
                            read_addr <= read_addr + (1 << read_size);
                    end
                    default: read_addr <= read_addr;
                endcase
                read_count <= read_count + 1;
                if (read_count == (read_len + 1)) begin
                    RVALID <= 1'b0;
                end
            end else begin
                i_mem_ren <= 1'b0;
                d_mem_ren <= 1'b0;
            end
        end
    end
    
    // Output signal assignments
    assign RLAST = (read_count == read_len + 1);
    assign RID = read_id;
    assign BID = write_id;
    assign RDATA = {i_mem_rdata, d_mem_rdata};
endmodule
