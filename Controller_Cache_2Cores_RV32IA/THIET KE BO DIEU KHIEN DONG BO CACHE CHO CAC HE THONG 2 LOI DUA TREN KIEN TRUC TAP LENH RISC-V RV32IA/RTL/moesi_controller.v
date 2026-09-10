`timescale 1ns/1ps
// from Lee Min Hunz with luv
module moesi_controller(
    input   [2:0]   current_state
,   input   [2:0]   victim_state
,   input           is_shared_response
// ,   input           is_dirty_response
,   input           refill_we

    // Request from CPU 
,   input           cpu_req_valid
,   input           cpu_hit
,   input           cpu_rw         // 1: Write, 0: Read

    // Request from Bus (Snoop)
,   input           snoop_valid
,   input           snoop_hit      
,   input           snoop_req_invalidate      

    // Outputs
,   output              victim_dirty       
// ,   output              is_unique      
// ,   output              is_owner       
,   output              victim_valid       
,   output reg [2:0]    next_state
);

    // ================================================================
    // LOCAL PARAMETERS - MOESI State Encoding
    // ================================================================
    localparam  STATE_M = 3'd0,   // Modified  - Dirty, Exclusive
                STATE_O = 3'd1,   // Owned     - Dirty, Shared
                STATE_E = 3'd2,   // Exclusive - Clean, Exclusive
                STATE_S = 3'd3,   // Shared    - Clean, Shared
                STATE_I = 3'd4;   // Invalid

    // ================================================================
    // STATE DECODE LOGIC
    // ================================================================
    // Extract state properties for external use
    assign victim_dirty = (victim_state == STATE_M) | (current_state == STATE_O);  // Has dirty data
    assign victim_valid = (victim_state != STATE_I);                               // Has valid copy
    // assign is_unique    = (current_state == STATE_M) | (current_state == STATE_E);  // Only copy
    // assign is_owner     = (current_state == STATE_M) | (current_state == STATE_O);  // Responsible for data
    

    // ================================================================
    // NEXT STATE LOGIC
    // ================================================================
    always @(*) begin
        next_state = current_state;
        // ========================
        // SNOOP REQUEST HANDLING (Highest Priority)
        // ========================
        // External core wants access to this cache line
        if (snoop_valid && snoop_hit) begin
            if (snoop_req_invalidate) begin   // Bus Write (CleanInvalid/MakeInvalid)
                // Other core wants exclusive access -> Invalidate our copy
                next_state = STATE_I; 
            end
            else begin // Bus Read (ReadShared)
                // Other core wants to read -> Downgrade to shared
                case (current_state)
                    STATE_M, STATE_O:   next_state = STATE_O; // Keep ownership of dirty data
                    STATE_E:            next_state = STATE_S; // Đang E (Clean-Exclusive) bị đọc -> S (Clean-Shared)
                    STATE_S:            next_state = STATE_S; // Already shared
                    default:            next_state = STATE_I;
                endcase
            end
        end

        // ========================
        // REFILL HANDLING (Cache Miss Resolution)
        // ========================
        // Data received from memory or peer cache
        else if (refill_we) begin
            if (cpu_rw) begin 
                // Refill cho Write Miss (Read-for-Ownership)
                next_state = STATE_M; 
            end
            else begin
                // Refill cho Read Miss
                if (is_shared_response) 
                    next_state = STATE_S; // Nếu được share từ cache khác (bất kể O/M/S/E)
                else 
                    next_state = STATE_E; // Cấp phát độc quyền từ Memory/L2
            end
        end

        // ========================
        // CPU HIT HANDLING (Local Access)
        // ========================
        // CPU accessing a line that exists in cache
        else if (cpu_req_valid && cpu_hit) begin
            if (cpu_rw) begin // Write Hit -> Always upgrade to Modified
                next_state = STATE_M; 
            end 
            else begin // Read Hit -> Keep current state
                next_state = current_state; 
            end 
        end 
    end 
endmodule