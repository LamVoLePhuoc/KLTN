`timescale 1ps/1ps

module decode(
    input             clk,          // Clock
    input             rst_n,        // Reset (active low)
    input [31:0]      instr,        // Instruction fetched from I-Cache
    input [31:0]      wb_data,      // Data written from the Register File
    // Phase-1 addition: gates the actual register-file write so a
    // multi-cycle (cache-miss-stalled) instruction only commits its
    // result on the cycle it truly retires, instead of every cycle it
    // sits combinationally decoded. Tie to 1'b1 for single-cycle-no-stall
    // use (legacy rv32i.v leaves this floating/unconnected and is
    // superseded by core_top.sv — see README_PHASE1).
    input             instr_valid,
    output [31:0]     rs1_data,     // Data read from register rs1
    output [31:0]     rs2_data,     // Data read from register rs2
    output [31:0]     imm,          // Immediate value
    // Control signals output to subsequent modules
    output [3:0]      alu_op,       // ALU operation
    output            mem_read,     // Memory read
    output            mem_write,    // Memory write
    output            reg_write_en, // Register write enable
    output [1:0]      wb_sel,       // Write back select
    output [1:0]      pc_sel,       // PC select
    output            a_sel,        // Select data from rs1 or PC
    output            b_sel,        // Select data from rs2 or immediate
    output [9:0]      ls_sel,       // Load/Store select
    output [9:0]      branch_signal,// Branch signal
    output            br_un         // Branch Unsigned signal
);
    // Extract fields from the instruction
    wire [6:0] opcode;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd_addr;
    wire [2:0] funct3;
    wire [6:0] funct7;

    assign opcode  = instr[6:0];
    assign rs1     = instr[19:15];
    assign rs2     = instr[24:20];
    assign rd_addr = instr[11:7];
    assign funct3  = instr[14:12];
    assign funct7  = instr[31:25];

    // Calculate immediate value based on the instruction type
    reg [31:0] imm_value;
    always @(*) begin
        case (opcode)
            7'b0110111, 7'b0010111: begin // U-type: LUI, AUIPC
                imm_value = {instr[31:12], 12'b0};
            end
            7'b1101111: begin // J-type: JAL
                // Format: {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0} with 11-bit sign extension
                imm_value = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            end
            7'b1100011: begin // B-type: Branch instructions
                // Format: {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0} with 20-bit sign extension
                imm_value = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0};
            end
            7'b0000011, 7'b0010011, 7'b1100111: begin // I-type: Loads, ALU immediates, JALR
                imm_value = {{20{instr[31]}}, instr[31:20]};
            end
            7'b0100011: begin // S-type: Store instructions
                imm_value = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end
            default: imm_value = 32'b0;
        endcase
    end

    assign imm = imm_value;

    // Connect to the Controller module
    Controller controller_inst(
        .opcode(opcode),
        .funct7(funct7),
        .funct3(funct3),
        .alu_op(alu_op),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .reg_write_en(reg_write_en),
        .wb_sel(wb_sel),
        .pc_sel(pc_sel),
        .a_sel(a_sel),
        .b_sel(b_sel),
        .ls_sel(ls_sel),
        .branch_signal(branch_signal),
        .br_un(br_un)
    );

    // Connect to the Register File module
    // Gate the write with instr_valid so a stalled instruction (waiting on
    // a cache miss) does not repeatedly re-write the register file every
    // cycle with a not-yet-valid result; it commits exactly once, on the
    // cycle it retires.
    register_file register_file_inst(
        .clk(clk),
        .rst_n(rst_n),
        .rs1(rs1),
        .rs2(rs2),
        .reg_write_en(reg_write_en & instr_valid),
        .rd_addr(rd_addr),
        .wb_data(wb_data),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data)
    );

endmodule

// Module register_file: 32-bit register file with 32 registers
module register_file(
    input             clk,          // Clock
    input             rst_n,        // Reset (active low)
    input             reg_write_en, // Register write enable
    input [4:0]       rs1,
    input [4:0]       rs2,        
    input [4:0]       rd_addr,      // Destination register address
    input [31:0]      wb_data,      // Data to be written to the register file
    output [31:0]     rs1_data,     // Data read from register rs1
    output [31:0]     rs2_data      // Data read from register rs2
);
    reg [31:0] reg_file [31:0];

    // Read data from the register file (read is combinational based on address)
    assign rs1_data = reg_file[rs1];
    assign rs2_data = reg_file[rs2];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            reg_file[i] = 32'b0;
        end
    end

    // Write data to the register file
    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            // Reset: set all registers to 0
            for (i = 0; i < 32; i = i + 1)
                reg_file[i] <= 32'b0;
        end 
        else if (reg_write_en) begin
            reg_file[rd_addr] <= wb_data;
            reg_file[0] <= 32'b0; // x0 is always 0
        end
    end
endmodule

// Module Controller: Generate control signals based on opcode and other fields
module Controller(
    input [6:0] opcode,
    input [6:0] funct7,
    input [2:0] funct3,
    output [3:0] alu_op,
    output       mem_read,
    output       mem_write,
    output       reg_write_en,
    output [1:0] wb_sel,
    output [1:0] pc_sel,
    output       a_sel,
    output       b_sel,
    output [9:0] ls_sel,
    output [9:0] branch_signal,
    output       br_un
);
    reg reg_write_en_reg, mem_read_reg, mem_write_reg, a_sel_reg, b_sel_reg, br_un_reg;
    reg [3:0] alu_op_reg;
    reg [1:0] wb_sel_reg, pc_sel_reg;
    reg [9:0] ls_sel_reg, branch_signal_reg;
    
    // Parameter definitions for opcodes
    parameter R_Type = 7'b0110011;
    parameter I_Type = 7'b0010011;
    parameter S_Type = 7'b0100011;
    parameter B_Type = 7'b1100011;
    parameter U_Type = 7'b0110111;
    parameter J_Type = 7'b1101111;
    parameter LOAD   = 7'b0000011;
    parameter LUI    = 7'b0110111;
    parameter AUIPC  = 7'b0010111;
    parameter JALR   = 7'b1100111;
    parameter JAL    = 7'b1101111;
    
    always @(*) begin
        case (opcode)
            // R-type instructions 
            R_Type: begin
                reg_write_en_reg = 1'b1; // enable register write
                mem_read_reg = 1'b0;     // no memory read
                mem_write_reg = 1'b0;    // no memory write
                wb_sel_reg = 2'b01;      // select ALU result
                pc_sel_reg = 2'b00;      // select PC + 4
                a_sel_reg = 1'b0;        // select data from rs1
                b_sel_reg = 1'b1;        // select data from rs2
                case ({funct7, funct3})
                    9'b000000000: alu_op_reg = 4'b0000; // ADD
                    9'b010000000: alu_op_reg = 4'b0001; // SUB
                    9'b000000001: alu_op_reg = 4'b0010; // SLL
                    9'b000000010: alu_op_reg = 4'b0011; // SLT
                    9'b000000011: alu_op_reg = 4'b0100; // SLTU
                    9'b000000100: alu_op_reg = 4'b0101; // XOR
                    9'b000000101: alu_op_reg = 4'b0110; // SRL
                    9'b010000101: alu_op_reg = 4'b0111; // SRA
                    9'b000000110: alu_op_reg = 4'b1000; // OR
                    9'b000000111: alu_op_reg = 4'b1001; // AND
                    default: alu_op_reg = 4'b0000;       // default to ADD
                endcase
            end
            // I-type instructions
            I_Type: begin
                reg_write_en_reg = 1'b1;
                mem_read_reg = 1'b0;
                mem_write_reg = 1'b0;
                wb_sel_reg = 2'b01;
                pc_sel_reg = 2'b00;
                a_sel_reg = 1'b0;
                b_sel_reg = 1'b0; // select immediate
                case (funct3)
                    3'b000: alu_op_reg = 4'b0000; // ADDI
                    3'b010: alu_op_reg = 4'b0011; // SLTI
                    3'b011: alu_op_reg = 4'b0100; // SLTIU
                    3'b100: alu_op_reg = 4'b0101; // XORI
                    3'b110: alu_op_reg = 4'b1000; // ORI
                    3'b111: alu_op_reg = 4'b1001; // ANDI
                    3'b001: alu_op_reg = 4'b0010; // SLLI
                    3'b101: begin
                        if (funct7 == 7'b0000000)
                            alu_op_reg = 4'b0110; // SRLI
                        else
                            alu_op_reg = 4'b0111; // SRAI
                    end
                    default: alu_op_reg = 4'b0000;
                endcase
            end
            // LOAD instructions (I-type)
            LOAD: begin
                reg_write_en_reg = 1'b1;
                mem_read_reg = 1'b1;
                mem_write_reg = 1'b0;
                wb_sel_reg = 2'b10;      // select data from data memory
                pc_sel_reg = 2'b00;
                a_sel_reg = 1'b0;
                b_sel_reg = 1'b0;
                alu_op_reg = 4'b0000;    // ADD
                ls_sel_reg = {funct7, funct3};
            end
            // JALR instruction (I-type)
            JALR: begin
                reg_write_en_reg = 1'b1;
                mem_read_reg = 1'b0;
                mem_write_reg = 1'b0;
                wb_sel_reg = 2'b11;      // select PC + 4
                pc_sel_reg = 2'b11;      // jump to target address
                a_sel_reg = 1'b0;
                b_sel_reg = 1'b0;        // use immediate
                alu_op_reg = 4'b0000;    // ADD
            end
            // S-type instructions
            S_Type: begin
                reg_write_en_reg = 1'b0;
                mem_read_reg = 1'b0;
                mem_write_reg = 1'b1;
                wb_sel_reg = 2'b00;
                pc_sel_reg = 2'b00;
                a_sel_reg = 1'b0;
                b_sel_reg = 1'b0;
                alu_op_reg = 4'b0000;    // ADD
                ls_sel_reg = {funct7, funct3};
            end
            // B-type instructions
            B_Type: begin
                reg_write_en_reg = 1'b0;
                mem_read_reg = 1'b0;
                mem_write_reg = 1'b0;
                wb_sel_reg = 2'b00;
                pc_sel_reg = 2'b10;      // select branch target
                a_sel_reg = 1'b1;        // use PC
                b_sel_reg = 1'b0;        // use immediate
                alu_op_reg = 4'b0000;    // ADD (for comparison)
                // Phase-1 fix: this used to be {funct7, funct3}. For
                // B-type instructions instr[31:25] is NOT a real funct7 —
                // it's part of the branch-offset immediate (imm[12],
                // imm[10:5]), so it's usually nonzero and essentially
                // random depending on the branch target. execute.v's case
                // statement, however, matches against constants like
                // 10'b1100011000 whose upper 7 bits are the B-type
                // *opcode* (7'b1100011), not funct7. The two never agreed
                // except by chance, so branch_taken was almost always
                // computed as 0 — no branch ever actually branched,
                // including the BEQ x0,x0,0 self-loop testbenches use to
                // halt, which is why the core would run off into
                // unintialized memory instead of stopping.
                branch_signal_reg = {opcode, funct3};
                case (funct3)
                    3'b000: br_un_reg = 1'b0; // BEQ
                    3'b001: br_un_reg = 1'b0; // BNE
                    3'b100: br_un_reg = 1'b0; // BLT
                    3'b101: br_un_reg = 1'b0; // BGE
                    3'b110: br_un_reg = 1'b1; // BLTU
                    3'b111: br_un_reg = 1'b1; // BGEU
                    default: br_un_reg = 1'b0;
                endcase
            end
            // U-type instructions: LUI
            LUI: begin
                reg_write_en_reg = 1'b1;
                mem_read_reg = 1'b0;
                mem_write_reg = 1'b0;
                wb_sel_reg = 2'b01;
                pc_sel_reg = 2'b00;
                a_sel_reg = 1'b0; // don't care
                b_sel_reg = 1'b0;
                alu_op_reg = 4'b1010;  // LUI: immediate shifted left 12 bits
            end
            // U-type instructions: AUIPC
            AUIPC: begin
                reg_write_en_reg = 1'b1;
                mem_read_reg = 1'b0;
                mem_write_reg = 1'b0;
                wb_sel_reg = 2'b01;
                pc_sel_reg = 2'b00;
                a_sel_reg = 1'b0;
                b_sel_reg = 1'b0;
                alu_op_reg = 4'b0000;  // ADD
            end
            // J-type instructions: JAL
            JAL: begin
                reg_write_en_reg = 1'b1;
                mem_read_reg = 1'b0;
                mem_write_reg = 1'b0;
                wb_sel_reg = 2'b11;      // select PC + 4
                pc_sel_reg = 2'b11;      // jump to target address
                a_sel_reg = 1'b1;        // use PC
                b_sel_reg = 1'b0;        // use immediate
                alu_op_reg = 4'b0000;    // ADD
            end
            default: begin
                reg_write_en_reg = 1'b0;
                mem_read_reg = 1'b0;
                mem_write_reg = 1'b0;
                wb_sel_reg = 2'b00;
                pc_sel_reg = 2'b00;
                a_sel_reg = 1'b0;
                b_sel_reg = 1'b0;
                alu_op_reg = 4'b0000;
                ls_sel_reg = 10'b0;
                branch_signal_reg = 10'b0;
                br_un_reg = 1'b0;
            end
        endcase
    end

    // Assign internal registers to outputs
    assign alu_op        = alu_op_reg;
    assign mem_read      = mem_read_reg;
    assign mem_write     = mem_write_reg;
    assign reg_write_en  = reg_write_en_reg;
    assign wb_sel        = wb_sel_reg;
    assign pc_sel        = pc_sel_reg;
    assign a_sel         = a_sel_reg;
    assign b_sel         = b_sel_reg;
    assign ls_sel        = ls_sel_reg;
    assign branch_signal = branch_signal_reg;
    assign br_un         = br_un_reg;

endmodule
