/*
 * Data Loader Module
 * 
 * Orchestrates data movement between DRAM, SRAM, and Systolic Array.
 * Works in conjunction with AGU for address generation.
 * Implements ping-pong buffering for continuous data flow.
 * 
 * Key Responsibilities:
 * - DRAM ↔ SRAM data transfers with handshaking
 * - SRAM ↔ Systolic Array data streaming
 * - Ping-pong buffer management
 * - Flow control to prevent stalls
 */

module data_loader #(
    parameter DATA_WIDTH = 8,
    parameter PSUM_WIDTH = 32,
    parameter ADDR_WIDTH = 8,
    parameter ARRAY_SIZE = 8,
    parameter DRAM_WIDTH = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Control signals from Control Unit
    input  wire                     start,
    input  wire                     go_load,
    input  wire                     go_stream,
    input  wire                     go_unload,
    input  wire                     mode_load_weight,
    
    // Configuration
    input  wire [7:0]               image_width,
    input  wire [7:0]               image_height,
    input  wire [4:0]               kernel_size,
    input  wire [7:0]               num_tiles_x,
    input  wire [7:0]               num_tiles_y,
    input  wire [7:0]               current_tile_x,
    input  wire [7:0]               current_tile_y,
    
    // Status outputs
    output wire                     load_done,
    output wire                     stream_done,
    output wire                     unload_done,
    output reg                      buffer_ready,
    output reg                      active_buffer,  // 0=Ping, 1=Pong
    
    // DRAM Interface (streaming)
    input  wire [DRAM_WIDTH-1:0]    dram_rx_data,
    input  wire                     dram_rx_valid,
    output wire                     dram_rx_ready,
    output wire [DRAM_WIDTH-1:0]    dram_tx_data,
    output wire                     dram_tx_valid,
    input  wire                     dram_tx_ready,
    
    // SRAM Interface
    output wire                     sram_start,
    output wire                     sram_buffer_switch,
    input  wire                     sram_ready,
    input  wire                     sram_wr_buffer_full,
    input  wire                     sram_rd_buffer_empty,
    
    // SRAM Write Interface (Data Loader → SRAM)
    output reg                      sram_wr_valid,
    input  wire                     sram_wr_ready,
    output reg  [DATA_WIDTH-1:0]    sram_wr_data,
    output wire [ADDR_WIDTH-1:0]    sram_wr_addr,
    
    // SRAM Read Interface (SRAM → Data Loader)
    output reg                      sram_rd_ready,
    input  wire                     sram_rd_valid,
    input  wire [DATA_WIDTH-1:0]    sram_rd_data,
    output wire [ADDR_WIDTH-1:0]    sram_rd_addr,
    
    // Systolic Array Interface
    output reg  [ARRAY_SIZE*DATA_WIDTH-1:0]  pixel_out,
    output reg                                pixel_valid,
    input  wire [ARRAY_SIZE*PSUM_WIDTH-1:0]  psum_in,
    input  wire                               psum_valid
);

    // AGU instance
    wire                     agu_addr_valid;
    wire [ADDR_WIDTH-1:0]    agu_rd_addr;
    wire [ADDR_WIDTH-1:0]    agu_wr_addr;
    wire                     agu_rd_enable;
    wire                     agu_wr_enable;
    wire [7:0]               agu_window_x;
    wire [7:0]               agu_window_y;
    wire                     agu_window_valid;
    wire [19:0]              agu_dram_rd_addr;
    wire [19:0]              agu_dram_wr_addr;
    wire                     agu_dram_rd_req;
    wire                     agu_dram_wr_req;
    wire                     agu_tile_complete;
    
    agu #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE),
        .MAX_IMAGE_SIZE(64),
        .MAX_KERNEL_SIZE(16)
    ) agu_inst (
        .clk(clk),
        .rst_n(rst_n),
        .go_load(go_load),
        .go_stream(go_stream),
        .go_unload(go_unload),
        .mode_load_weight(mode_load_weight),
        .image_width(image_width),
        .image_height(image_height),
        .kernel_size(kernel_size),
        .num_tiles_x(num_tiles_x),
        .num_tiles_y(num_tiles_y),
        .current_tile_x(current_tile_x),
        .current_tile_y(current_tile_y),
        .active_buffer(active_buffer),
        .load_done(load_done),
        .stream_done(stream_done),
        .unload_done(unload_done),
        .tile_complete(agu_tile_complete),
        .addr_valid(agu_addr_valid),
        .rd_addr(agu_rd_addr),
        .wr_addr(agu_wr_addr),
        .rd_enable(agu_rd_enable),
        .wr_enable(agu_wr_enable),
        .window_x(agu_window_x),
        .window_y(agu_window_y),
        .window_valid(agu_window_valid),
        .dram_rd_addr(agu_dram_rd_addr),
        .dram_wr_addr(agu_dram_wr_addr),
        .dram_rd_req(agu_dram_rd_req),
        .dram_wr_req(agu_dram_wr_req)
    );
    
    // Connect AGU addresses to SRAM
    assign sram_rd_addr = agu_rd_addr;
    assign sram_wr_addr = agu_wr_addr;
    
    // State machine for data movement
    localparam IDLE = 3'b000;
    localparam LOADING = 3'b001;
    localparam STREAMING = 3'b010;
    localparam UNLOADING = 3'b011;
    localparam BUFFER_SWITCH = 3'b100;
    
    reg [2:0] state;
    reg [7:0] load_counter;
    reg [7:0] stream_counter;
    reg [3:0] array_row_counter;
    
    // DRAM interface control
    reg dram_read_active;
    reg dram_write_active;
    reg [15:0] dram_transfer_length;
    reg [15:0] dram_transfer_count;
    
    // DRAM width conversion (if DRAM_WIDTH != DATA_WIDTH)
    localparam BYTES_PER_DRAM = DRAM_WIDTH / 8;
    localparam BYTES_PER_DATA = DATA_WIDTH / 8;
    
    reg [DRAM_WIDTH-1:0] dram_rx_buffer;
    reg [2:0] rx_byte_index;
    reg dram_rx_buffer_valid;
    
    // Extract bytes from DRAM word
    wire [DATA_WIDTH-1:0] extracted_data = dram_rx_buffer[DATA_WIDTH-1:0];
    
    // DRAM ready when not full and actively loading
    assign dram_rx_ready = dram_read_active && sram_wr_ready && !sram_wr_buffer_full;
    
    // DRAM TX (for unloading)
    reg [PSUM_WIDTH-1:0] tx_buffer;
    reg tx_buffer_valid;
    assign dram_tx_data = tx_buffer[DRAM_WIDTH-1:0];
    assign dram_tx_valid = tx_buffer_valid && dram_write_active;
    
    assign sram_start = start;
    assign sram_buffer_switch = (state == BUFFER_SWITCH);
    
    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            active_buffer <= 1'b0;
            buffer_ready <= 1'b0;
            sram_wr_valid <= 1'b0;
            sram_wr_data <= {DATA_WIDTH{1'b0}};
            sram_rd_ready <= 1'b0;
            pixel_out <= {(ARRAY_SIZE*DATA_WIDTH){1'b0}};
            pixel_valid <= 1'b0;
            load_counter <= 8'h0;
            stream_counter <= 8'h0;
            array_row_counter <= 4'h0;
            dram_read_active <= 1'b0;
            dram_write_active <= 1'b0;
            dram_transfer_length <= 16'h0;
            dram_transfer_count <= 16'h0;
            dram_rx_buffer <= {DRAM_WIDTH{1'b0}};
            rx_byte_index <= 3'h0;
            dram_rx_buffer_valid <= 1'b0;
            tx_buffer <= {PSUM_WIDTH{1'b0}};
            tx_buffer_valid <= 1'b0;
        end else begin
            // Default: clear single-cycle signals
            pixel_valid <= 1'b0;
            
            case (state)
                IDLE: begin
                    buffer_ready <= 1'b0;
                    sram_wr_valid <= 1'b0;
                    sram_rd_ready <= 1'b0;
                    dram_read_active <= 1'b0;
                    dram_write_active <= 1'b0;
                    
                    if (start && sram_ready) begin
                        buffer_ready <= 1'b1;
                    end
                    
                    if (go_load) begin
                        // Start loading data from DRAM to SRAM
                        state <= LOADING;
                        load_counter <= 8'h0;
                        dram_read_active <= 1'b1;
                        // Calculate transfer length based on tile size
                        dram_transfer_length <= (ARRAY_SIZE + kernel_size - 1) * 
                                               (ARRAY_SIZE + kernel_size - 1);
                        dram_transfer_count <= 16'h0;
                    end else if (go_stream) begin
                        // Start streaming to systolic array
                        state <= STREAMING;
                        stream_counter <= 8'h0;
                        array_row_counter <= 4'h0;
                        sram_rd_ready <= 1'b1;
                    end else if (go_unload) begin
                        // Start unloading results
                        state <= UNLOADING;
                        dram_write_active <= 1'b1;
                        dram_transfer_length <= ARRAY_SIZE * ARRAY_SIZE;
                        dram_transfer_count <= 16'h0;
                    end
                end
                
                LOADING: begin
                    // Transfer data from DRAM to SRAM via AGU addresses
                    
                    // DRAM → internal buffer
                    if (dram_rx_valid && dram_rx_ready) begin
                        dram_rx_buffer <= dram_rx_data;
                        dram_rx_buffer_valid <= 1'b1;
                        rx_byte_index <= 3'h0;
                    end
                    
                    // Internal buffer → SRAM
                    if (dram_rx_buffer_valid && sram_wr_ready && agu_wr_enable) begin
                        sram_wr_valid <= 1'b1;
                        sram_wr_data <= extracted_data;
                        
                        // Shift buffer if DRAM is wider than data
                        if (DRAM_WIDTH > DATA_WIDTH) begin
                            dram_rx_buffer <= dram_rx_buffer >> DATA_WIDTH;
                            rx_byte_index <= rx_byte_index + 1'b1;
                            
                            if (rx_byte_index >= (DRAM_WIDTH/DATA_WIDTH - 1)) begin
                                dram_rx_buffer_valid <= 1'b0;
                            end
                        end else begin
                            dram_rx_buffer_valid <= 1'b0;
                        end
                        
                        load_counter <= load_counter + 1'b1;
                        dram_transfer_count <= dram_transfer_count + 1'b1;
                    end else begin
                        sram_wr_valid <= 1'b0;
                    end
                    
                    // Check completion
                    if (load_done) begin
                        state <= IDLE;
                        dram_read_active <= 1'b0;
                        sram_wr_valid <= 1'b0;
                    end
                end
                
                STREAMING: begin
                    // Stream data from SRAM to Systolic Array
                    // Read addresses come from AGU sliding window generation
                    
                    if (agu_window_valid && agu_rd_enable) begin
                        sram_rd_ready <= 1'b1;
                        
                        // Wait for SRAM read latency, then capture data
                        if (sram_rd_valid) begin
                            // Pack data for systolic array row
                            // Each cycle, we feed ARRAY_SIZE pixels to one row
                            pixel_out[array_row_counter*DATA_WIDTH +: DATA_WIDTH] <= sram_rd_data;
                            
                            if (array_row_counter == ARRAY_SIZE - 1) begin
                                // Complete row assembled
                                pixel_valid <= 1'b1;
                                array_row_counter <= 4'h0;
                                stream_counter <= stream_counter + 1'b1;
                            end else begin
                                array_row_counter <= array_row_counter + 1'b1;
                            end
                        end
                    end
                    
                    if (stream_done) begin
                        state <= BUFFER_SWITCH;
                        sram_rd_ready <= 1'b0;
                    end
                end
                
                UNLOADING: begin
                    // Capture results from systolic array and write to DRAM
                    
                    if (psum_valid && agu_wr_enable) begin
                        // Write to SRAM first
                        sram_wr_valid <= 1'b1;
                        sram_wr_data <= psum_in[DATA_WIDTH-1:0];  // Take lower bits
                        
                        // Prepare for DRAM transfer
                        tx_buffer <= psum_in[PSUM_WIDTH-1:0];
                        tx_buffer_valid <= 1'b1;
                    end else begin
                        sram_wr_valid <= 1'b0;
                    end
                    
                    // DRAM write
                    if (dram_tx_valid && dram_tx_ready) begin
                        tx_buffer_valid <= 1'b0;
                        dram_transfer_count <= dram_transfer_count + 1'b1;
                    end
                    
                    if (unload_done) begin
                        state <= BUFFER_SWITCH;
                        dram_write_active <= 1'b0;
                        sram_wr_valid <= 1'b0;
                    end
                end
                
                BUFFER_SWITCH: begin
                    // Switch ping-pong buffers
                    active_buffer <= ~active_buffer;
                    state <= IDLE;
                    buffer_ready <= 1'b1;
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
        if (state == LOADING && sram_wr_valid && sram_wr_ready)
            $display("[DataLoader] Loading: addr=0x%h, data=0x%h", sram_wr_addr, sram_wr_data);
        
        if (state == STREAMING && pixel_valid)
            $display("[DataLoader] Streaming: cycle=%0d, row=%0d", stream_counter, array_row_counter);
        
        if (state == UNLOADING && sram_wr_valid)
            $display("[DataLoader] Unloading: addr=0x%h, data=0x%h", sram_wr_addr, sram_wr_data);
        
        if (state == BUFFER_SWITCH)
            $display("[DataLoader] Buffer switch - now using %s", active_buffer ? "Pong" : "Ping");
    end
    `endif

endmodule