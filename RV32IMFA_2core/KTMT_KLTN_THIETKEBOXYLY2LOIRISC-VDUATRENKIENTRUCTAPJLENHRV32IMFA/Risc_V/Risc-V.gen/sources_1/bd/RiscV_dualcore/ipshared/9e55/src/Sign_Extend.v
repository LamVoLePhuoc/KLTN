module Sign_Extend (
    input  wire [31:0] In,
    input  wire [2:0]  ImmSrc,
    output reg  [31:0] Imm_Ext
);
    always @(*) begin
        case(ImmSrc)
            // I-type (ADDI, Load, JALR, FLW)
            3'b000: Imm_Ext = {{20{In[31]}}, In[31:20]};
            
            // S-type (Store, FSW)
            3'b001: Imm_Ext = {{20{In[31]}}, In[31:25], In[11:7]};
            
            // B-type (Branch)
            3'b010: Imm_Ext = {{20{In[31]}}, In[7], In[30:25], In[11:8], 1'b0};
            
            // U-type (LUI, AUIPC)
            3'b011: Imm_Ext = {In[31:12], 12'b0};
            
            // J-type (JAL)
            3'b100: Imm_Ext = {{12{In[31]}}, In[19:12], In[20], In[30:21], 1'b0};
            
            // Atomic (Dummy Imm = 0 cho LR/SC/AMO)
            3'b101: Imm_Ext = 32'd0; 

            // CSR-type (5-bit Zero-extended cho CSRRWI/...)
            3'b110: Imm_Ext = {27'b0, In[19:15]};

            default: Imm_Ext = 32'd0;
        endcase
    end
endmodule