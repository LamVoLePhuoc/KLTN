// L2_CacheController: shared L2 cache controller. Unlike the L1
// I_/D_CacheController (which transfer 64-bit CPU words within a
// 256-bit line and need an in-line word-merge), every transaction here
// is a *whole 32-byte line* — the "CPU side" of this controller is
// really the interconnect forwarding an L1 miss-fill or an L1
// write-through, both of which are already full-line operations. That
// collapses the old CPU_READ/CPU_WRITE/CPU_PREPARE_WRITE staging down
// to three states: IDLE, WRITE_BACK (evict a dirty victim), ALLOCATE
// (fetch a line for a read miss). A write miss needs no allocate step
// at all, since the whole line is being overwritten anyway.
module L2_CacheController (
    input  wire         clk,
    input  wire         reset,
    // CPU (interconnect) interface — whole-line only
    input  wire [31:0]  cpu_addr,
    input  wire         cpu_read,
    input  wire         cpu_write,
    input  wire [255:0] cpu_wdata,
    output reg  [255:0] cpu_rdata,
    output reg           cpu_ready,
    // Tag Array interface
    output wire [12:0]  tag_index,
    input  wire [13:0]  tag_way0,
    input  wire [13:0]  tag_way1,
    input  wire          valid_way0,
    input  wire          valid_way1,
    input  wire          dirty_way0,
    input  wire          dirty_way1,
    output reg            tag_write_enable,
    output reg  [1:0]     tag_way_select,
    output reg  [13:0]    tag_in,
    output reg             valid_in,
    output reg             dirty_in,
    input  wire            tag_error,
    // Data Array interface
    output wire [12:0]   data_index,
    input  wire [255:0]  data_way0,
    input  wire [255:0]  data_way1,
    output reg  [255:0]  data_wdata,
    output reg            data_write_enable,
    output reg  [1:0]     data_way_select,
    input  wire            data_error,
    // Comparator interface
    input  wire  hit_way0,
    input  wire  hit_way1,
    input  wire  comp_hit,
    input  wire  comp_miss,
    input  wire  comp_error,
    // Backing DRAM interface
    output reg  [31:0]  mem_req_addr,
    output reg           mem_req_read,
    output reg           mem_req_write,
    output reg  [255:0] mem_req_wdata,
    input  wire [255:0] mem_rdata,
    input  wire          mem_ready,
    output reg            fsm_error
);

    timeunit 1ns; timeprecision 1ps;

    localparam IDLE       = 2'b00;
    localparam WRITE_BACK = 2'b01;
    localparam ALLOCATE   = 2'b10;

    reg [1:0] state, next_state;
    reg lru [0:8191];
    reg pending_write; // latched: was the miss that triggered WRITE_BACK/ALLOCATE a write?

    assign tag_index  = cpu_addr[17:5];
    assign data_index = cpu_addr[17:5];
    wire [13:0] cpu_tag = cpu_addr[31:18];
    wire        replace_way = lru[tag_index];

    wire replace_way_eff =
        (!valid_way0) ? 1'b0 :
        (!valid_way1) ? 1'b1 :
        replace_way;

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            for (i = 0; i < 8192; i = i + 1) lru[i] <= 1'b0;
            pending_write <= 1'b0;
        end else begin
            state <= next_state;
            if (comp_hit && state == IDLE) begin
                lru[tag_index] <= hit_way0 ? 1'b1 : 1'b0;
            end
            if (state == IDLE && next_state != IDLE) begin
                pending_write <= cpu_write;
            end
        end
    end

    always @(*) begin
        next_state        = state;
        cpu_ready          = 1'b0;
        cpu_rdata          = cpu_rdata;
        data_write_enable  = 1'b0;
        data_wdata         = cpu_wdata;
        data_way_select    = 2'b00;
        tag_write_enable   = 1'b0;
        tag_way_select     = 2'b00;
        tag_in             = cpu_tag;
        valid_in           = 1'b0;
        dirty_in           = 1'b0;
        mem_req_addr       = {cpu_addr[31:5], 5'b0};
        mem_req_read       = 1'b0;
        mem_req_write      = 1'b0;
        mem_req_wdata      = 256'b0;
        fsm_error          = tag_error || data_error || comp_error;

        case (state)
            IDLE: begin
                if (cpu_read || cpu_write) begin
                    if (comp_hit) begin
                        data_way_select = hit_way0 ? 2'b01 : 2'b10;
                        if (cpu_read) begin
                            cpu_rdata = hit_way0 ? data_way0 : data_way1;
                            cpu_ready = 1'b1;
                        end else begin
                            // Phase-2 fix: this used to be a blind
                            // `data_wdata = cpu_wdata`, overwriting the
                            // ENTIRE 256-bit line with whatever the
                            // writing core's L1 sent — including that
                            // L1's stale/don't-care view of the *other*
                            // three 64-bit slots in the line. Two
                            // addresses that are merely close together
                            // (e.g. two different cores' independent
                            // result variables sharing one 32-byte line)
                            // would then clobber each other even though
                            // they're logically unrelated. Only the one
                            // 64-bit slot cpu_addr actually targets
                            // should be updated here; the other three
                            // must keep L2's existing (already-correct)
                            // data, exactly like D_CacheController.sv
                            // does for its own local line on a hit.
                            data_wdata = hit_way0 ? data_way0 : data_way1;
                            case (cpu_addr[4:3])
                                2'b00: data_wdata[255:192] = cpu_wdata[255:192];
                                2'b01: data_wdata[191:128] = cpu_wdata[191:128];
                                2'b10: data_wdata[127:64]  = cpu_wdata[127:64];
                                2'b11: data_wdata[63:0]    = cpu_wdata[63:0];
                            endcase
                            data_write_enable = 1'b1;
                            tag_write_enable  = 1'b1;
                            tag_way_select    = data_way_select;
                            tag_in            = cpu_tag;
                            valid_in          = 1'b1;
                            dirty_in          = 1'b1; // L2 is genuinely write-back to DRAM
                            cpu_ready         = 1'b1;
                        end
                    end else begin
                        // Miss.
                        if ((dirty_way0 && !replace_way_eff) || (dirty_way1 && replace_way_eff)) begin
                            next_state    = WRITE_BACK;
                            mem_req_addr  = replace_way_eff ? {tag_way1, cpu_addr[17:5], 5'b0}
                                                             : {tag_way0, cpu_addr[17:5], 5'b0};
                            mem_req_wdata = replace_way_eff ? data_way1 : data_way0;
                            mem_req_write = 1'b1;
                        end else if (cpu_write) begin
                            // Write-allocate, no read-before-write needed:
                            // the whole line is being overwritten.
                            data_way_select   = replace_way_eff ? 2'b10 : 2'b01;
                            data_wdata        = cpu_wdata;
                            data_write_enable = 1'b1;
                            tag_write_enable  = 1'b1;
                            tag_way_select    = data_way_select;
                            tag_in            = cpu_tag;
                            valid_in          = 1'b1;
                            dirty_in          = 1'b1;
                            cpu_ready         = 1'b1;
                        end else begin
                            mem_req_addr = {cpu_addr[31:5], 5'b0};
                            mem_req_read = 1'b1;
                            next_state   = ALLOCATE;
                        end
                    end
                end
            end

            WRITE_BACK: begin
                mem_req_addr  = replace_way_eff ? {tag_way1, cpu_addr[17:5], 5'b0}
                                                 : {tag_way0, cpu_addr[17:5], 5'b0};
                mem_req_wdata = replace_way_eff ? data_way1 : data_way0;
                mem_req_write = 1'b1;
                if (mem_ready) begin
                    if (pending_write) begin
                        data_way_select   = replace_way_eff ? 2'b10 : 2'b01;
                        data_wdata        = cpu_wdata;
                        data_write_enable = 1'b1;
                        tag_write_enable  = 1'b1;
                        tag_way_select    = data_way_select;
                        tag_in            = cpu_tag;
                        valid_in          = 1'b1;
                        dirty_in          = 1'b1;
                        cpu_ready         = 1'b1;
                        next_state        = IDLE;
                    end else begin
                        mem_req_addr = {cpu_addr[31:5], 5'b0};
                        mem_req_read = 1'b1;
                        next_state   = ALLOCATE;
                    end
                end else begin
                    next_state = WRITE_BACK;
                end
            end

            ALLOCATE: begin
                mem_req_addr = {cpu_addr[31:5], 5'b0};
                mem_req_read = 1'b1;
                if (mem_ready) begin
                    data_way_select   = replace_way_eff ? 2'b10 : 2'b01;
                    data_wdata        = mem_rdata;
                    data_write_enable = 1'b1;
                    tag_write_enable  = 1'b1;
                    tag_way_select    = data_way_select;
                    tag_in            = cpu_tag;
                    valid_in          = 1'b1;
                    dirty_in          = 1'b0;
                    cpu_rdata         = mem_rdata;
                    cpu_ready         = 1'b1;
                    next_state        = IDLE;
                end else begin
                    next_state = ALLOCATE;
                end
            end

            default: begin
                next_state = IDLE;
                fsm_error  = 1'b1;
            end
        endcase
    end

endmodule
