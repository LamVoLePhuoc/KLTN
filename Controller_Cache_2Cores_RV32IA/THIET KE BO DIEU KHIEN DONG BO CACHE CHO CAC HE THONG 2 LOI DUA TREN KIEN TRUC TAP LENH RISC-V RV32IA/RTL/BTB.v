// from Lee Min Hunz with luv
`timescale 1ns / 1ps
// ============================================================================
// BTB - Branch Target Buffer (4-way set associative)
// ============================================================================
module BTB #(
    parameter W_ADDR = 32
)(
    input                   clk, rst_n
,   input [W_ADDR-1:2]      F_PC
,   output reg [W_ADDR-1:0] pc_prediction
,   output                  hit

    // MEM stage update inputs
,   input [W_ADDR-1:2]      M_PC           
,   input [W_ADDR-1:0]      M_PCTarget  
,   input                   M_Branch       
,   input                   M_Jump          
);
    localparam INDEX_BITS = 3;                          
    localparam TAG_BITS   = W_ADDR - 2 - INDEX_BITS;    

    wire [INDEX_BITS-1:0] f_index   = F_PC[4:2];
    wire [TAG_BITS-1:0]   f_tag     = F_PC[W_ADDR-1:5];
    
    // Đổi e_index, e_tag thành m_index, m_tag
    wire [INDEX_BITS-1:0] m_index   = M_PC[4:2];
    wire [TAG_BITS-1:0]   m_tag     = M_PC[W_ADDR-1:5];
    wire update_en                  = M_Branch | M_Jump;

    reg [W_ADDR-1:0]    data_mem0 [0:7]; reg [W_ADDR-1:0]    data_mem1 [0:7]; 
    reg [W_ADDR-1:0]    data_mem2 [0:7]; reg [W_ADDR-1:0]    data_mem3 [0:7]; 
    reg [TAG_BITS-1:0]  tag_mem0  [0:7]; reg [TAG_BITS-1:0]  tag_mem1  [0:7];
    reg [TAG_BITS-1:0]  tag_mem2  [0:7]; reg [TAG_BITS-1:0]  tag_mem3  [0:7];
    reg valid0 [0:7]; reg valid1 [0:7]; reg valid2 [0:7]; reg valid3 [0:7];

    wire [3:0] read_hit_ways, write_hit_ways, plru_victim_way, final_target_way;

    // READ LOGIC (Tầng Fetch)
    assign read_hit_ways[0] = (tag_mem0[f_index] == f_tag) && valid0[f_index];
    assign read_hit_ways[1] = (tag_mem1[f_index] == f_tag) && valid1[f_index];
    assign read_hit_ways[2] = (tag_mem2[f_index] == f_tag) && valid2[f_index];
    assign read_hit_ways[3] = (tag_mem3[f_index] == f_tag) && valid3[f_index];
    assign hit              = |read_hit_ways;

    always @(*) begin
        case(read_hit_ways)
            4'b0001: pc_prediction = data_mem0[f_index];
            4'b0010: pc_prediction = data_mem1[f_index];
            4'b0100: pc_prediction = data_mem2[f_index];
            4'b1000: pc_prediction = data_mem3[f_index];
            default: pc_prediction = 32'd0;
        endcase
    end

    // WRITE LOGIC (Tầng MEM)
    assign write_hit_ways[0] = (tag_mem0[m_index] == m_tag) && valid0[m_index];
    assign write_hit_ways[1] = (tag_mem1[m_index] == m_tag) && valid1[m_index];
    assign write_hit_ways[2] = (tag_mem2[m_index] == m_tag) && valid2[m_index];
    assign write_hit_ways[3] = (tag_mem3[m_index] == m_tag) && valid3[m_index];
    
    wire write_hit_any       = |write_hit_ways;
    assign final_target_way  = write_hit_any ? write_hit_ways : plru_victim_way;

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (k = 0; k < 8; k = k + 1) begin
                valid0[k] <= 1'b0; valid1[k] <= 1'b0; valid2[k] <= 1'b0; valid3[k] <= 1'b0;
                tag_mem0[k] <= 0; tag_mem1[k] <= 0; tag_mem2[k] <= 0; tag_mem3[k] <= 0;
                data_mem0[k] <= 0; data_mem1[k] <= 0; data_mem2[k] <= 0; data_mem3[k] <= 0;
            end
        end
        else if (update_en) begin
            if (final_target_way[0]) begin
                tag_mem0[m_index]  <= m_tag; data_mem0[m_index]  <= M_PCTarget; valid0[m_index]  <= 1'b1;
            end
            if (final_target_way[1]) begin
                tag_mem1[m_index]  <= m_tag; data_mem1[m_index]  <= M_PCTarget; valid1[m_index]  <= 1'b1;
            end
            if (final_target_way[2]) begin
                tag_mem2[m_index]  <= m_tag; data_mem2[m_index]  <= M_PCTarget; valid2[m_index]  <= 1'b1;
            end
            if (final_target_way[3]) begin
                tag_mem3[m_index]  <= m_tag; data_mem3[m_index]  <= M_PCTarget; valid3[m_index]  <= 1'b1;
            end
        end
    end

    // PLRU REPLACEMENT
    reg [3:1]   btb_plru_mem [0:7];
    wire [3:1]  current_tree = btb_plru_mem[m_index];
    wire [3:1]  next_tree;

    wire [2:0] node_id_1    = current_tree[1] ? 3'd3 : 3'd2;
    wire [1:0] victim_bin   = current_tree[node_id_1] ? {node_id_1[0], 1'b1} : {node_id_1[0], 1'b0};
    assign plru_victim_way  = 4'b0001 << victim_bin;

    plru plru_update1 (.clk(clk), .rst_n(rst_n), .prev_bit(current_tree[1]), .left_hit(|final_target_way[1:0]), .right_hit(|final_target_way[3:2]), .plru_bit(next_tree[1]));
    plru plru_update2 (.clk(clk), .rst_n(rst_n), .prev_bit(current_tree[2]), .left_hit(final_target_way[0]), .right_hit(final_target_way[1]), .plru_bit(next_tree[2]));
    plru plru_update3 (.clk(clk), .rst_n(rst_n), .prev_bit(current_tree[3]), .left_hit(final_target_way[2]), .right_hit(final_target_way[3]), .plru_bit(next_tree[3]));

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            for (i = 0; i < 8; i = i + 1) btb_plru_mem[i] <= 3'd0;
        end 
        else if (update_en) begin
            btb_plru_mem[m_index] <= next_tree;
        end
    end
endmodule