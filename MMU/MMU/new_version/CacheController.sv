module CacheController #(
    parameter int CPU_DATA_WIDTH = 32,
    parameter bit READ_ONLY      = 1'b0,
    parameter int LINE_WIDTH     = 256,
    parameter int NUM_SETS       = 32,
    parameter int TAG_WIDTH      = 22,
    parameter int INDEX_WIDTH    = $clog2(NUM_SETS),
    parameter int WORDS_PER_LINE = LINE_WIDTH / CPU_DATA_WIDTH,
    parameter int OFFSET_BITS    = $clog2(WORDS_PER_LINE)
) (
    input  wire                      clk,
    input  wire                      reset,

    input  wire [31:0]               cpu_addr,
    input  wire                      cpu_read,
    input  wire                      cpu_write,
    input  wire [CPU_DATA_WIDTH-1:0] cpu_wdata,
    output reg  [CPU_DATA_WIDTH-1:0] cpu_rdata,
    output reg                       cpu_ready,

    output wire [INDEX_WIDTH-1:0]    tag_index,
    input  wire [TAG_WIDTH-1:0]      tag_way0,
    input  wire [TAG_WIDTH-1:0]      tag_way1,
    input  wire                      valid_way0,
    input  wire                      valid_way1,
    input  wire                      dirty_way0,
    input  wire                      dirty_way1,
    output reg                       tag_write_enable,
    output reg  [1:0]                tag_way_select,
    output reg  [TAG_WIDTH-1:0]      tag_in,
    output reg                       valid_in,
    output reg                       dirty_in,
    input  wire                      tag_error,

    output wire [INDEX_WIDTH-1:0]    data_index,
    input  wire [LINE_WIDTH-1:0]     data_way0,
    input  wire [LINE_WIDTH-1:0]     data_way1,
    output reg  [LINE_WIDTH-1:0]     data_wdata,
    output reg                       data_write_enable,
    output reg  [1:0]                data_way_select,
    input  wire                      data_error,

    input  wire                      hit_way0,
    input  wire                      hit_way1,
    input  wire                      comp_hit,
    input  wire                      comp_miss,
    input  wire                      comp_error,

    output reg  [31:0]               mem_req_addr,
    output reg                       mem_req_read,
    output reg                       mem_req_write,
    output reg  [LINE_WIDTH-1:0]     mem_req_wdata,
    input  wire [LINE_WIDTH-1:0]     mem_rdata,
    input  wire                      mem_ready,
    output reg                       fsm_error
);

    timeunit 1ns; timeprecision 1ps;

    localparam logic [2:0] IDLE              = 3'b000;
    localparam logic [2:0] WRITE_BACK        = 3'b001;
    localparam logic [2:0] ALLOCATE          = 3'b010;
    localparam logic [2:0] CPU_READ          = 3'b011;
    localparam logic [2:0] CPU_PREPARE_WRITE = 3'b100;
    localparam logic [2:0] CPU_WRITE         = 3'b101;

    reg [2:0] state, next_state;
    reg       lru [0:NUM_SETS-1];
    reg [LINE_WIDTH-1:0] fill_line;

    wire [TAG_WIDTH-1:0] cpu_tag;
    wire [OFFSET_BITS-1:0] offset;
    wire replace_way;
    wire replace_way_eff;
    wire [LINE_WIDTH-1:0] hit_line;

    assign cpu_tag       = cpu_addr[31:10];
    assign tag_index     = cpu_addr[9:5];
    assign data_index    = cpu_addr[9:5];
    assign offset        = cpu_addr[4 -: OFFSET_BITS];
    assign replace_way   = lru[tag_index];
    assign replace_way_eff =
        (!valid_way0) ? 1'b0 :
        (!valid_way1) ? 1'b1 :
        replace_way;
    assign hit_line = hit_way0 ? data_way0 : data_way1;

    function automatic [CPU_DATA_WIDTH-1:0] select_word(
        input [LINE_WIDTH-1:0] line,
        input [OFFSET_BITS-1:0] word_offset
    );
        select_word = line[LINE_WIDTH-1 - (word_offset * CPU_DATA_WIDTH) -: CPU_DATA_WIDTH];
    endfunction

    function automatic [LINE_WIDTH-1:0] patch_word(
        input [LINE_WIDTH-1:0] line,
        input [OFFSET_BITS-1:0] word_offset,
        input [CPU_DATA_WIDTH-1:0] word_data
    );
        patch_word = line;
        patch_word[LINE_WIDTH-1 - (word_offset * CPU_DATA_WIDTH) -: CPU_DATA_WIDTH] = word_data;
    endfunction

    integer i;
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            fill_line <= '0;
            for (i = 0; i < NUM_SETS; i = i + 1) begin
                lru[i] <= 1'b0;
            end
        end else begin
            state <= next_state;
            if (((state == ALLOCATE) || (state == CPU_PREPARE_WRITE)) && mem_ready) begin
                fill_line <= mem_rdata;
            end
            if (comp_hit && state == IDLE) begin
                lru[tag_index] <= hit_way0 ? 1'b1 : 1'b0;
            end
        end
    end

    always_comb begin
        next_state         = state;
        cpu_ready          = 1'b0;
        cpu_rdata          = '0;
        data_write_enable  = 1'b0;
        data_wdata         = '0;
        data_way_select    = 2'b00;
        tag_write_enable   = 1'b0;
        tag_way_select     = 2'b00;
        tag_in             = cpu_tag;
        valid_in           = 1'b0;
        dirty_in           = 1'b0;
        mem_req_addr       = '0;
        mem_req_read       = 1'b0;
        mem_req_write      = 1'b0;
        mem_req_wdata      = '0;
        fsm_error          = tag_error || data_error || comp_error;

        unique case (state)
            IDLE: begin
                if (cpu_read || (cpu_write && !READ_ONLY)) begin
                    if (comp_hit) begin
                        if (cpu_read) begin
                            cpu_rdata = select_word(hit_line, offset);
                            cpu_ready = 1'b1;
                        end else begin
                            data_way_select   = hit_way0 ? 2'b01 : 2'b10;
                            data_wdata        = patch_word(hit_line, offset, cpu_wdata);
                            data_write_enable = 1'b1;
                            tag_write_enable  = 1'b1;
                            tag_way_select    = data_way_select;
                            valid_in          = 1'b1;
                            dirty_in          = 1'b1;
                            cpu_ready         = 1'b1;
                        end
                    end else begin
                        if (!READ_ONLY && ((dirty_way0 && !replace_way_eff) || (dirty_way1 && replace_way_eff))) begin
                            next_state = WRITE_BACK;
                        end else begin
                            mem_req_addr = {cpu_addr[31:5], 5'b0};
                            mem_req_read = 1'b1;
                            next_state = cpu_write && !READ_ONLY ? CPU_PREPARE_WRITE : ALLOCATE;
                        end
                    end
                end
            end

            WRITE_BACK: begin
                mem_req_addr  = replace_way_eff ? {tag_way1, data_index, 5'b0} : {tag_way0, data_index, 5'b0};
                mem_req_wdata = replace_way_eff ? data_way1 : data_way0;
                mem_req_write = 1'b1;
                if (mem_ready) begin
                    next_state = cpu_write && !READ_ONLY ? CPU_PREPARE_WRITE : ALLOCATE;
                end
            end

            ALLOCATE: begin
                mem_req_addr = {cpu_addr[31:5], 5'b0};
                mem_req_read = 1'b1;
                if (mem_ready) begin
                    data_wdata        = mem_rdata;
                    data_write_enable = 1'b1;
                    data_way_select   = replace_way_eff ? 2'b10 : 2'b01;
                    next_state        = CPU_READ;
                end
            end

            CPU_READ: begin
                cpu_rdata         = select_word(fill_line, offset);
                cpu_ready         = 1'b1;
                tag_write_enable  = 1'b1;
                tag_way_select    = replace_way_eff ? 2'b10 : 2'b01;
                valid_in          = 1'b1;
                dirty_in          = 1'b0;
                next_state        = IDLE;
            end

            CPU_PREPARE_WRITE: begin
                mem_req_addr = {cpu_addr[31:5], 5'b0};
                mem_req_read = 1'b1;
                if (mem_ready) begin
                    next_state = CPU_WRITE;
                end
            end

            CPU_WRITE: begin
                data_wdata        = patch_word(fill_line, offset, cpu_wdata);
                data_write_enable = 1'b1;
                data_way_select   = replace_way_eff ? 2'b10 : 2'b01;
                tag_write_enable  = 1'b1;
                tag_way_select    = data_way_select;
                valid_in          = 1'b1;
                dirty_in          = 1'b1;
                cpu_ready         = 1'b1;
                next_state        = IDLE;
            end

            default: begin
                next_state = IDLE;
                fsm_error  = 1'b1;
            end
        endcase
    end

endmodule
