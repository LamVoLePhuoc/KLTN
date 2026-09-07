// Module Name: AXI4_Arbiter_R
// Project Name: AXI4 Interconnect
// Description: AXI4 Read Address Channel Arbiter
// Function: This module implements a round-robin arbitration scheme for the AXI4 read address channel. 
//      It grants access to one of the four masters based on their request signals and the current state of the bus. 
//      The priority is set as follows: Master 0 > Master 1 > Master 2 > Master 3.

`timescale 1ns/1ns

module AXI_Arbiter_R (
    /**********Clock & Reset**********/
    input                       ACLK,
    input      	                ARESETn,
    /********** Master 0 **********/
    input                       m0_ARVALID,
    input                       m0_RREADY,
    /********** Master 1 **********/
    input                       m1_ARVALID,
    input                       m1_RREADY,
    /********** Master 2 **********/
    input                       m2_ARVALID,
    input                       m2_RREADY,
    /********** Master 3 **********/
    input                       m3_ARVALID,
    input                       m3_RREADY,
    /******* Master Common Signals ********/
    input                       m_RVALID,
    input                       m_RLAST,
    
    output reg                  m0_rgrnt,
    output reg	                m1_rgrnt,
    output reg                  m2_rgrnt,
    output reg                  m3_rgrnt
);

    //=========================================================
    //Constant definition
    parameter   TCO     =   1;  //Register delay

    //=========================================================
    //Read address channel arbitration state machine

    //---------------------------------------------------------
    //State definitions
    parameter [1:0] 
        AXI_MASTER_0 = 2'b00,   //Master 0 occupies bus state
        AXI_MASTER_1 = 2'b01,   //Master 1 occupies bus state
        AXI_MASTER_2 = 2'b10,   //Master 2 occupies bus state
        AXI_MASTER_3 = 2'b11;   //Master 3 occupies bus state
    
    reg [1:0] state, next_state;

    //---------------------------------------------------------
    //State decoding
    always @(*) begin
        case (state)
            AXI_MASTER_0: begin                 //Master 0 occupies bus, priority: 0>1>2>3
                if(m0_ARVALID)                  //If master 0 requests bus
                    next_state = AXI_MASTER_0;  //Keep master 0 occupies bus state
                else if(m_RVALID||m0_RREADY)    //If still writing data
                    next_state = AXI_MASTER_0;  //Keep master 0 occupies bus state
                else if(m_RLAST&&m_RVALID)      //Read complete
                    next_state = AXI_MASTER_1;  //Change priority
                else if(m1_ARVALID)             //If master 1 requests bus
                    next_state = AXI_MASTER_1;  //Next state is master 1 occupies bus
                else if(m2_ARVALID)             //If master 2 requests bus
                    next_state = AXI_MASTER_2;  //Next state is master 2 occupies bus
                else if(m3_ARVALID)             //If master 3 requests bus
                    next_state = AXI_MASTER_3;  //Next state is master 3 occupies bus
                else                            //No bus request
                    next_state = AXI_MASTER_0;  //Keep master 0 occupies bus state
            end
            AXI_MASTER_1: begin                 //Master 1 occupies bus, priority: 1>2>3>0
                if(m1_ARVALID)                  //Similar to previous section
                    next_state = AXI_MASTER_1;
                else if(m_RVALID||m1_RREADY)
                    next_state = AXI_MASTER_1;
                else if(m_RLAST&&m_RVALID)
                    next_state = AXI_MASTER_2;
                else if(m2_ARVALID)
                    next_state = AXI_MASTER_2;
                else if(m3_ARVALID)
                    next_state = AXI_MASTER_3;
                else if(m0_ARVALID)
                    next_state = AXI_MASTER_0;
                else
                    next_state = AXI_MASTER_0;
            end
            AXI_MASTER_2: begin                 //Master 2 occupies bus, priority: 2>3>0>1
                if(m2_ARVALID)                  //Similar to previous section
                    next_state = AXI_MASTER_2;
                else if(m_RVALID||m2_RREADY)
                    next_state = AXI_MASTER_2;
                else if(m_RLAST&&m_RVALID)
                    next_state = AXI_MASTER_3;
                else if(m3_ARVALID)
                    next_state = AXI_MASTER_3;
                else if(m0_ARVALID)
                    next_state = AXI_MASTER_0;
                else if(m1_ARVALID)
                    next_state = AXI_MASTER_1;
                else
                    next_state = AXI_MASTER_2;
            end
            AXI_MASTER_3: begin                 //Master 3 occupies bus, priority: 3>0>1>2
                if(m3_ARVALID)                  //Similar to previous section
                    next_state = AXI_MASTER_3;  
                else if(m_RVALID||m3_RREADY)
                    next_state = AXI_MASTER_3;
                else if(m_RLAST&&m_RVALID)
                    next_state = AXI_MASTER_0;
                else if(m0_ARVALID)
                    next_state = AXI_MASTER_0;
                else if(m1_ARVALID)
                    next_state = AXI_MASTER_1;
                else if(m2_ARVALID)
                    next_state = AXI_MASTER_2;
                else
                    next_state = AXI_MASTER_3;
            end
            default:
                next_state = AXI_MASTER_0;      //Default state is master 0 occupies bus
        endcase
    end

    //---------------------------------------------------------
    //Update state register
    always @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn)
            state <= #TCO AXI_MASTER_0;         //Default state is master 0 occupies bus
        else
            state <= #TCO next_state;
    end

    //---------------------------------------------------------
    //Output control results using state register
    always @(*) begin
        case (state)
            AXI_MASTER_0: {m0_rgrnt,m1_rgrnt,m2_rgrnt,m3_rgrnt} = 4'b1000;
            AXI_MASTER_1: {m0_rgrnt,m1_rgrnt,m2_rgrnt,m3_rgrnt} = 4'b0100;
            AXI_MASTER_2: {m0_rgrnt,m1_rgrnt,m2_rgrnt,m3_rgrnt} = 4'b0010;
            AXI_MASTER_3: {m0_rgrnt,m1_rgrnt,m2_rgrnt,m3_rgrnt} = 4'b0001;
            default:      {m0_rgrnt,m1_rgrnt,m2_rgrnt,m3_rgrnt} = 4'b0000;
        endcase
    end

endmodule
