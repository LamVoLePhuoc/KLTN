`timescale 1ns / 1ps

// Eight-master, one-slave AHB-Lite arbiter for the four I-cache and four
// D-cache master adapters.  Master numbering is fixed by the active SoC:
//   0..3 = D$0..D$3, 4..7 = I$0..I$3.
//
// Arbitration is starvation-free round-robin.  A grant is held for the full
// cache request (REQ_ACTIVE), not merely one AHB word, so the eight sequential
// word transfers that make up a line operation cannot be interleaved.  This is
// also required by the line-assembling AHB slave adapter downstream.
//
// Each L1 master adapter already latches one complete native request before
// arbitration.  This arbiter adds the matching one-entry response buffer per
// master.  The downstream slave response is captured after its AHB data phase
// completes and is returned to only the owning master on the following cycle.
// Besides making the ownership explicit, this cuts the former high-fanout
// combinational HRDATA broadcast that dominated the integrated routed timing.
module ahb_lite_arbiter_8m1s (
    input  wire         HCLK,
    input  wire         HRESETn,

    input  wire [7:0]   M_REQ_ACTIVE,
    input  wire [255:0] M_HADDR,
    input  wire [7:0]   M_HWRITE,
    input  wire [23:0]  M_HSIZE,
    input  wire [23:0]  M_HBURST,
    input  wire [15:0]  M_HTRANS,
    input  wire [255:0] M_HWDATA,
    input  wire [31:0]  M_HPROT,
    input  wire [7:0]   M_HMASTLOCK,

    output wire [7:0]   M_HGRANT,
    output reg  [7:0]   M_HREADY,
    output reg  [255:0] M_HRDATA,
    output reg  [15:0]  M_HRESP,
    output reg  [15:0]  M_HRUSER,

    output reg  [31:0]  S_HADDR,
    output reg          S_HWRITE,
    output reg  [2:0]   S_HSIZE,
    output reg  [2:0]   S_HBURST,
    output reg  [1:0]   S_HTRANS,
    output reg  [31:0]  S_HWDATA,
    output reg  [3:0]   S_HPROT,
    output reg          S_HMASTLOCK,
    output reg          S_REQ_ACTIVE,
    input  wire         S_HREADY,
    input  wire [31:0]  S_HRDATA,
    input  wire [1:0]   S_HRESP,
    input  wire [1:0]   S_HRUSER,

    output wire         GRANT_VALID,
    output wire [2:0]   GRANT_SOURCE
);
    reg       grant_valid_r;
    reg [2:0] grant_source_r;
    reg [2:0] rr_next;
    reg       choose_valid;
    reg [2:0] choose_source;
    reg [2:0] candidate;
    reg       data_phase_active;
    reg [2:0] data_phase_source;
    reg [7:0] response_valid_r;
    reg [255:0] response_data_r;
    reg [15:0] response_status_r;
    reg [15:0] response_user_r;
    integer offset;

    always @(*) begin
        choose_valid  = 1'b0;
        choose_source = rr_next;
        candidate     = rr_next;
        for (offset = 0; offset < 8; offset = offset + 1) begin
            candidate = rr_next + offset[2:0];
            if (!choose_valid && M_REQ_ACTIVE[candidate]) begin
                choose_valid  = 1'b1;
                choose_source = candidate;
            end
        end
    end

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            grant_valid_r  <= 1'b0;
            grant_source_r <= 3'd0;
            rr_next        <= 3'd0;
        end
        else if (grant_valid_r) begin
            if (!M_REQ_ACTIVE[grant_source_r]) begin
                grant_valid_r <= 1'b0;
                rr_next       <= grant_source_r + 3'd1;
            end
        end
        else if (choose_valid) begin
            grant_valid_r  <= 1'b1;
            grant_source_r <= choose_source;
        end
    end

    // Track the non-overlapped AHB address/data phases used by the L1 master
    // adapters.  S_HREADY qualifies address acceptance and later terminates
    // the corresponding data phase.  A response-valid bit is a one-cycle
    // pulse; the addressed master samples its registered data/status with it.
    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            data_phase_active <= 1'b0;
            data_phase_source <= 3'd0;
            response_valid_r  <= 8'b0;
            response_data_r   <= 256'b0;
            response_status_r <= 16'b0;
            response_user_r   <= 16'b0;
        end
        else begin
            response_valid_r <= 8'b0;

            if (!data_phase_active && grant_valid_r && S_HTRANS[1] && S_HREADY) begin
                data_phase_active <= 1'b1;
                data_phase_source <= grant_source_r;
            end

            if (data_phase_active && S_HREADY) begin
                response_data_r[data_phase_source*32 +: 32] <= S_HRDATA;
                response_status_r[data_phase_source*2 +: 2] <= S_HRESP;
                response_user_r[data_phase_source*2 +: 2] <= S_HRUSER;
                response_valid_r[data_phase_source] <= 1'b1;
                data_phase_active <= 1'b0;
            end
        end
    end

    assign M_HGRANT     = grant_valid_r ? (8'b0000_0001 << grant_source_r) : 8'b0;
    assign GRANT_VALID  = grant_valid_r;
    assign GRANT_SOURCE = grant_source_r;

    always @(*) begin
        S_HADDR      = 32'd0;
        S_HWRITE     = 1'b0;
        S_HSIZE      = 3'b010;
        S_HBURST     = 3'b000;
        S_HTRANS     = 2'b00;
        S_HWDATA     = 32'd0;
        S_HPROT      = 4'b0011;
        S_HMASTLOCK  = 1'b0;
        S_REQ_ACTIVE = 1'b0;
        M_HREADY     = response_valid_r;
        M_HRDATA     = response_data_r;
        M_HRESP      = response_status_r;
        M_HRUSER     = response_user_r;

        if (grant_valid_r) begin
            S_HADDR      = M_HADDR[grant_source_r*32 +: 32];
            S_HWRITE     = M_HWRITE[grant_source_r];
            S_HSIZE      = M_HSIZE[grant_source_r*3 +: 3];
            S_HBURST     = M_HBURST[grant_source_r*3 +: 3];
            S_HTRANS     = M_HTRANS[grant_source_r*2 +: 2];
            S_HWDATA     = M_HWDATA[grant_source_r*32 +: 32];
            S_HPROT      = M_HPROT[grant_source_r*4 +: 4];
            S_HMASTLOCK  = M_HMASTLOCK[grant_source_r];
            S_REQ_ACTIVE = M_REQ_ACTIVE[grant_source_r];
        end
    end

endmodule
