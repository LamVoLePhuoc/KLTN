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
    input  [31:0]   WDATA,
    input  [3:0]    WSTRB,
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
    input  [31:0]   ARADDR,
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
    output [31:0]   RDATA,
    output [1:0]    RRESP,
    output          RLAST,
    output [3:0]    RID,
    
    // Connection to Main Memory
    output reg      mem_wen,
    output reg      mem_ren,
    output reg [31:0] mem_addr,
    output reg [31:0] mem_wdata,
    input  [31:0]   mem_rdata
);

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
    
    // Logic for write transaction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            AWREADY <= 1'b0;
            WREADY  <= 1'b0;
            BVALID  <= 1'b0;
            mem_wen <= 1'b0;
            write_count <= 8'b0;
        end else begin
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
                mem_wen <= 1'b1;
                mem_addr <= write_addr;
                // Handle WSTRB to perform byte-wise write
                mem_wdata <= WDATA & {{8{WSTRB[3]}}, {8{WSTRB[2]}}, {8{WSTRB[1]}}, {8{WSTRB[0]}}};
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
                mem_wen <= 1'b0;
            end
            
            // Handle B channel
            if (BVALID && BREADY) begin
                BVALID <= 1'b0;
            end
        end
    end
    
    // State variables for read transaction
    reg [31:0] read_addr;
    reg [7:0]  read_len;
    reg [2:0]  read_size;
    reg [1:0]  read_burst;
    reg [3:0]  read_id;
    reg [7:0]  read_count;
    
    // Logic for read transaction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ARREADY <= 1'b0;
            RVALID  <= 1'b0;
            mem_ren <= 1'b0;
            read_count <= 8'b0;
        end else begin
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
            end else begin
                ARREADY <= 1'b0;
            end
            
            // Handle R channel
            if (RVALID && RREADY) begin
                mem_ren <= 1'b1;
                mem_addr <= read_addr;
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
                if (read_count == read_len) begin
                    RVALID <= 1'b0;
                end
            end else begin
                mem_ren <= 1'b0;
            end
        end
    end
    
    // Output signal assignments
    assign RLAST = (read_count == read_len);
    assign RID = read_id;
    assign BID = write_id;
    assign RDATA = mem_rdata;
endmodule
