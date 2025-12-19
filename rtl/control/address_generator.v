//==============================================================================
// Address Generation Unit (AGU) for Convolution Accelerator
//==============================================================================
// This module generates memory addresses for:
// 1. Loading input data (LOAD_INPUT) - Linear addressing
// 2. Loading weights (LOAD_WEIGHT) - Linear addressing for kernel
// 3. Streaming data to Systolic Array (STREAM) - Sliding window pattern
// 4. Unloading results (UNLOAD) - Linear addressing for output
//
// Key Features:
// - 2D to 1D address mapping: addr = y * width + x
// - Sliding window address generation for convolution
// - Tile management with halo overlap
// - Configurable N (image size) and K (kernel size)
// - Proper valid/ready handshaking protocol
//==============================================================================

module address_generator #(
    parameter ADDR_WIDTH    = 8,    // Address width (256 SRAM locations)
    parameter ARRAY_SIZE    = 8,    // Systolic array dimension (8x8)
    parameter MAX_IMG_SIZE  = 64,   // Maximum supported image dimension
    parameter DATA_WIDTH    = 32    // Data bus width
)(
    // Clock and Reset
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Configuration Interface
    input  wire [6:0]               cfg_N,          // Image dimension (8-64)
    input  wire [2:0]               cfg_K,          // Kernel size (3, 5, or 7)
    input  wire                     cfg_valid,      // Latch configuration
    
    // Control Interface
    input  wire                     start,          // Start address generation
    input  wire [1:0]               mode,           // Operation mode
    input  wire                     next_addr,      // Request next address (handshake)
    
    // Tile Control (from Control Unit)
    input  wire [2:0]               tile_x,         // Current tile X coordinate
    input  wire [2:0]               tile_y,         // Current tile Y coordinate
    input  wire                     next_tile,      // Move to next tile
    
    // Address Output
    output reg  [ADDR_WIDTH-1:0]    addr_out,       // Generated memory address
    output reg                      addr_valid,     // Address is valid
    output reg  [2:0]               row_idx,        // Current row within tile
    output reg  [2:0]               col_idx,        // Current column within tile
    
    // Status Outputs
    output reg                      busy,           // AGU is generating addresses
    output reg                      tile_done,      // Current tile complete
    output reg                      frame_done      // Entire image processed
);

    //==========================================================================
    // Operation Mode Encoding
    //==========================================================================
    localparam MODE_IDLE        = 2'b00;
    localparam MODE_LOAD_INPUT  = 2'b01;    // Load input tile to SRAM
    localparam MODE_STREAM      = 2'b10;    // Stream to systolic array
    localparam MODE_UNLOAD      = 2'b11;    // Unload results from SRAM

    //==========================================================================
    // State Machine States
    //==========================================================================
    localparam STATE_IDLE       = 3'd0;
    localparam STATE_CONFIG     = 3'd1;
    localparam STATE_LOAD       = 3'd2;
    localparam STATE_STREAM     = 3'd3;
    localparam STATE_UNLOAD     = 3'd4;
    localparam STATE_TILE_DONE  = 3'd5;
    localparam STATE_FRAME_DONE = 3'd6;

    //==========================================================================
    // Internal Registers
    //==========================================================================
    reg [2:0]  state, next_state;
    
    // Latched configuration
    reg [6:0]  cfg_N_reg;           // Image dimension
    reg [2:0]  cfg_K_reg;           // Kernel size
    reg [3:0]  input_tile_size;     // ARRAY_SIZE + (K - 1)
    
    // Address counters
    reg [11:0] linear_addr;         // For linear addressing (up to 4096)
    reg [6:0]  x_coord, y_coord;    // 2D coordinates within image
    reg [3:0]  tile_row, tile_col;  // Position within current tile
    reg [2:0]  kernel_row, kernel_col; // Position within kernel (for STREAM)
    
    // Tile tracking
    reg [2:0]  current_tile_x, current_tile_y;
    reg [2:0]  num_tiles_x, num_tiles_y;
    
    // Handshake control
    reg        addr_consumed;       // Current address has been consumed
    
    // Computed base addresses
    wire [6:0] tile_base_x, tile_base_y;
    wire [11:0] base_addr;
    
    // Current address computation (combinational)
    wire [11:0] computed_addr;

    //==========================================================================
    // Tile Base Address Calculation
    //==========================================================================
    assign tile_base_x = current_tile_x * ARRAY_SIZE;
    assign tile_base_y = current_tile_y * ARRAY_SIZE;
    assign base_addr = tile_base_y * cfg_N_reg + tile_base_x;

    //==========================================================================
    // Address Computation (Combinational)
    //==========================================================================
    // Compute address based on current state and counters
    always @(*) begin
        case (state)
            STATE_LOAD, STATE_UNLOAD: begin
                // Linear addressing within tile
                addr_out = ((tile_base_y + tile_row) * cfg_N_reg + (tile_base_x + tile_col));
                row_idx = tile_row[2:0];
                col_idx = tile_col[2:0];
            end
            STATE_STREAM: begin
                // Sliding window addressing
                addr_out = ((tile_base_y + tile_row[2:0] + kernel_row) * cfg_N_reg + 
                           (tile_base_x + tile_col[2:0] + kernel_col));
                row_idx = tile_row[2:0];
                col_idx = tile_col[2:0];
            end
            default: begin
                addr_out = 8'd0;
                row_idx = 3'd0;
                col_idx = 3'd0;
            end
        endcase
    end

    //==========================================================================
    // Number of Tiles Calculation
    //==========================================================================
    always @(*) begin
        if (cfg_N_reg <= 8)
            num_tiles_x = 3'd1;
        else if (cfg_N_reg <= 16)
            num_tiles_x = 3'd2;
        else if (cfg_N_reg <= 24)
            num_tiles_x = 3'd3;
        else if (cfg_N_reg <= 32)
            num_tiles_x = 3'd4;
        else if (cfg_N_reg <= 40)
            num_tiles_x = 3'd5;
        else if (cfg_N_reg <= 48)
            num_tiles_x = 3'd6;
        else if (cfg_N_reg <= 56)
            num_tiles_x = 3'd7;
        else
            num_tiles_x = 3'd0;
    end
    
    always @(*) begin
        num_tiles_y = num_tiles_x;
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
    // State Machine - Combinational Logic
    //==========================================================================
    always @(*) begin
        next_state = state;
        
        case (state)
            STATE_IDLE: begin
                if (cfg_valid)
                    next_state = STATE_CONFIG;
                else if (start && mode == MODE_LOAD_INPUT)
                    next_state = STATE_LOAD;
                else if (start && mode == MODE_STREAM)
                    next_state = STATE_STREAM;
                else if (start && mode == MODE_UNLOAD)
                    next_state = STATE_UNLOAD;
            end
            
            STATE_CONFIG: begin
                next_state = STATE_IDLE;
            end
            
            STATE_LOAD: begin
                if (tile_row >= input_tile_size - 1 && tile_col >= input_tile_size - 1 && next_addr)
                    next_state = STATE_TILE_DONE;
            end
            
            STATE_STREAM: begin
                if (tile_row >= ARRAY_SIZE - 1 && tile_col >= ARRAY_SIZE - 1 && 
                    kernel_row >= cfg_K_reg - 1 && kernel_col >= cfg_K_reg - 1 && next_addr)
                    next_state = STATE_TILE_DONE;
            end
            
            STATE_UNLOAD: begin
                if (tile_row >= ARRAY_SIZE - 1 && tile_col >= ARRAY_SIZE - 1 && next_addr)
                    next_state = STATE_TILE_DONE;
            end
            
            STATE_TILE_DONE: begin
                if (next_tile) begin
                    if ((current_tile_x >= num_tiles_x - 1 || num_tiles_x == 0) && 
                        (current_tile_y >= num_tiles_y - 1 || num_tiles_y == 0))
                        next_state = STATE_FRAME_DONE;
                    else
                        next_state = STATE_IDLE;
                end
            end
            
            STATE_FRAME_DONE: begin
                if (start)
                    next_state = STATE_IDLE;
            end
            
            default: next_state = STATE_IDLE;
        endcase
    end

    //==========================================================================
    // Counter and Control Logic
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_N_reg        <= 7'd16;
            cfg_K_reg        <= 3'd3;
            input_tile_size  <= 4'd10;
            linear_addr      <= 12'd0;
            x_coord          <= 7'd0;
            y_coord          <= 7'd0;
            tile_row         <= 4'd0;
            tile_col         <= 4'd0;
            kernel_row       <= 3'd0;
            kernel_col       <= 3'd0;
            current_tile_x   <= 3'd0;
            current_tile_y   <= 3'd0;
            addr_valid       <= 1'b0;
            busy             <= 1'b0;
            tile_done        <= 1'b0;
            frame_done       <= 1'b0;
            addr_consumed    <= 1'b0;
        end
        else begin
            // Default pulse outputs
            tile_done  <= 1'b0;
            frame_done <= 1'b0;
            
            case (state)
                STATE_IDLE: begin
                    busy         <= 1'b0;
                    addr_valid   <= 1'b0;
                    tile_row     <= 4'd0;
                    tile_col     <= 4'd0;
                    kernel_row   <= 3'd0;
                    kernel_col   <= 3'd0;
                    addr_consumed <= 1'b0;
                    
                    if (start) begin
                        current_tile_x <= tile_x;
                        current_tile_y <= tile_y;
                    end
                end
                
                STATE_CONFIG: begin
                    busy            <= 1'b1;  // Set busy during config to prevent race
                    cfg_N_reg       <= cfg_N;
                    cfg_K_reg       <= cfg_K;
                    input_tile_size <= ARRAY_SIZE + cfg_K - 1;
                    current_tile_x  <= 3'd0;
                    current_tile_y  <= 3'd0;
                end
                
                STATE_LOAD: begin
                    busy <= 1'b1;
                    
                    // Valid/Ready handshaking: set valid when address is ready
                    // Clear valid when consumed, set again after counter updates
                    if (next_addr) begin
                        // Address consumed, will update counter
                        addr_valid <= 1'b0;
                        addr_consumed <= 1'b1;
                        
                        // Advance counter
                        if (tile_col < input_tile_size - 1) begin
                            tile_col <= tile_col + 1;
                        end else begin
                            tile_col <= 4'd0;
                            if (tile_row < input_tile_size - 1) begin
                                tile_row <= tile_row + 1;
                            end
                        end
                    end else if (addr_consumed || !addr_valid) begin
                        // Address updated or first address, now valid
                        addr_valid <= 1'b1;
                        addr_consumed <= 1'b0;
                    end
                end
                
                STATE_STREAM: begin
                    busy <= 1'b1;
                    
                    if (next_addr) begin
                        addr_valid <= 1'b0;
                        addr_consumed <= 1'b1;
                        
                        // Advance through kernel, then output position
                        if (kernel_col < cfg_K_reg - 1) begin
                            kernel_col <= kernel_col + 1;
                        end else begin
                            kernel_col <= 3'd0;
                            if (kernel_row < cfg_K_reg - 1) begin
                                kernel_row <= kernel_row + 1;
                            end else begin
                                kernel_row <= 3'd0;
                                if (tile_col < ARRAY_SIZE - 1) begin
                                    tile_col <= tile_col + 1;
                                end else begin
                                    tile_col <= 4'd0;
                                    if (tile_row < ARRAY_SIZE - 1) begin
                                        tile_row <= tile_row + 1;
                                    end
                                end
                            end
                        end
                    end else if (addr_consumed || !addr_valid) begin
                        addr_valid <= 1'b1;
                        addr_consumed <= 1'b0;
                    end
                end
                
                STATE_UNLOAD: begin
                    busy <= 1'b1;
                    
                    if (next_addr) begin
                        addr_valid <= 1'b0;
                        addr_consumed <= 1'b1;
                        
                        if (tile_col < ARRAY_SIZE - 1) begin
                            tile_col <= tile_col + 1;
                        end else begin
                            tile_col <= 4'd0;
                            if (tile_row < ARRAY_SIZE - 1) begin
                                tile_row <= tile_row + 1;
                            end
                        end
                    end else if (addr_consumed || !addr_valid) begin
                        addr_valid <= 1'b1;
                        addr_consumed <= 1'b0;
                    end
                end
                
                STATE_TILE_DONE: begin
                    busy       <= 1'b0;
                    addr_valid <= 1'b0;
                    tile_done  <= 1'b1;
                    
                    if (next_tile) begin
                        tile_row   <= 4'd0;
                        tile_col   <= 4'd0;
                        kernel_row <= 3'd0;
                        kernel_col <= 3'd0;
                        
                        if (current_tile_x < num_tiles_x - 1) begin
                            current_tile_x <= current_tile_x + 1;
                        end else begin
                            current_tile_x <= 3'd0;
                            current_tile_y <= current_tile_y + 1;
                        end
                    end
                end
                
                STATE_FRAME_DONE: begin
                    busy       <= 1'b0;
                    addr_valid <= 1'b0;
                    frame_done <= 1'b1;
                    
                    if (start) begin
                        current_tile_x <= 3'd0;
                        current_tile_y <= 3'd0;
                    end
                end
                
                default: begin
                    busy       <= 1'b0;
                    addr_valid <= 1'b0;
                end
            endcase
        end
    end

    //==========================================================================
    // Debug Output (Simulation Only)
    //==========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (addr_valid && next_addr) begin
            case (state)
                STATE_LOAD:
                    $display("Time %0t: AGU LOAD - tile(%0d,%0d) pos(%0d,%0d) -> addr=%0d",
                             $time, current_tile_x, current_tile_y, tile_row, tile_col, addr_out);
                STATE_STREAM:
                    $display("Time %0t: AGU STREAM - out(%0d,%0d) kernel(%0d,%0d) -> addr=%0d",
                             $time, tile_row, tile_col, kernel_row, kernel_col, addr_out);
                STATE_UNLOAD:
                    $display("Time %0t: AGU UNLOAD - tile(%0d,%0d) pos(%0d,%0d) -> addr=%0d",
                             $time, current_tile_x, current_tile_y, tile_row, tile_col, addr_out);
            endcase
        end
    end
    `endif

endmodule
