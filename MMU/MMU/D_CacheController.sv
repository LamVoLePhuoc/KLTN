module D_CacheController (
    input wire clk,                          // Clock input
    input wire reset,                        // Active-high reset
    // CPU interface
    input wire [31:0] cpu_addr,              // CPU address
    input wire cpu_read,                     // CPU read request
    input wire cpu_write,                    // CPU write request (unused in I_Cache)
    input wire [63:0] cpu_wdata,             // CPU write data (unused in I_Cache)
    output reg [63:0] cpu_rdata,             // CPU read data
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

    // FSM states
    localparam IDLE           = 3'b000;      // Wait for CPU request, handle hit
    localparam WRITE_BACK     = 3'b001;      // Write dirty data back to memory (D_Cache only)
    localparam ALLOCATE       = 3'b010;      // Fetch new data from memory
    localparam CPU_READ       = 3'b011;      // Return data to CPU and update cache
    localparam CPU_PREPARE_WRITE = 3'b100;
    localparam CPU_WRITE      = 3'b101;      // Write CPU data to cache and update (D_Cache only)
    // Phase-2 addition: every store now also pushes its updated line to
    // the shared L2 immediately (write-through), instead of only marking
    // the local line dirty and deferring to a later eviction. This is
    // what makes the interconnect's snoop-invalidate coherence scheme
    // correct: once another core's stale L1 copy is invalidated, its
    // next fetch from L2 is guaranteed to see this write, because the
    // write already landed in L2 before the invalidate for it was even
    // sent. (The old write-back-only policy could leave L2 stale
    // indefinitely, since a dirty line might not be evicted for a long
    // time — or ever, in a short test program.)
    localparam WRITE_THROUGH  = 3'b110;

    reg [2:0] state, next_state;
    reg lru [0:31];                          // LRU bits (1 bit per set)
    reg [1:0] replace_way_reg;               // Store selected way for replacement
    reg [31:0]  wt_addr;                     // latched write-through target address
    reg [255:0] wt_line;                     // latched write-through line data

    // Address parsing
    assign tag_index = cpu_addr[9:5];        // 5-bit set index
    assign data_index = cpu_addr[9:5];       // Same index for data array
    wire [21:0] cpu_tag = cpu_addr[31:10];   // 22-bit tag
    wire [2:0] offset = cpu_addr[4:3];       // 5-bit offset for word selection
    wire replace_way = lru[tag_index];       // LRU bit for replacement
    
    wire replace_way_eff;

    assign replace_way_eff =
        (!valid_way0) ? 1'b0 :
        (!valid_way1) ? 1'b1 :
        replace_way;   // = lru[tag_index]
    
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
                replace_way_reg <= replace_way_eff ? 2'b10 : 2'b01;
            end
            // Latch the write-through target whenever we're about to
            // leave a state that just computed a new line value for a
            // store (write hit in IDLE, or write-allocate merge in
            // CPU_WRITE) on our way into WRITE_THROUGH.
            if (next_state == WRITE_THROUGH && state != WRITE_THROUGH) begin
                // Phase-2 fix: this used to line-align the address
                // ({cpu_addr[31:5],5'b0}), throwing away the low 5 bits.
                // L2_CacheController needs those bits (specifically
                // addr[4:3]) to know *which* 64-bit slot of the line
                // this write actually touched, so it can patch only that
                // slot instead of overwriting the whole line (see the
                // comment on L2's write-hit merge). Sending the exact
                // address costs nothing here — L2's own tag/index lookup
                // already only looks at addr[31:18]/addr[17:5], ignoring
                // addr[4:0] regardless of whether we zero it or not.
                wt_addr <= cpu_addr;
                wt_line <= data_wdata;
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
                                if (offset == 3'd0)      cpu_rdata = data_way0[255:192];
                                else if (offset == 3'd1) cpu_rdata = data_way0[191:128];
                                else if (offset == 3'd2) cpu_rdata = data_way0[127:64];
                                else if (offset == 3'd3) cpu_rdata = data_way0[63:0];
                            end
                            else begin
                                if (offset == 3'd0)      cpu_rdata = data_way1[255:192];
                                else if (offset == 3'd1) cpu_rdata = data_way1[191:128];
                                else if (offset == 3'd2) cpu_rdata = data_way1[127:64];
                                else if (offset == 3'd3) cpu_rdata = data_way1[63:0];
                            end
                            cpu_ready = 1'b1;
                        end else begin        
                            data_way_select = hit_way0 ? 2'b01 : 2'b10;
                            
                            // 1) Read current line from the hit way
                            data_wdata = hit_way0 ? data_way0 : data_way1;
                            
                            // 2) Patch the 64-bit word selected by offset
                            if (offset == 3'd0)      data_wdata[255:192] = cpu_wdata;
                            else if (offset == 3'd1) data_wdata[191:128] = cpu_wdata;
                            else if (offset == 3'd2) data_wdata[127:64]  = cpu_wdata;
                            else if (offset == 3'd3) data_wdata[63:0]    = cpu_wdata;
                            
                            // 3) Write the updated line back to DataArray
                            //    (local copy is available immediately for
                            //    subsequent hits from this same core)
                            data_write_enable = 1'b1;

                            // 4) Update tag status (tag usually unchanged on hit, but OK to rewrite)
                            tag_write_enable = 1'b1;
                            tag_way_select = data_way_select;
                            tag_in   = cpu_tag;
                            valid_in = 1'b1;
                            dirty_in = 1'b0; // clean: about to write straight through to L2

                            // 5) Push the updated line to L2 before
                            //    telling the CPU the store completed, so
                            //    that once the interconnect invalidates
                            //    any sibling core's stale copy, L2 is
                            //    guaranteed to already hold this value.
                            next_state = WRITE_THROUGH;

                            // (Optional) cpu_rdata is not meaningful for store; you can leave it unchanged
                        end
                    end else  begin
                        // Cache miss
                        mem_req_addr = {cpu_addr[31:5], 5'b0};  //Load 32byte = 256bit tu dia chi [cpu_addr[31:5], 5'b0]
                        mem_req_read = 1'b1;
                        if ((dirty_way0 && !replace_way_eff) || (dirty_way1 && replace_way_eff)) begin
                            next_state = WRITE_BACK;
                        end else begin
                            next_state = cpu_write ? CPU_PREPARE_WRITE : ALLOCATE;    
                        end
                    end
                end else begin
                    // No CPU request
                    next_state = IDLE;
                end
            end

            WRITE_BACK: begin
                // Write dirty data back to memory (D_Cache only)
                mem_req_addr = replace_way_eff ? {tag_way1, data_index, 5'b0} : {tag_way0, data_index, 5'b0};
                mem_req_wdata = replace_way_eff ? data_way1 : data_way0;
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
                    data_way_select = (replace_way_eff == 1) ? 2'b10 : 2'b01;
                    next_state = CPU_READ;
                end else begin
                    next_state = ALLOCATE; // Wait for memory
                end
            end

            CPU_PREPARE_WRITE:begin
                // Fetch new data from memory
                mem_req_addr = {cpu_addr[31:5], 5'b0};
                mem_req_read = 1'b1;
                if (mem_ready) begin
                    next_state = CPU_WRITE;
                end else begin
                    next_state = CPU_PREPARE_WRITE; // Wait for memory
                end
            end
            
            CPU_READ: begin
                if (data_way_select == 2'b01) begin
                    if (offset == 3'd0)      cpu_rdata = data_way0[255:192];
                    else if (offset == 3'd1) cpu_rdata = data_way0[191:128];
                    else if (offset == 3'd2) cpu_rdata = data_way0[127:64];
                    else if (offset == 3'd3) cpu_rdata = data_way0[63:0];
                end
                else begin
                    if (offset == 3'd0)      cpu_rdata = data_way1[255:192];
                    else if (offset == 3'd1) cpu_rdata = data_way1[191:128];
                    else if (offset == 3'd2) cpu_rdata = data_way1[127:64];
                    else if (offset == 3'd3) cpu_rdata = data_way1[63:0];
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
                
                if (offset == 3'd0)      data_wdata[255:192] = cpu_wdata;
                else if (offset == 3'd1) data_wdata[191:128] = cpu_wdata;
                else if (offset == 3'd2) data_wdata[127:64] = cpu_wdata;
                else if (offset == 3'd3) data_wdata[63:0] = cpu_wdata;
                
                data_write_enable = 1'b1;
                data_way_select = replace_way_eff ? 2'b10 : 2'b01;
                // Update tag array
                tag_write_enable = 1'b1;
                tag_way_select = data_way_select;
                tag_in = cpu_tag;
                valid_in = 1'b1;
                dirty_in = 1'b0; // clean: about to write straight through to L2
                next_state = WRITE_THROUGH;
            end

            WRITE_THROUGH: begin
                // Push the just-updated line to L2 (shared, write-back at
                // that level) before acking the CPU. See the localparam
                // comment above for why this matters for coherence.
                mem_req_addr  = wt_addr;
                mem_req_wdata = wt_line;
                mem_req_write = 1'b1;
                if (mem_ready) begin
                    cpu_ready  = 1'b1;
                    next_state = IDLE;
                end else begin
                    next_state = WRITE_THROUGH;
                end
            end

            default: begin
                next_state = IDLE;
                fsm_error = 1'b1; // Invalid state
            end
        endcase
    end

endmodule