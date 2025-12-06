/*
 * Address Generation Unit (AGU)
 * 
 * Generates complex address sequences for the systolic array accelerator.
 * Handles address arithmetic for:
 * - Loading: Linear addresses for DRAM → SRAM transfer
 * - Streaming: Sliding window addresses for SRAM → Systolic Array
 * - Unloading: Addresses for results Array → SRAM → DRAM
 * 
 * Key Features:
 * - Tiling support with halo pixel inclusion
 * - 2D to 1D address mapping
 * - Ping-pong buffer aware addressing
 * - Sliding window pattern generation
 */

module agu #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8,
    parameter ARRAY_SIZE = 8,
    parameter MAX_IMAGE_SIZE = 64,
    parameter MAX_KERNEL_SIZE = 16
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Control signals from Control Unit
    input  wire                     go_load,        // Start loading phase
    input  wire                     go_stream,      // Start streaming phase
    input  wire                     go_unload,      // Start unloading phase
    input  wire                     mode_load_weight, // Load weights instead of pixels
    
    // Configuration
    input  wire [7:0]               image_width,    // Input image width
    input  wire [7:0]               image_height,   // Input image height
    input  wire [4:0]               kernel_size,    // Kernel size (3, 5, 7, etc.)
    input  wire [7:0]               num_tiles_x,    // Number of tiles in X direction
    input  wire [7:0]               num_tiles_y,    // Number of tiles in Y direction
    
    // Tile control
    input  wire [7:0]               current_tile_x, // Current tile X index
    input  wire [7:0]               current_tile_y, // Current tile Y index
    
    // Ping-pong buffer control
    input  wire                     active_buffer,  // 0=Ping, 1=Pong
    
    // Status outputs
    output reg                      load_done,
    output reg                      stream_done,
    output reg                      unload_done,
    output reg                      tile_complete,
    output reg                      addr_valid,
    
    // Address outputs for SRAM
    output reg  [ADDR_WIDTH-1:0]    rd_addr,        // Read address
    output reg  [ADDR_WIDTH-1:0]    wr_addr,        // Write address
    output reg                      rd_enable,      // Read enable
    output reg                      wr_enable,      // Write enable
    
    // Sliding window control for systolic array
    output reg  [7:0]               window_x,       // Current window X position
    output reg  [7:0]               window_y,       // Current window Y position
    output reg                      window_valid,   // Window position valid
    
    // DRAM interface addressing
    output reg  [19:0]              dram_rd_addr,   // DRAM read address
    output reg  [19:0]              dram_wr_addr,   // DRAM write address
    output reg                      dram_rd_req,    // Request DRAM read
    output reg                      dram_wr_req     // Request DRAM write
);

    // State machine
    localparam IDLE = 3'b000;
    localparam LOAD = 3'b001;
    localparam STREAM = 3'b010;
    localparam UNLOAD = 3'b011;
    localparam LOAD_WEIGHT = 3'b100;
    
    reg [2:0] state;
    
    // Address computation registers
    reg [7:0] tile_width;           // Width of current tile (including halo)
    reg [7:0] tile_height;          // Height of current tile (including halo)
    reg [7:0] tile_start_x;         // Tile start X in global image
    reg [7:0] tile_start_y;         // Tile start Y in global image
    reg [7:0] halo_size;            // Halo pixels on each side
    
    // Counters for address generation
    reg [7:0] x_counter;
    reg [7:0] y_counter;
    reg [7:0] pixel_counter;
    reg [15:0] total_pixels;
    
    // Sliding window state
    reg [7:0] window_row;
    reg [7:0] window_col;
    reg [7:0] array_cycle;          // Cycle within array processing
    reg [7:0] output_row;
    reg [7:0] output_col;
    
    // Temporary registers for address computation
    reg [7:0] global_x, global_y;
    reg [7:0] out_global_x, out_global_y;
    

	                                reg [7:0] base_row;
				reg [7:0] base_col;


    // Base addresses for ping-pong buffers
    wire [ADDR_WIDTH-1:0] ping_base = 8'h00;
    wire [ADDR_WIDTH-1:0] pong_base = 8'h00;  // Both start at 0, switched by buffer select
    wire [ADDR_WIDTH-1:0] buffer_base = active_buffer ? pong_base : ping_base;
    
	
    // Compute tile dimensions with halo
    always @(*) begin
        halo_size = (kernel_size - 1) >> 1;  // Halo on each side
        
        // Compute tile dimensions including halo
        tile_width = ARRAY_SIZE + (kernel_size - 1);
        tile_height = ARRAY_SIZE + (kernel_size - 1);
        
        // Compute tile start position in global image
        tile_start_x = current_tile_x * ARRAY_SIZE;
        tile_start_y = current_tile_y * ARRAY_SIZE;
        
        // Adjust for boundary tiles (may need clipping)
        total_pixels = tile_width * tile_height;
    end
    
    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            load_done <= 1'b0;
            stream_done <= 1'b0;
            unload_done <= 1'b0;
            tile_complete <= 1'b0;
            addr_valid <= 1'b0;
            rd_addr <= {ADDR_WIDTH{1'b0}};
            wr_addr <= {ADDR_WIDTH{1'b0}};
            rd_enable <= 1'b0;
            wr_enable <= 1'b0;
            window_x <= 8'h0;
            window_y <= 8'h0;
            window_valid <= 1'b0;
            x_counter <= 8'h0;
            y_counter <= 8'h0;
            pixel_counter <= 8'h0;
            window_row <= 8'h0;
            window_col <= 8'h0;
            array_cycle <= 8'h0;
            output_row <= 8'h0;
            output_col <= 8'h0;
            dram_rd_addr <= 20'h0;
            dram_wr_addr <= 20'h0;
            dram_rd_req <= 1'b0;
            dram_wr_req <= 1'b0;
        end else begin
            // Clear single-cycle signals
            load_done <= 1'b0;
            stream_done <= 1'b0;
            unload_done <= 1'b0;
            tile_complete <= 1'b0;
            dram_rd_req <= 1'b0;
            dram_wr_req <= 1'b0;
            
            case (state)
                IDLE: begin
                    addr_valid <= 1'b0;
                    rd_enable <= 1'b0;
                    wr_enable <= 1'b0;
                    window_valid <= 1'b0;
                    
                    if (go_load && mode_load_weight) begin
                        // Load weights
                        state <= LOAD_WEIGHT;
                        x_counter <= 8'h0;
                        y_counter <= 8'h0;
                        pixel_counter <= 8'h0;
                        wr_addr <= buffer_base;
                        dram_rd_addr <= 20'h01000;  // Kernel at offset 0x1000
                    end else if (go_load) begin
                        // Load input tile from DRAM to SRAM
                        state <= LOAD;
                        x_counter <= 8'h0;
                        y_counter <= 8'h0;
                        pixel_counter <= 8'h0;
                        wr_addr <= buffer_base;
                        // Compute DRAM address for tile start
                        dram_rd_addr <= {12'h0, tile_start_y} * image_width + {12'h0, tile_start_x};
                    end else if (go_stream) begin
                        // Stream data to systolic array
                        state <= STREAM;
                        window_row <= 8'h0;
                        window_col <= 8'h0;
                        array_cycle <= 8'h0;
                        rd_addr <= buffer_base;
                    end else if (go_unload) begin
                        // Unload results from array to SRAM
                        state <= UNLOAD;
                        output_row <= 8'h0;
                        output_col <= 8'h0;
                        wr_addr <= buffer_base;
                        // Compute DRAM write address for output tile
                        dram_wr_addr <= 20'h10000 + ({12'h0, current_tile_y} * ARRAY_SIZE * image_width) + 
                                       ({12'h0, current_tile_x} * ARRAY_SIZE);
                    end
                end
                
                LOAD_WEIGHT: begin
                    // Linear loading of kernel weights
                    if (pixel_counter < (kernel_size * kernel_size)) begin
                        wr_enable <= 1'b1;
                        addr_valid <= 1'b1;
                        dram_rd_req <= 1'b1;
                        
                        // Sequential SRAM write address
                        wr_addr <= buffer_base + pixel_counter[ADDR_WIDTH-1:0];
                        
                        // Sequential DRAM read address
                        dram_rd_addr <= 20'h01000 + {12'h0, pixel_counter};
                        
                        pixel_counter <= pixel_counter + 1'b1;
                    end else begin
                        wr_enable <= 1'b0;
                        addr_valid <= 1'b0;
                        load_done <= 1'b1;
                        state <= IDLE;
                    end
                end
                
                LOAD: begin
                    // Load tile with halo from DRAM to SRAM
                    if (y_counter < tile_height) begin
                        if (x_counter < tile_width) begin
                            wr_enable <= 1'b1;
                            addr_valid <= 1'b1;
                            dram_rd_req <= 1'b1;
                            
                            // Compute global image coordinates
                            global_x = tile_start_x + x_counter - halo_size;
                            global_y = tile_start_y + y_counter - halo_size;
                            
                            // Handle boundary conditions (clamp to image bounds)
                            if (global_x >= image_width) global_x = image_width - 1;
                            if (global_y >= image_height) global_y = image_height - 1;
                            
                            // Linear SRAM write address
                            wr_addr <= buffer_base + ((y_counter * tile_width + x_counter) & {{(ADDR_WIDTH){1'b1}}});
                            
                            // Compute DRAM address: y * width + x
                            dram_rd_addr <= {12'h0, global_y} * image_width + {12'h0, global_x};
                            
                            x_counter <= x_counter + 1'b1;
                        end else begin
                            // Move to next row
                            x_counter <= 8'h0;
                            y_counter <= y_counter + 1'b1;
                        end
                    end else begin
                        // Loading complete
                        wr_enable <= 1'b0;
                        addr_valid <= 1'b0;
                        load_done <= 1'b1;
                        state <= IDLE;
                    end
                end
                
                STREAM: begin
                    // Generate sliding window addresses for systolic array
                    // The array processes one window per cycle, output 8x8 tile
                    
                    if (window_row < ARRAY_SIZE) begin
                        if (window_col < ARRAY_SIZE) begin
                            rd_enable <= 1'b1;
                            window_valid <= 1'b1;
                            
                            // Current window position
                            window_x <= window_col;
                            window_y <= window_row;
                            
                            // Generate addresses for the 8 pixels needed this cycle
                            // For systolic array, we feed one diagonal per cycle
                            // Diagonal pattern: row i gets data from column (cycle - i)
                            
                            if (array_cycle < (ARRAY_SIZE + kernel_size - 1)) begin
                                // Generate read address for current diagonal

                                base_row = window_row;
                                base_col = window_col;
                                
                                // Read from sliding window position
                                // Address = (window_y + row) * tile_width + (window_x + col)
                                rd_addr <= buffer_base + 
                                          ((base_row * tile_width + base_col) & {ADDR_WIDTH{1'b1}});
                                
                                array_cycle <= array_cycle + 1'b1;
                            end else begin
                                // Window complete, move to next
                                array_cycle <= 8'h0;
                                
                                if (window_col < ARRAY_SIZE - 1) begin
                                    window_col <= window_col + 1'b1;
                                end else begin
                                    window_col <= 8'h0;
                                    if (window_row < ARRAY_SIZE - 1) begin
                                        window_row <= window_row + 1'b1;
                                    end else begin
                                        // All windows complete
                                        window_row <= 8'h0;
                                        rd_enable <= 1'b0;
                                        window_valid <= 1'b0;
                                        stream_done <= 1'b1;
                                        tile_complete <= 1'b1;
                                        state <= IDLE;
                                    end
                                end
                            end
                        end
                    end
                end
                
                UNLOAD: begin
                    // Unload results from systolic array to SRAM then DRAM
                    if (output_row < ARRAY_SIZE) begin
                        if (output_col < ARRAY_SIZE) begin
                            wr_enable <= 1'b1;
                            addr_valid <= 1'b1;
                            dram_wr_req <= 1'b1;
                            
                            // Compute DRAM write address
                            // Output position in global image
                            out_global_x = current_tile_x * ARRAY_SIZE + output_col;
                            out_global_y = current_tile_y * ARRAY_SIZE + output_row;
                            
                            // Write to SRAM buffer
                            wr_addr <= buffer_base + ((output_row * ARRAY_SIZE + output_col) & {{(ADDR_WIDTH){1'b1}}});
                            
                            dram_wr_addr <= 20'h10000 + 
                                          ({12'h0, out_global_y} * image_width + {12'h0, out_global_x});
                            
                            output_col <= output_col + 1'b1;
                        end else begin
                            output_col <= 8'h0;
                            output_row <= output_row + 1'b1;
                        end
                    end else begin
                        // Unloading complete
                        wr_enable <= 1'b0;
                        addr_valid <= 1'b0;
                        unload_done <= 1'b1;
                        state <= IDLE;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
    
    // Debug monitoring
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (load_done)
            $display("[AGU] Load phase complete - Tile (%0d,%0d)", current_tile_x, current_tile_y);
        if (stream_done)
            $display("[AGU] Stream phase complete - Tile (%0d,%0d)", current_tile_x, current_tile_y);
        if (unload_done)
            $display("[AGU] Unload phase complete - Tile (%0d,%0d)", current_tile_x, current_tile_y);
        if (tile_complete)
            $display("[AGU] Tile processing complete");
    end
    `endif

endmodule