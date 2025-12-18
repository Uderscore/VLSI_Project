//==============================================================================
// Data Loader Module
//==============================================================================
// This module acts as the bridge between the External Interface (DRAM) and 
// the Internal Memory Controller. It handles:
// 1. Loading Input/Weights: External -> SRAM (via Memory Controller)
// 2. Unloading Results: SRAM -> External (with 32-bit to 8-bit Truncation)
// 3. Handshaking: Manages Valid/Ready signals for both sides and AGU.
//
// TIMING ALIGNMENT:
// - LOAD Mode: Simple pass-through with handshaking
// - UNLOAD Mode: FSM-based to handle 3-cycle SRAM read latency
//   * IDLE -> REQUEST_READ (assert agu_rd_data_ready)
//   * REQUEST_READ -> WAIT_DATA (3 cycles for SRAM pipeline)
//   * WAIT_DATA -> OUTPUT_DATA (when agu_rd_data_valid)
//   * OUTPUT_DATA -> IDLE (when tx_ready, then request next address)
//==============================================================================

module data_loader (
    input  wire          clk,
    input  wire          rst_n,

    //--- Control Signals ---
    input  wire          is_loading,      // 1 = Load Mode (Input/Weights), 0 = Unload Mode (Results)
    
    //--- 1. External Interface (Host/DRAM) ---
    // Input Stream (From DRAM)
    input  wire [31:0]   rx_data,         // Data from Host
    input  wire          rx_valid,        // Host has valid data
    output reg           rx_ready,        // We are ready to accept data

    // Output Stream (To DRAM)
    output reg  [7:0]    tx_data,         // Processed Result (Truncated to 8-bit)
    output reg           tx_valid,        // We have valid output data
    input  wire          tx_ready,        // Host is ready to accept result

    //--- 2. AGU Interface (Coordinate with address_generator.v) ---
    input  wire [7:0]    agu_addr,        // From AGU (addr_out)
    input  wire          agu_addr_valid,  // From AGU (addr_valid)
    output reg           agu_next_addr,   // To AGU (next_addr) - Request next address

    //--- 3. Memory Controller Interface (Coordinate with memory_controller.v) ---
    // Write Port (For Loading)
    output reg  [31:0]   agu_wr_data,     // To Memory Controller
    output reg  [7:0]    agu_wr_addr,     // To Memory Controller
    output reg           agu_wr_valid,    // To Memory Controller
    input  wire          agu_wr_ready,    // From Memory Controller

    // Read Port (For Unloading)
    output reg  [7:0]    agu_rd_addr,     // To Memory Controller
    output reg           agu_rd_data_ready,// To Memory Controller (Request Read)
    input  wire [31:0]   agu_rd_data,     // From Memory Controller (Raw 32-bit Result)
    input  wire          agu_rd_data_valid // From Memory Controller
);

    //==========================================================================
    // Unload Mode State Machine
    //==========================================================================
    localparam UNLOAD_IDLE        = 2'd0;  // Waiting for valid address from AGU
    localparam UNLOAD_REQUEST     = 2'd1;  // Requested read from Memory Controller
    localparam UNLOAD_WAIT_DATA   = 2'd2;  // Waiting for data from SRAM (3-cycle latency)
    localparam UNLOAD_OUTPUT      = 2'd3;  // Data valid, outputting to external interface
    
    reg [1:0] unload_state, unload_next_state;
    reg [7:0] latched_data;                 // Store truncated result
    
    //==========================================================================
    // Internal Signals
    //==========================================================================
    // Truncation Logic: Convert 32-bit Accumulation to 8-bit Output
    // If bits [31:8] contain any value, saturate to 255 (0xFF), else pass [7:0]
    wire [7:0] truncated_result;
    assign truncated_result = (|agu_rd_data[31:8]) ? 8'hFF : agu_rd_data[7:0];

    //==========================================================================
    // Unload FSM - State Register
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            unload_state <= UNLOAD_IDLE;
            latched_data <= 8'd0;
        end else begin
            unload_state <= unload_next_state;
            
            // Latch data when it becomes valid
            if (agu_rd_data_valid && unload_state == UNLOAD_WAIT_DATA) begin
                latched_data <= truncated_result;
            end
        end
    end

    //==========================================================================
    // Unload FSM - Next State Logic
    //==========================================================================
    always @(*) begin
        unload_next_state = unload_state;
        
        case (unload_state)
            UNLOAD_IDLE: begin
                // Start read when AGU has valid address and tx is ready
                if (agu_addr_valid && tx_ready) begin
                    unload_next_state = UNLOAD_REQUEST;
                end
            end
            
            UNLOAD_REQUEST: begin
                // Move to wait state immediately after request
                unload_next_state = UNLOAD_WAIT_DATA;
            end
            
            UNLOAD_WAIT_DATA: begin
                // Wait for Memory Controller to return valid data
                if (agu_rd_data_valid) begin
                    unload_next_state = UNLOAD_OUTPUT;
                end
            end
            
            UNLOAD_OUTPUT: begin
                // Output data and wait for tx_ready handshake
                // When successful, request next address and return to IDLE
                if (tx_ready) begin
                    unload_next_state = UNLOAD_IDLE;
                end
            end
            
            default: unload_next_state = UNLOAD_IDLE;
        endcase
    end

    //==========================================================================
    // Main Combinational Logic
    //==========================================================================
    always @(*) begin
        // Defaults
        rx_ready          = 1'b0;
        tx_data           = 8'd0;
        tx_valid          = 1'b0;
        agu_next_addr     = 1'b0;
        
        // Memory Write Defaults
        agu_wr_data       = 32'd0;
        agu_wr_addr       = 8'd0;
        agu_wr_valid      = 1'b0;

        // Memory Read Defaults
        agu_rd_addr       = 8'd0;
        agu_rd_data_ready = 1'b0;

        if (is_loading) begin
            //------------------------------------------------------------------
            // LOAD MODE: Host (rx) -> Memory (wr)
            //------------------------------------------------------------------
            // Simple pass-through with proper handshaking
            agu_wr_data  = rx_data;
            agu_wr_addr  = agu_addr;

            // Three-way handshake: rx_valid && agu_addr_valid && agu_wr_ready
            // All three must be true for successful transaction
            if (rx_valid && agu_addr_valid && agu_wr_ready) begin
                agu_wr_valid   = 1'b1;      // Assert write to Memory Controller
                rx_ready       = 1'b1;      // Acknowledge data from DRAM
                agu_next_addr  = 1'b1;      // Request next address from AGU
            end
        end 
        else begin
            //------------------------------------------------------------------
            // UNLOAD MODE: Memory (rd) -> Host (tx) with FSM
            //------------------------------------------------------------------
            // FSM handles the 3-cycle SRAM read latency and ensures proper
            // alignment between AGU address generation and data output
            
            case (unload_state)
                UNLOAD_IDLE: begin
                    // Wait for AGU to provide valid address and tx to be ready
                    // Do nothing, just waiting
                end
                
                UNLOAD_REQUEST: begin
                    // Issue read request to Memory Controller
                    agu_rd_addr       = agu_addr;
                    agu_rd_data_ready = 1'b1;  // Pulse to start read
                end
                
                UNLOAD_WAIT_DATA: begin
                    // Waiting for SRAM pipeline (3 cycles)
                    // Memory Controller will assert agu_rd_data_valid when ready
                    agu_rd_addr = agu_addr;  // Keep address stable
                end
                
                UNLOAD_OUTPUT: begin
                    // Data is valid (latched in register)
                    // Output to external interface
                    tx_data  = latched_data;
                    tx_valid = 1'b1;
                    
                    // CRITICAL FIX: Only request next address AFTER successful handshake
                    // tx_ready being high means the external interface consumed the data
                    if (tx_ready) begin
                        agu_next_addr = 1'b1;  // Request next address from AGU
                    end
                end
                
                default: begin
                    // Safety defaults
                    tx_data  = 8'd0;
                    tx_valid = 1'b0;
                end
            endcase
        end
    end

endmodule