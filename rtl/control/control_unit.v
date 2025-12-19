//==============================================================================
// Control Unit (Main FSM) for Convolution Accelerator
//==============================================================================
// This module acts as the system orchestrator. It manages the global states:
//   - IDLE: Waiting for Host to initiate processing
//   - LOAD: Loading input data and weights into SRAM buffers
//   - COMPUTE: Streaming data through Systolic Array for convolution
//   - DRAIN: Unloading results from SRAM to external interface
//
// Responsibilities:
//   1. Latching configuration inputs (cfg_N, cfg_K)
//   2. Handling handshake with Host interface
//   3. Triggering the AGU with appropriate modes
//   4. Coordinating tile-by-tile processing
//==============================================================================

module control_unit #(
    parameter ADDR_WIDTH   = 8,     // Address width for SRAM
    parameter ARRAY_SIZE   = 8,     // Systolic array dimension
    parameter MAX_IMG_SIZE = 64     // Maximum supported image dimension
)(
    // Clock and Reset
    input  wire                     clk,
    input  wire                     rst_n,
    
    //==========================================================================
    // Host Interface (External)
    //==========================================================================
    input  wire [6:0]               cfg_N,          // Image dimension (8-64)
    input  wire [2:0]               cfg_K,          // Kernel size (3, 5, or 7)
    input  wire                     host_start,     // Start processing command
    input  wire                     host_data_valid,// Host has valid data to send
    input  wire                     host_ready,     // Host ready to receive results
    output reg                      host_ack,       // Acknowledge to Host
    output reg                      busy,           // System is busy processing
    output reg                      done,           // Processing complete
    
    //==========================================================================
    // Configuration Output (to AGU)
    //==========================================================================
    output reg  [6:0]               cfg_N_latched,  // Latched image dimension
    output reg  [2:0]               cfg_K_latched,  // Latched kernel size
    output reg                      cfg_valid,      // Configuration valid pulse
    
    //==========================================================================
    // AGU Control Interface
    //==========================================================================
    output reg                      agu_start,      // Start signal to AGU
    output reg  [1:0]               agu_mode,       // Operation mode for AGU
    output reg  [2:0]               agu_tile_x,     // Current tile X coordinate
    output reg  [2:0]               agu_tile_y,     // Current tile Y coordinate
    output reg                      agu_next_tile,  // Signal to advance to next tile
    input  wire                     agu_busy,       // AGU is generating addresses
    input  wire                     agu_tile_done,  // Current tile complete
    input  wire                     agu_frame_done, // Entire frame processed
    
    //==========================================================================
    // Data Loader Control Interface
    //==========================================================================
    output reg                      loader_is_loading, // 1=Load mode, 0=Unload mode
    
    //==========================================================================
    // Systolic Array Control
    //==========================================================================
    output reg                      sa_enable,      // Enable systolic array
    output reg                      sa_load_weight, // Weight loading mode
    output reg                      sa_clear_acc,   // Clear accumulators
    
    //==========================================================================
    // Memory Controller Control
    //==========================================================================
    output reg                      mem_start,      // Start memory controller
    output reg                      mem_buffer_switch // Trigger buffer switch
);

    //==========================================================================
    // AGU Mode Encoding (must match address_generator.v)
    //==========================================================================
    localparam MODE_IDLE        = 2'b00;
    localparam MODE_LOAD_INPUT  = 2'b01;
    localparam MODE_STREAM      = 2'b10;
    localparam MODE_UNLOAD      = 2'b11;

    //==========================================================================
    // FSM State Encoding
    //==========================================================================
    localparam STATE_IDLE       = 3'd0;
    localparam STATE_CONFIG     = 3'd1;
    localparam STATE_LOAD       = 3'd2;
    localparam STATE_COMPUTE    = 3'd3;
    localparam STATE_DRAIN      = 3'd4;
    localparam STATE_DONE       = 3'd5;
    
    //==========================================================================
    // Internal Registers
    //==========================================================================
    reg [2:0]  state, next_state;
    
    // Tile tracking
    reg [2:0]  current_tile_x, current_tile_y;
    reg [2:0]  num_tiles_x, num_tiles_y;
    reg        all_tiles_loaded;
    reg        all_tiles_computed;
    reg        all_tiles_drained;
    
    // Phase tracking within states
    reg        load_started;
    reg        compute_started;
    reg        drain_started;
    reg        weight_load_done;
    
    // First entry flags (for tile counter reset only once per phase)
    reg        compute_phase_init;
    reg        drain_phase_init;
    reg [1:0]  state_timer;     // Timer for state stability
    
    // Edge detection for tile_done
    reg        agu_tile_done_d;
    wire       agu_tile_done_pulse;
    
    //==========================================================================
    // Edge Detection for AGU Tile Done
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            agu_tile_done_d <= 1'b0;
        else
            agu_tile_done_d <= agu_tile_done;
    end
    
    assign agu_tile_done_pulse = agu_tile_done && !agu_tile_done_d;

    //==========================================================================
    // Number of Tiles Calculation (based on image size)
    //==========================================================================
    always @(*) begin
        if (cfg_N_latched <= 8)
            num_tiles_x = 3'd1;
        else if (cfg_N_latched <= 16)
            num_tiles_x = 3'd2;
        else if (cfg_N_latched <= 24)
            num_tiles_x = 3'd3;
        else if (cfg_N_latched <= 32)
            num_tiles_x = 3'd4;
        else if (cfg_N_latched <= 40)
            num_tiles_x = 3'd5;
        else if (cfg_N_latched <= 48)
            num_tiles_x = 3'd6;
        else if (cfg_N_latched <= 56)
            num_tiles_x = 3'd7;
        else
            num_tiles_x = 3'd0; // Overflow case
        
        num_tiles_y = num_tiles_x; // Square image assumption
    end

    //==========================================================================
    // State Machine - Sequential Logic
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= next_state;
        end
    end

    //==========================================================================
    // State Machine - Combinational Next State Logic
    //==========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (host_start && host_data_valid)
                    next_state = STATE_CONFIG;
            end
            
            STATE_CONFIG: begin
                // Move to LOAD after configuration is latched
                next_state = STATE_LOAD;
            end
            
            STATE_LOAD: begin
                // Transition to COMPUTE when all tiles are loaded
                if (all_tiles_loaded && !agu_busy)
                    next_state = STATE_COMPUTE;
            end
            
            STATE_COMPUTE: begin
                // Transition to DRAIN when computation is complete
                if (all_tiles_computed && !agu_busy)
                    next_state = STATE_DRAIN;
            end
            
            STATE_DRAIN: begin
                // Transition to DONE when all results are drained
                if (all_tiles_drained && !agu_busy)
                    next_state = STATE_DONE;
            end
            
            STATE_DONE: begin
                // Return to IDLE when host acknowledges
                if (!host_start)
                    next_state = STATE_IDLE;
            end
            
            default: next_state = STATE_IDLE;
        endcase
    end

    //==========================================================================
    // Main Control Logic - Sequential
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Configuration
            cfg_N_latched      <= 7'd16;    // Default 16x16
            cfg_K_latched      <= 3'd3;     // Default 3x3 kernel
            cfg_valid          <= 1'b0;
            
            // Host interface
            host_ack           <= 1'b0;
            busy               <= 1'b0;
            done               <= 1'b0;
            
            // AGU control
            agu_start          <= 1'b0;
            agu_mode           <= MODE_IDLE;
            agu_tile_x         <= 3'd0;
            agu_tile_y         <= 3'd0;
            agu_next_tile      <= 1'b0;
            
            // Data loader
            loader_is_loading  <= 1'b1;
            
            // Systolic array
            sa_enable          <= 1'b0;
            sa_load_weight     <= 1'b0;
            sa_clear_acc       <= 1'b0;
            
            // Memory controller
            mem_start          <= 1'b0;
            mem_buffer_switch  <= 1'b0;
            
            // Tile tracking
            current_tile_x     <= 3'd0;
            current_tile_y     <= 3'd0;
            all_tiles_loaded   <= 1'b0;
            all_tiles_computed <= 1'b0;
            all_tiles_drained  <= 1'b0;
            
            // Phase tracking
            load_started       <= 1'b0;
            compute_started    <= 1'b0;
            drain_started      <= 1'b0;
            weight_load_done   <= 1'b0;
            compute_phase_init <= 1'b0;
            drain_phase_init   <= 1'b0;
            
        end else begin
            // Default pulse signals
            cfg_valid          <= 1'b0;
            agu_start          <= 1'b0;
            agu_next_tile      <= 1'b0;
            host_ack           <= 1'b0;
            mem_buffer_switch  <= 1'b0;
            sa_clear_acc       <= 1'b0;
            
            case (state)
                //==============================================================
                // IDLE State: Wait for Host to initiate
                //==============================================================
                STATE_IDLE: begin
                    busy               <= 1'b0;
                    done               <= 1'b0;
                    sa_enable          <= 1'b0;
                    sa_load_weight     <= 1'b0;
                    loader_is_loading  <= 1'b1;
                    
                    // Reset tracking
                    current_tile_x     <= 3'd0;
                    current_tile_y     <= 3'd0;
                    all_tiles_loaded   <= 1'b0;
                    all_tiles_computed <= 1'b0;
                    all_tiles_drained  <= 1'b0;
                    load_started       <= 1'b0;
                    compute_started    <= 1'b0;
                    drain_started      <= 1'b0;
                    weight_load_done   <= 1'b0;
                    compute_phase_init <= 1'b0;
                    drain_phase_init   <= 1'b0;
                    state_timer        <= 2'd0;
                    
                    if (host_start && host_data_valid) begin
                        host_ack <= 1'b1;  // Acknowledge start
                        busy     <= 1'b1;
                    end
                end
                
                //==============================================================
                // CONFIG State: Latch configuration
                //==============================================================
                STATE_CONFIG: begin
                    busy <= 1'b1;
                    
                    // Latch configuration
                    cfg_N_latched <= cfg_N;
                    cfg_K_latched <= cfg_K;
                    cfg_valid     <= 1'b1;  // Pulse to AGU
                    
                    // Clear accumulators before starting
                    sa_clear_acc  <= 1'b1;
                    
                    // Start memory controller
                    mem_start     <= 1'b1;
                    
                    state_timer   <= 2'd0; // Reset timer for next state
                end
                
                //==============================================================
                // LOAD State: Load input data and weights
                //==============================================================
                STATE_LOAD: begin
                    busy              <= 1'b1;
                    loader_is_loading <= 1'b1;
                    
                    // Force 1-cycle wait upon entering LOAD to allow AGU to process config
                    if (!load_started && !agu_busy && state_timer > 0) begin
                        agu_mode      <= MODE_LOAD_INPUT;
                        agu_tile_x    <= current_tile_x;
                        agu_tile_y    <= current_tile_y;
                        agu_start     <= 1'b1;
                        load_started  <= 1'b1;
                    end
                    
                    if (state_timer < 3) state_timer <= state_timer + 1; // Counter for stability
                    
                    // Handle tile completion
                    if (agu_tile_done_pulse) begin
                        if ((current_tile_x >= num_tiles_x - 1 || num_tiles_x == 0) && 
                            (current_tile_y >= num_tiles_y - 1 || num_tiles_y == 0)) begin
                            // All tiles loaded
                            all_tiles_loaded <= 1'b1;
                            mem_buffer_switch <= 1'b1; // Switch to read mode
                        end else begin
                            // Move to next tile
                            agu_next_tile <= 1'b1;
                            load_started  <= 1'b0; // Allow restart for next tile
                            
                            if (current_tile_x < num_tiles_x - 1) begin
                                current_tile_x <= current_tile_x + 1;
                            end else begin
                                current_tile_x <= 3'd0;
                                current_tile_y <= current_tile_y + 1;
                            end
                        end
                    end
                end
                
                //==============================================================
                // COMPUTE State: Stream data through Systolic Array
                //==============================================================
                STATE_COMPUTE: begin
                    busy              <= 1'b1;
                    sa_enable         <= 1'b1;
                    loader_is_loading <= 1'b1; // Still reading from SRAM
                    
                    // Reset tile counters ONLY on first entry to compute phase
                    if (!compute_phase_init) begin
                        current_tile_x     <= 3'd0;
                        current_tile_y     <= 3'd0;
                        compute_phase_init <= 1'b1;
                    end
                    
                    // Start AGU for streaming if not already started
                    if (!compute_started && !agu_busy) begin
                        agu_mode        <= MODE_STREAM;
                        agu_tile_x      <= current_tile_x;
                        agu_tile_y      <= current_tile_y;
                        agu_start       <= 1'b1;
                        compute_started <= 1'b1;
                    end
                    
                    // Handle tile completion
                    if (agu_tile_done_pulse) begin
                        if ((current_tile_x >= num_tiles_x - 1 || num_tiles_x == 0) && 
                            (current_tile_y >= num_tiles_y - 1 || num_tiles_y == 0)) begin
                            // All tiles computed
                            all_tiles_computed <= 1'b1;
                        end else begin
                            // Move to next tile
                            agu_next_tile   <= 1'b1;
                            compute_started <= 1'b0;
                            
                            if (current_tile_x < num_tiles_x - 1) begin
                                current_tile_x <= current_tile_x + 1;
                            end else begin
                                current_tile_x <= 3'd0;
                                current_tile_y <= current_tile_y + 1;
                            end
                        end
                    end
                end
                
                //==============================================================
                // DRAIN State: Unload results to Host
                //==============================================================
                STATE_DRAIN: begin
                    busy              <= 1'b1;
                    sa_enable         <= 1'b0;
                    loader_is_loading <= 1'b0; // Switch to unload mode
                    
                    // Reset tile counters ONLY on first entry to drain phase
                    if (!drain_phase_init) begin
                        current_tile_x   <= 3'd0;
                        current_tile_y   <= 3'd0;
                        drain_phase_init <= 1'b1;
                    end
                    
                    // Start AGU for unloading if not already started
                    if (!drain_started && !agu_busy) begin
                        agu_mode      <= MODE_UNLOAD;
                        agu_tile_x    <= current_tile_x;
                        agu_tile_y    <= current_tile_y;
                        agu_start     <= 1'b1;
                        drain_started <= 1'b1;
                    end
                    
                    // Handle tile completion
                    if (agu_tile_done_pulse) begin
                        if ((current_tile_x >= num_tiles_x - 1 || num_tiles_x == 0) && 
                            (current_tile_y >= num_tiles_y - 1 || num_tiles_y == 0)) begin
                            // All results drained
                            all_tiles_drained <= 1'b1;
                        end else begin
                            // Move to next tile
                            agu_next_tile <= 1'b1;
                            drain_started <= 1'b0;
                            
                            if (current_tile_x < num_tiles_x - 1) begin
                                current_tile_x <= current_tile_x + 1;
                            end else begin
                                current_tile_x <= 3'd0;
                                current_tile_y <= current_tile_y + 1;
                            end
                        end
                    end
                end
                
                //==============================================================
                // DONE State: Signal completion to Host
                //==============================================================
                STATE_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    
                    sa_enable      <= 1'b0;
                    sa_load_weight <= 1'b0;
                end
                
                default: begin
                    busy <= 1'b0;
                    done <= 1'b0;
                end
            endcase
        end
    end

    //==========================================================================
    // Debug Output (Simulation Only)
    //==========================================================================
    `ifdef SIMULATION
    reg [2:0] state_d;
    always @(posedge clk) begin
        state_d <= state;
        if (state != state_d) begin
            case (state)
                STATE_IDLE:    $display("Time %0t: CONTROL_UNIT -> IDLE", $time);
                STATE_CONFIG:  $display("Time %0t: CONTROL_UNIT -> CONFIG (N=%0d, K=%0d)", $time, cfg_N, cfg_K);
                STATE_LOAD:    $display("Time %0t: CONTROL_UNIT -> LOAD", $time);
                STATE_COMPUTE: $display("Time %0t: CONTROL_UNIT -> COMPUTE", $time);
                STATE_DRAIN:   $display("Time %0t: CONTROL_UNIT -> DRAIN", $time);
                STATE_DONE:    $display("Time %0t: CONTROL_UNIT -> DONE", $time);
            endcase
        end
        
        if (agu_tile_done_pulse) begin
            $display("Time %0t: CONTROL_UNIT - Tile (%0d,%0d) complete", 
                     $time, current_tile_x, current_tile_y);
        end
    end
    `endif

endmodule
