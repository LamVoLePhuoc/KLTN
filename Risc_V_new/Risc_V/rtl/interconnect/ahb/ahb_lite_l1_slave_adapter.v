`timescale 1ns / 1ps

// ============================================================
// ahb_lite_l1_slave_adapter
//
// The other half of the pair with ahb_lite_l1_adapter.v: an AHB-
// Lite SLAVE that receives the 8 sequential single-word transfers
// ahb_lite_l1_adapter.v issues per line-fill/writeback, and speaks
// coherence_manager.v's per-core D$ request shape
// (dreq_valid/dreq_type/dreq_addr/dreq_line <-> dresp_valid/
// dresp_line/dresp_state) on the other side. Also usable, as-is, for
// a core's I$ port (see quad_core_soc_ahb.v) -- just don't connect
// dreq_type/dresp_state there, coherence_manager.v's I$ ports don't
// have them (I$ traffic is implicitly always a read, see
// l1_icache.v/coherence_manager.v).
//
// Together, one ahb_lite_l1_adapter.v + one of this module form a
// bridge that is functionally transparent (same requests reach
// coherence_manager.v as if the L1 were wired to it directly) but
// puts LITERAL AHB-Lite signals on the wire in between -- see
// quad_core_soc_ahb.v's header for why this exists as a separate,
// new top-level variant rather than being wired into the already-
// reviewed quad_core_soc.v in place.
//
// MSI request semantics over AHB-Lite: HWRITE distinguishes a
// WRITEBACK from a line read. HMASTLOCK distinguishes an RFO/upgrade
// from a plain BusRd. This is a standard AHB signal and avoids the
// old correctness bug where the bridge collapsed RFO into READ and
// let an L1 enter M without invalidating sibling sharers. MSI read
// fills are always S, so no response-state sideband is needed.
//
// Read path: on the FIRST word (word_idx==0) of a fresh line-read,
// immediately issues dreq_valid (type=READ) and holds HREADYOUT low
// until dresp_valid returns the WHOLE line; word 0's data is served
// that same cycle, words 1-7 are then served immediately out of the
// now-fully-populated local buffer on their own subsequent AHB
// transfers (no further waiting).
//
// Write path: words 0-6 are accepted (HREADYOUT=1) into a local
// buffer immediately, no backend interaction yet -- only word 7
// triggers dreq_valid (type=WRITEBACK, the assembled whole line),
// and THAT transfer's HREADYOUT is held low until dresp_valid acks
// it. (Completing word 7 immediately and acking the writeback to
// coherence_manager.v asynchronously in the background -- a
// "posted write" -- would let the requesting L1 believe the
// writeback finished before it actually reached L2, a real race;
// this adapter deliberately does not do that.)
// ============================================================
module ahb_lite_l1_slave_adapter (
    input  wire         HCLK,
    input  wire         HRESETn,

    // ---- AHB-Lite slave ----
    input  wire [31:0]  HADDR,
    input  wire          HWRITE,
    input  wire [1:0]    HTRANS,
    input  wire [31:0]   HWDATA,
    input  wire          HMASTLOCK,
    output reg            HREADYOUT,
    output reg  [31:0]    HRDATA,
    output wire [1:0]     HRESP,      // tied OKAY -- see ahb_lite_l1_adapter.v's header

    // ---- coherence_manager.v-shaped request/response (D$ shape;
    // for an I$ caller, just leave dreq_type/dresp_state unconnected) ----
    output reg           dreq_valid,
    output reg  [1:0]    dreq_type,
    output reg  [31:0]   dreq_addr,
    output reg  [255:0]  dreq_line,
    input  wire          dresp_valid,
    input  wire [255:0]  dresp_line,
    input  wire [1:0]    dresp_state
);

    localparam [1:0] TRANS_NONSEQ = 2'b10;
    localparam [1:0] REQ_READ = 2'b00, REQ_RFO = 2'b01, REQ_WRITEBACK = 2'b10;

    assign HRESP = 2'b00; // OKAY, always -- see ahb_lite_l1_adapter.v's header

    localparam [1:0] S_IDLE       = 2'd0,
                     S_WAIT_READ  = 2'd1,
                     S_WAIT_WRITE = 2'd2,
                     S_WRITE_DATA = 2'd3;

    reg [1:0]   state;
    reg [2:0]   word_idx;
    reg [31:0]  line_addr;
    reg         is_write;
    reg [255:0] rd_buf;
    reg [255:0] wr_buf;

    always @(posedge HCLK or negedge HRESETn) begin
        if (!HRESETn) begin
            state      <= S_IDLE;
            word_idx   <= 3'd0;
            HREADYOUT  <= 1'b1;
            dreq_valid <= 1'b0;
        end
        else begin
            case (state)
                // ------------------------------------------------
                S_IDLE: begin
                    dreq_valid <= 1'b0;
                    if (HTRANS == TRANS_NONSEQ) begin
                        if (HWRITE) begin
                            // Address phase only. HWDATA belongs to the
                            // following data phase and is captured in
                            // S_WRITE_DATA, not here.
                            if (word_idx == 3'd0) line_addr <= HADDR;
                            is_write <= 1'b1;
                            HREADYOUT <= (word_idx == 3'd7) ? 1'b0 : 1'b1;
                            state <= S_WRITE_DATA;
                        end
                        else begin
                            is_write <= 1'b0;
                            if (word_idx == 3'd0) begin
                                line_addr <= HADDR;
                                // Word 0 of a read: wait for the whole
                                // line from the coherence manager.
                                HREADYOUT  <= 1'b0;
                                dreq_valid <= 1'b1;
                                dreq_type  <= HMASTLOCK ? REQ_RFO : REQ_READ;
                                dreq_addr  <= HADDR;
                                state      <= S_WAIT_READ;
                            end
                            else begin
                                // Read, word_idx 1..7: already have the
                                // whole line buffered (rd_buf) from the
                                // S_WAIT_READ completion below -- serve
                                // immediately, no further waiting.
                                HRDATA    <= rd_buf[word_idx*32 +: 32];
                                HREADYOUT <= 1'b1;
                                if (word_idx == 3'd7) word_idx <= 3'd0;
                                else                  word_idx <= word_idx + 3'd1;
                            end
                        end
                    end
                    else begin
                        // IDLE/BUSY on the bus -- nothing to do, stay ready.
                        HREADYOUT <= 1'b1;
                    end
                end

                // AHB write data phase. For words 0..6 the transfer
                // completes immediately. Word 7 is held with HREADY
                // low until the assembled full-line writeback is
                // acknowledged by the coherence manager.
                S_WRITE_DATA: begin
                    wr_buf[word_idx*32 +: 32] <= HWDATA;
                    if (word_idx == 3'd7) begin
                        HREADYOUT  <= 1'b0;
                        dreq_valid <= 1'b1;
                        dreq_type  <= REQ_WRITEBACK;
                        dreq_addr  <= line_addr;
                        dreq_line  <= {HWDATA, wr_buf[223:0]};
                        state      <= S_WAIT_WRITE;
                    end
                    else begin
                        HREADYOUT <= 1'b1;
                        word_idx  <= word_idx + 3'd1;
                        state     <= S_IDLE;
                    end
                end

                // ------------------------------------------------
                S_WAIT_READ: begin
                    // Hold valid until the serialized coherence
                    // manager returns a response; a one-cycle pulse
                    // can be lost while another core owns the CM.
                    dreq_valid <= 1'b1;
                    if (dresp_valid) begin
                        dreq_valid <= 1'b0;
                        rd_buf    <= dresp_line;
                        HRDATA    <= dresp_line[0 +: 32]; // word 0
                        HREADYOUT <= 1'b1;                // complete transfer 0 now
                        word_idx  <= 3'd1;
                        state     <= S_IDLE;
                    end
                    // else: still waiting, HREADYOUT stays low (held from before)
                end

                // ------------------------------------------------
                S_WAIT_WRITE: begin
                    dreq_valid <= 1'b1;
                    if (dresp_valid) begin
                        dreq_valid <= 1'b0;
                        HREADYOUT <= 1'b1; // complete the final (8th) transfer now
                        word_idx  <= 3'd0;
                        state     <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
