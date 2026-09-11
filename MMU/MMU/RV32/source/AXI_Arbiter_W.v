// Module Name: AXI_Arbiter_W
// Project Name: AXI4 Interconnect
// Description: AXI4 Write Address Channel Arbiter
// Function: This module implements a round-robin arbitration scheme for the AXI4 write address channel. 
//      It grants access to one of the four masters based on their request signals and the current state of the bus. 
//      The priority is set as follows: Master 0 > Master 1 > Master 2 > Master 3.

`timescale 1ns/1ns

module AXI_Arbiter_W (
    /**********Clock & Reset**********/
    input           ACLK,
    input      	    ARESETn,
    /********** Master 0 **********/
    input                       m0_AWVALID,
    input                       m0_WVALID,
    input                       m0_BREADY,
    /********** Master 1 **********/
    input                       m1_AWVALID,
    input                       m1_WVALID,
    input                       m1_BREADY,
    /********** Master 2 **********/
    input                       m2_AWVALID,
    input                       m2_WVALID,
    input                       m2_BREADY,
    /********** Master 3 **********/
    input                       m3_AWVALID,
    input                       m3_WVALID,
    input                       m3_BREADY,

    input                       m_AWREADY,
    input                       m_WREADY,
    input                       m_BVALID,
    
    output reg                  m0_wgrnt,
    output reg	                m1_wgrnt,
    output reg                  m2_wgrnt,
    output reg                  m3_wgrnt
);

    //=========================================================
    //Constants
    parameter   TCO     =   1;  //Register delay

    //=========================================================
    //Write address channel arbitration state machine

    //---------------------------------------------------------
    //Define states
    // States for the state machine (replaced enum with parameters)
    parameter [1:0] AXI_MASTER_0 = 2'b00;    //Master 0 occupies bus
    parameter [1:0] AXI_MASTER_1 = 2'b01;    //Master 1 occupies bus
    parameter [1:0] AXI_MASTER_2 = 2'b10;    //Master 2 occupies bus
    parameter [1:0] AXI_MASTER_3 = 2'b11;    //Master 3 occupies bus
    
    reg [1:0] state, next_state;

    //---------------------------------------------------------
    //State decoding
    always @(*) begin
        case (state)
            AXI_MASTER_0: begin                 //Master 0 occupies bus, priority: 0>1>2>3
                if(m0_AWVALID)                  //If master 0 requests bus
                    next_state = AXI_MASTER_0;  //Maintain master 0 bus occupation
                else if(m0_WVALID||m_WREADY)    //If still writing data
                    next_state = AXI_MASTER_0;  //Maintain master 0 bus occupation
                else if(m_BVALID&&m0_BREADY)    //Write response complete
                    next_state = AXI_MASTER_1;  //Change priority
                else if(m1_AWVALID)             //If master 1 requests bus
                    next_state = AXI_MASTER_1;  //Next state is master 1 bus occupation
                else if(m2_AWVALID)             //If master 2 requests bus
                    next_state = AXI_MASTER_2;  //Next state is master 2 bus occupation
                else if(m3_AWVALID)             //If master 3 requests bus
                    next_state = AXI_MASTER_3;  //Next state is master 3 bus occupation
                else                            //No bus requests
                    next_state = AXI_MASTER_0;  //Maintain master 0 bus occupation
            end
            AXI_MASTER_1: begin                 //Master 1 occupies bus, priority: 1>2>3>0
                if(m1_AWVALID)                  //Similar to previous section
                    next_state = AXI_MASTER_1;
                else if(m1_WVALID||m_WREADY)
                    next_state = AXI_MASTER_1;
                else if(m_BVALID&&m1_BREADY)
                    next_state = AXI_MASTER_2;
                else if(m2_AWVALID)
                    next_state = AXI_MASTER_2;
                else if(m3_AWVALID)
                    next_state = AXI_MASTER_3;
                else if(m0_AWVALID)
                    next_state = AXI_MASTER_0;
                else
                    next_state = AXI_MASTER_1;
            end
            AXI_MASTER_2: begin                 //Master 2 occupies bus, priority: 2>3>0>1
                if(m2_AWVALID)                  //Similar to previous section
                    next_state = AXI_MASTER_2;
                else if(m2_WVALID||m_WREADY)
                    next_state = AXI_MASTER_2;
                else if(m_BVALID&&m2_BREADY)
                    next_state = AXI_MASTER_3;
                else if(m3_AWVALID)
                    next_state = AXI_MASTER_3;
                else if(m0_AWVALID)
                    next_state = AXI_MASTER_0;
                else if(m1_AWVALID)
                    next_state = AXI_MASTER_1;
                else
                    next_state = AXI_MASTER_2;
            end
            AXI_MASTER_3: begin                 //Master 3 occupies bus, priority: 3>0>1>2
                if(m3_AWVALID)                  //Similar to previous section
                    next_state = AXI_MASTER_3;
                else if(m3_WVALID||m_WREADY)
                    next_state = AXI_MASTER_3;
                else if(m_BVALID&&m3_BREADY)
                    next_state = AXI_MASTER_0;
                else if(m0_AWVALID)
                    next_state = AXI_MASTER_0;
                else if(m1_AWVALID)
                    next_state = AXI_MASTER_1;
                else if(m2_AWVALID)
                    next_state = AXI_MASTER_2;
                else
                    next_state = AXI_MASTER_3;
            end
            default:
                next_state = AXI_MASTER_0;      //Default state is master 0 bus occupation
        endcase
    end

    //---------------------------------------------------------
    //Update state register
    always @(posedge ACLK or negedge ARESETn) begin
        if(!ARESETn)
            state <= #TCO AXI_MASTER_0;         //Default state is master 0 bus occupation
        else
            state <= #TCO next_state;
    end

    //---------------------------------------------------------
    //Output control results using state register
    always @(*) begin
        case (state)
            AXI_MASTER_0: {m0_wgrnt,m1_wgrnt,m2_wgrnt,m3_wgrnt} = 4'b1000;
            AXI_MASTER_1: {m0_wgrnt,m1_wgrnt,m2_wgrnt,m3_wgrnt} = 4'b0100;
            AXI_MASTER_2: {m0_wgrnt,m1_wgrnt,m2_wgrnt,m3_wgrnt} = 4'b0010;
            AXI_MASTER_3: {m0_wgrnt,m1_wgrnt,m2_wgrnt,m3_wgrnt} = 4'b0001;
            default:      {m0_wgrnt,m1_wgrnt,m2_wgrnt,m3_wgrnt} = 4'b0000;
        endcase
    end

endmodule