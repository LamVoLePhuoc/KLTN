`timescale 1ns / 1ps

// ============================================================
// physical_core_wrapper
//
// Active core wrapper for the cache-controller-only thesis scope.
// The core issues one 32-bit address space directly to its private
// L1 caches.  No TLB, page-table walker or VA-to-PA translation is
// instantiated in this hierarchy.
//
// This block retains the parts that are still required with a real
// multi-cycle cache: pipeline back-pressure, one-shot completion for
// a level-held M-stage request, physical access-fault propagation,
// LR/SC snoop matching and architectural FENCE.I observation.
// ============================================================
module physical_core_wrapper #(
    parameter [31:0] RESET_ADDR = 32'h0000_1000,
    parameter [31:0] HART_ID    = 32'd0
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        Stall_Core_External,

    input  wire [31:0] Snoop_Addr,
    input  wire        Snoop_WE,

    output wire [31:0] PCF,
    input  wire [31:0] InstrF,
    input  wire        Instr_ValidF,
    input  wire        Instr_ErrorF,

    output wire [31:0] Mem_AddrM,
    output wire [31:0] Mem_WriteDataM,
    output wire        Mem_WriteEnM,
    output wire        Mem_ReadEnM,
    output wire [2:0]  MemOpM,
    output wire        Mem_AmoRmwM,
    output wire [4:0]  Mem_AmoOpM,
    output wire [31:0] Mem_AmoOperandM,
    input  wire [31:0] Mem_ReadDataM,
    input  wire        Mem_ReadDataValidM,
    input  wire        Mem_WriteDoneM,
    input  wire        Mem_ReadErrorM,
    input  wire        Mem_WriteErrorM,

    output wire [31:0] ResultW,
    output wire [31:0] ALU_ResultE_Debug,
    output wire        Fetch_AccessFault,
    output wire        Data_AccessFault,
    output wire        FenceI_M
);

    wire [31:0] pcf_core;
    wire [31:0] mem_addr_core;
    wire [31:0] mem_wdata_core;
    wire        mem_we_core;
    wire        mem_re_core;
    wire [2:0]  memop_core;
    wire        mem_amo_core;
    wire [4:0]  mem_amo_op_core;
    wire [31:0] mem_amo_operand_core;
    wire        mem_req_core;

    reg         core_data_completed;

    assign Fetch_AccessFault = Instr_ValidF & Instr_ErrorF;
    assign Data_AccessFault = ~core_data_completed &
                              ((mem_re_core & Mem_ReadDataValidM & Mem_ReadErrorM) |
                               (mem_we_core & Mem_WriteDoneM & Mem_WriteErrorM));

    wire fetch_wait = ~Instr_ValidF;
    wire data_wait  = ~core_data_completed &
                      (mem_we_core ? ~Mem_WriteDoneM :
                       mem_re_core ? ~Mem_ReadDataValidM : 1'b0);
    wire core_pipeline_stall = Stall_Core_External | fetch_wait | data_wait;
    wire core_data_response = ~core_data_completed &
                              ((mem_we_core & Mem_WriteDoneM) |
                               (mem_re_core & Mem_ReadDataValidM));

    // A fetch or maintenance stall can keep an already-completed data
    // instruction parked in M.  Remember that completion so a store or
    // AMO cannot be presented to D$ more than once.
    always @(posedge clk) begin
        if (rst)
            core_data_completed <= 1'b0;
        else if (!core_pipeline_stall)
            core_data_completed <= 1'b0;
        else if (core_data_response)
            core_data_completed <= 1'b1;
        else if (!mem_req_core)
            core_data_completed <= 1'b0;
    end

    assign PCF             = pcf_core;
    assign Mem_AddrM       = mem_addr_core;
    assign Mem_WriteDataM  = mem_wdata_core;
    assign Mem_WriteEnM    = mem_we_core & ~core_data_completed;
    assign Mem_ReadEnM     = mem_re_core & ~core_data_completed;
    assign MemOpM          = memop_core;
    assign Mem_AmoRmwM     = mem_amo_core;
    assign Mem_AmoOpM      = mem_amo_op_core;
    assign Mem_AmoOperandM = mem_amo_operand_core;

    wire [31:0] instr_to_core = Fetch_AccessFault ? 32'h0000_0013 : InstrF;
    wire [31:0] rdata_to_core = Data_AccessFault ? 32'b0 : Mem_ReadDataM;

    RV32IMA #(
        .RESET_ADDR(RESET_ADDR),
        .HART_ID(HART_ID)
    ) core (
        .clk(clk),
        .rst(rst),
        .Stall_Core_External(core_pipeline_stall),

        .Snoop_Addr(Snoop_Addr),
        .Snoop_WE(Snoop_WE),
        // The only address domain in the active design is physical.
        .Mem_PhysAddrM(mem_addr_core),

        .PCF(pcf_core),
        .InstrF(instr_to_core),

        .Mem_AddrM(mem_addr_core),
        .Mem_WriteDataM(mem_wdata_core),
        .Mem_WriteEnM(mem_we_core),
        .Mem_ReadEnM(mem_re_core),
        .MemOpM(memop_core),
        .Mem_AmoRmwM(mem_amo_core),
        .Mem_AmoOpM(mem_amo_op_core),
        .Mem_AmoOperandM(mem_amo_operand_core),
        .Mem_RequestM(mem_req_core),
        .Mem_StoreIntentM(),
        .Mem_ReadDataM(rdata_to_core),

        .Fetch_PageFault_In(1'b0),
        .Data_PageFault_In(1'b0),
        .Fetch_AccessFault_In(Fetch_AccessFault),
        .Data_AccessFault_In(Data_AccessFault),

        .ResultW(ResultW),
        .ALU_ResultE_Debug(ALU_ResultE_Debug),
        .CurrentPriv(),
        .Mmu_Enable_Csr(),
        .Satp_PPN_Csr(),
        .Mstatus_Sum(),
        .Mstatus_Mxr(),
        .Mmu_Flush_Csr(),
        .FenceI_M(FenceI_M)
    );

endmodule

