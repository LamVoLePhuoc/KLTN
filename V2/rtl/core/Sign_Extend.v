`timescale 1ns / 1ps

module Sign_Extend (
    input  wire [31:0] In,
    input  wire [2:0]  ImmSrc,
    output reg  [31:0] Imm_Ext
);
    always @(*) begin
        case (ImmSrc)
            3'b000: Imm_Ext = {{20{In[31]}}, In[31:20]};                     // I-type
            3'b001: Imm_Ext = {{20{In[31]}}, In[31:25], In[11:7]};          // S-type
            3'b010: Imm_Ext = {{19{In[31]}}, In[31], In[7], In[30:25], In[11:8], 1'b0}; // B-type
            3'b011: Imm_Ext = {In[31:12], 12'b0};                           // U-type
            3'b100: Imm_Ext = {{11{In[31]}}, In[31], In[19:12], In[20], In[30:21], 1'b0}; // J-type
            3'b101: Imm_Ext = 32'd0;                                        // Atomic dummy imm
            3'b110: Imm_Ext = {27'b0, In[19:15]};                           // CSR imm
            default: Imm_Ext = 32'd0;
        endcase
    end
endmodule