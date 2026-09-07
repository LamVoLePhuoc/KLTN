module I_CacheController (
    input wire clk,                          // Clock input
    input wire reset,                        // Active-high reset
    // CPU interface
    input wire [31:0] cpu_addr,              // CPU address
    input wire cpu_read,                     // CPU read request
    input wire cpu_write,                    // CPU write request (unused in I_Cache)
    input wire [31:0] cpu_wdata,             // CPU write data (unused in I_Cache)
    output reg [31:0] cpu_rdata,             // CPU read data
    output reg cpu_ready,                    // CPU ready signal
    // Tag Array interface
    output wire [4:0] tag_index,             // Tag array index
    input wire [21:0] tag_way0,              // Tag for way 0
    input wire [21:0] tag_way1,              // Tag for way 1
    input wire valid_way0,                   // Valid bit for way 0
    input wire valid_way1,                   // Valid bit for way 1
    input wire dirty_way0,                   // Dirty bit for way 0 (D_Cache only)
    input wire dirty_way1,                   // Dirty bit for way 1 (D_Cache only)
    output reg tag_write_enable,             // Tag write enable
    output reg [1:0] tag_way_select,         // Tag way select (2'b01: way 0, 2'b10: way 1)
    output reg [21:0] tag_in,                // Tag input
    output reg valid_in,                     // Valid bit input
    output reg dirty_in,                     // Dirty bit input (D_Cache only)
    input wire tag_error,                    // Error from TagArray
    // Data Array interface
    output wire [4:0] data_index,            // Data array index
    input wire [255:0] data_way0,            // Data for way 0
    input wire [255:0] data_way1,            // Data for way 1
    output reg [255:0] data_wdata,           // Data input
    output reg data_write_enable,            // Data write enable
    output reg [1:0] data_way_select,        // Data way select (2'b01: way 0, 2'b10: way 1)
    input wire data_error,                   // Error from DataArray
    // Comparator interface
    input wire hit_way0,                     // Hit signal for way 0
    input wire hit_way1,                     // Hit signal for way 1
    input wire comp_hit,                     // Overall hit signal
    input wire comp_miss,                    // Miss signal
    input wire comp_error,                   // Error from Comparator **Comparator**
    // Memory interface (AXI-4)
    output reg [31:0] mem_req_addr,          // Memory request address
    output reg mem_req_read,                 // Memory read request
    output reg mem_req_write,                // Memory write request (D_Cache only)
    output reg [255:0] mem_req_wdata,        // Memory write data (D_Cache only)
    input wire [255:0] mem_rdata,            // Memory read data
    input wire mem_ready,                    // Memory ready signal
    output reg fsm_error                     // FSM error signal
);

    timeunit 1ns; timeprecision 1ps;	

    localparam IDLE           = 3'b000;      // Wait for CPU request, handle hit
    localparam WRITE_BACK     = 3'b001;      // Write dirty data back to memory (D_Cache only)
    localparam ALLOCATE       = 3'b010;      // Fetch new data from memory
    localparam CPU_READ       = 3'b011;      // Return data to CPU and update cache
    localparam CPU_WRITE      = 3'b100;      // Write CPU data to cache and update (D_Cache only)

    reg [2:0] state, next_state;
    reg lru [0:31];                          // LRU bits (1 bit per set)
    reg [1:0] replace_way_reg;               // Store selected way for replacement

    // Address parsing
    assign tag_index = cpu_addr[9:5];        // 5-bit set index
    assign data_index = cpu_addr[9:5];       // Same index for data array
    wire [21:0] cpu_tag = cpu_addr[31:10];   // 22-bit tag
    wire [2:0] offset = cpu_addr[4:2];       // 5-bit offset for word selection
    wire replace_way = lru[tag_index];       // LRU bit for replacement
    integer i;

    // State transition and LRU update
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < 32; i = i + 1) lru[i] <= 0;
            replace_way_reg <= 2'b00;
            data_way_select <= 2'b00;
        end else begin
            state <= next_state;
            // Update LRU on hit
            if (comp_hit && state == IDLE) begin
                lru[tag_index] <= hit_way0 ? 1 : 0;
            end
            // Store replacement way after allocation
            if (state == ALLOCATE && mem_ready) begin
                replace_way_reg <= replace_way ? 2'b10 : 2'b01;
            end
        end
    end

    // FSM combinational logic
    always @(*) begin
        // Default outputs
        next_state = state;
        cpu_ready = 1'b0;
        next_state = state;
        cpu_ready = 1'b0;
        data_write_enable = 1'b0;
        data_wdata = data_wdata;
        mem_req_addr = 32'b0;
        mem_req_read = 1'b0;
        mem_req_write = 1'b0;
        mem_req_wdata = 256'b0;
        tag_write_enable = 1'b0;
        tag_way_select = 2'b00;
        cpu_rdata = cpu_rdata;
        tag_in = 1'b0;
        valid_in = 1'b0;
        dirty_in = 1'b0;
        fsm_error = tag_error || data_error || comp_error; // Aggregate error signals
        case (state)
            IDLE: begin
                if (cpu_read || cpu_write) begin
                    if (comp_hit) begin
                        // Cache hit
                        if (cpu_read) begin
                            // Read hit: Return data to CPU
                            if (hit_way0) begin
                                if (offset == 3'd0)      cpu_rdata = data_way0[255:224];
                                else if (offset == 3'd1) cpu_rdata = data_way0[223:192];
                                else if (offset == 3'd2) cpu_rdata = data_way0[191:160];
                                else if (offset == 3'd3) cpu_rdata = data_way0[159:128];
                                else if (offset == 3'd4) cpu_rdata = data_way0[127:96];
                                else if (offset == 3'd5) cpu_rdata = data_way0[95:64];
                                else if (offset == 3'd6) cpu_rdata = data_way0[63:32];
                                else if (offset == 3'd7) cpu_rdata = data_way0[31:0];
                            end
                            else begin
                                if (offset == 3'd0)      cpu_rdata = data_way1[255:224];
                                else if (offset == 3'd1) cpu_rdata = data_way1[223:192];
                                else if (offset == 3'd2) cpu_rdata = data_way1[191:160];
                                else if (offset == 3'd3) cpu_rdata = data_way1[159:128];
                                else if (offset == 3'd4) cpu_rdata = data_way1[127:96];
                                else if (offset == 3'd5) cpu_rdata = data_way1[95:64];
                                else if (offset == 3'd6) cpu_rdata = data_way1[63:32];
                                else if (offset == 3'd7) cpu_rdata = data_way1[31:0];
                            end
                            cpu_ready = 1'b1;
                        end else begin
                            // Write hit: Update cache line
                            data_write_enable = 1'b1;
                            data_way_select = hit_way0 ? 2'b01 : 2'b10;
                            data_wdata = hit_way0 ? data_way0 : data_way1;
                            if (offset == 3'd0)      cpu_rdata = data_wdata[255:224];
                            else if (offset == 3'd1) cpu_rdata = data_wdata[223:192];
                            else if (offset == 3'd2) cpu_rdata = data_wdata[191:160];
                            else if (offset == 3'd3) cpu_rdata = data_wdata[159:128];
                            else if (offset == 3'd4) cpu_rdata = data_wdata[127:96];
                            else if (offset == 3'd5) cpu_rdata = data_wdata[95:64];
                            else if (offset == 3'd6) cpu_rdata = data_wdata[63:32];
                            else if (offset == 3'd7) cpu_rdata = data_wdata[31:0];
                            tag_write_enable = 1'b1;
                            tag_way_select = data_way_select;
                            tag_in = cpu_tag;
                            valid_in = 1'b1;
                            dirty_in = 1'b1; // Mark as dirty (D_Cache only)
                            cpu_ready = 1'b1;
                        end
                    end else begin
                        // Cache miss
                        mem_req_addr = {cpu_addr[31:5], 5'b0};
                        mem_req_read = 1'b1;
                        if ((dirty_way0 && !replace_way) || (dirty_way1 && replace_way)) begin
                            next_state = WRITE_BACK;
                        end else begin
                            next_state = cpu_write ? CPU_WRITE : ALLOCATE;    
                        end
                    end
                end else begin
                    // No CPU request
                    next_state = IDLE;
                end
            end

            WRITE_BACK: begin
                // Write dirty data back to memory (D_Cache only)
                mem_req_addr = replace_way ? {tag_way1, data_index, 5'b0} : {tag_way0, data_index, 5'b0};
                mem_req_wdata = replace_way ? data_way1 : data_way0;
                mem_req_write = 1'b1;
                if (mem_ready) begin
                    next_state = cpu_write ? CPU_WRITE : ALLOCATE;
                end else begin
                    next_state = WRITE_BACK; // Wait for memory
                end
            end

            ALLOCATE: begin
                // Fetch new data from memory
                mem_req_addr = {cpu_addr[31:5], 5'b0};
                mem_req_read = 1'b1;
                if (mem_ready) begin
                    data_wdata = mem_rdata;
                    data_write_enable = 1'b1;
                    data_way_select = (replace_way == 1) ? 2'b10 : 2'b01;
                    next_state = CPU_READ;
                end else begin
                    next_state = ALLOCATE; // Wait for memory
                end
            end

            CPU_READ: begin
                // Return data to CPU and update cache
                    if (data_way_select == 2'b01) begin
                        if (offset == 3'd0)      cpu_rdata = data_way0[255:224];
                        else if (offset == 3'd1) cpu_rdata = data_way0[223:192];
                        else if (offset == 3'd2) cpu_rdata = data_way0[191:160];
                        else if (offset == 3'd3) cpu_rdata = data_way0[159:128];
                        else if (offset == 3'd4) cpu_rdata = data_way0[127:96];
                        else if (offset == 3'd5) cpu_rdata = data_way0[95:64];
                        else if (offset == 3'd6) cpu_rdata = data_way0[63:32];
                        else if (offset == 3'd7) cpu_rdata = data_way0[31:0];
                    end
                    else begin
                        if (offset == 3'd0)      cpu_rdata = data_way1[255:224];
                        else if (offset == 3'd1) cpu_rdata = data_way1[223:192];
                        else if (offset == 3'd2) cpu_rdata = data_way1[191:160];
                        else if (offset == 3'd3) cpu_rdata = data_way1[159:128];
                        else if (offset == 3'd4) cpu_rdata = data_way1[127:96];
                        else if (offset == 3'd5) cpu_rdata = data_way1[95:64];
                        else if (offset == 3'd6) cpu_rdata = data_way1[63:32];
                        else if (offset == 3'd7) cpu_rdata = data_way1[31:0];
                    end
                cpu_ready = 1'b1;
                // Update tag array
                tag_write_enable = 1'b1;
                tag_way_select = data_way_select;
                tag_in = cpu_tag;
                valid_in = 1'b1;
                dirty_in = 1'b0; // Clean line (D_Cache only)
                next_state = IDLE;
            end

            CPU_WRITE: begin
                // Write CPU data to cache and update (D_Cache only)
                data_wdata = mem_rdata;
                
                if (offset == 3'd0)      data_wdata[255:224] = cpu_wdata;
                else if (offset == 3'd1) data_wdata[223:192] = cpu_wdata;
                else if (offset == 3'd2) data_wdata[191:160] = cpu_wdata;
                else if (offset == 3'd3) data_wdata[159:128] = cpu_wdata;
                else if (offset == 3'd4) data_wdata[127:96] = cpu_wdata;
                else if (offset == 3'd5) data_wdata[95:64] = cpu_wdata;
                else if (offset == 3'd6) data_wdata[63:32] = cpu_wdata;
                else if (offset == 3'd7) data_wdata[31:0] = cpu_wdata;
                
                data_write_enable = 1'b1;
                data_way_select = replace_way ? 2'b10 : 2'b01;
                // Update tag array
                tag_write_enable = 1'b1;
                tag_way_select = data_way_select;
                tag_in = cpu_tag;
                valid_in = 1'b1;
                dirty_in = 1'b1; // Mark as dirty
                cpu_ready = 1'b1;
                next_state = IDLE;
            end

            default: begin
                next_state = IDLE;
                fsm_error = 1'b1; // Invalid state
            end
        endcase
    end

endmodule