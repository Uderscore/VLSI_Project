//==============================================================================
// Accelerator Integration Module
//==============================================================================
// This module integrates the Memory Controller with the Systolic Array
// creating a complete data processing pipeline for convolution operations.
//
// Components:
// 1. Memory Controller - Manages ping-pong buffered SRAM access
// 2. Systolic Array - 8x8 processing element grid for convolution
// 3. Data path wiring and control logic
//
// Data Flow:
// - Input data flows: External → Memory Controller → Systolic Array
// - Weight data flows: External → Memory Controller → Systolic Array
// - Output data flows: Systolic Array → Memory Controller → External
//==============================================================================

module accelerator_integration #(
    parameter DATA_WIDTH    = 8,      // Input/Weight data width
    parameter PSUM_WIDTH    = 32,     // Partial sum width
    parameter MEM_WIDTH     = 32,     // Memory interface width
    parameter ADDR_WIDTH    = 8,      // SRAM address width
    parameter ARRAY_SIZE    = 8       // Systolic array dimension
)(
    // Global signals
    input  wire                         clk,
    input  wire                         rst_n,
    
    // Configuration
    input  wire [6:0]                   cfg_N,          // Image dimension
    input  wire [2:0]                   cfg_K,          // Kernel dimension
    
    // Control signals
    input  wire                         start,          // Start processing
    input  wire                         mode_load,      // Load input mode
    input  wire                         mode_weight,    // Load weight mode
    input  wire                         mode_compute,   // Compute mode
    output wire                         busy,           // System busy
    output wire                         done,           // Processing complete
    
    // External memory interface - Input Data
    input  wire                         ext_data_valid,
    output wire                         ext_data_ready,
    input  wire [MEM_WIDTH-1:0]         ext_data_in,
    
    // External memory interface - Output Data
    output wire                         ext_result_valid,
    input  wire                         ext_result_ready,
    output wire [MEM_WIDTH-1:0]         ext_result_out,
    
    // Status outputs
    output wire                         sa_computing,   // Systolic array active
    output wire                         mem_writing,    // Memory being written
    output wire                         mem_reading     // Memory being read
);

    //==========================================================================
    // Internal Wiring - Memory Controller Signals
    //==========================================================================
    wire                        mem_start;
    wire                        mem_buffer_switch;
    wire                        mem_ping_active;
    wire                        mem_ready;
    
    // AGU → Memory Write Path
    wire                        agu_wr_valid;
    wire                        agu_wr_ready;
    wire [MEM_WIDTH-1:0]        agu_wr_data;
    wire [ADDR_WIDTH-1:0]       agu_wr_addr;
    wire                        wr_buffer_full;
    
    // Memory → AGU Read Path (currently unused in this simplified integration)
    wire                        agu_rd_data_ready;
    wire                        agu_rd_data_valid;
    wire [ADDR_WIDTH-1:0]       agu_rd_addr;
    wire [MEM_WIDTH-1:0]        agu_rd_data;
    
    // Systolic Array → Memory Write Path
    wire                        sa_wr_valid;
    wire                        sa_wr_ready;
    wire [MEM_WIDTH-1:0]        sa_wr_data;
    wire [ADDR_WIDTH-1:0]       sa_wr_addr;
    
    // Memory → Systolic Array Read Path
    wire                        sa_rd_data_ready;
    wire                        sa_rd_data_valid;
    wire [ADDR_WIDTH-1:0]       sa_rd_addr;
    wire [MEM_WIDTH-1:0]        sa_rd_data;
    wire                        rd_buffer_empty;

    //==========================================================================
    // Internal Wiring - Systolic Array Signals
    //==========================================================================
    wire                        sa_enable;
    wire                        sa_load_weight;
    wire                        sa_clear_acc;
    
    // Input handshake
    wire                        sa_data_valid;
    wire                        sa_data_ready;
    
    // Weight handshake
    wire                        sa_weight_valid;
    wire                        sa_weight_ready;
    
    // Result handshake
    wire                        sa_result_valid;
    wire                        sa_result_ready;
    
    // Data buses
    wire [ARRAY_SIZE*DATA_WIDTH-1:0]  sa_pixel_in_bus;
    wire [ARRAY_SIZE*PSUM_WIDTH-1:0]  sa_psum_in_bus;
    wire [ARRAY_SIZE*DATA_WIDTH-1:0]  sa_pixel_out_bus;
    wire [ARRAY_SIZE*PSUM_WIDTH-1:0]  sa_psum_out_bus;

    //==========================================================================
    // Internal Control Logic
    //==========================================================================
    reg [2:0]  state;
    reg [3:0]  data_counter;        // Track data transfers
    reg [7:0]  pixel_buffer [0:7];  // Buffer for converting 32-bit to 8x8-bit
    reg [2:0]  pixel_buf_idx;
    reg [ADDR_WIDTH-1:0] write_addr_counter;
    reg [ADDR_WIDTH-1:0] read_addr_counter;
    reg                  buffer_switched;   // Track if buffer was switched after load
    
    // State definitions
    localparam IDLE         = 3'd0;
    localparam LOAD_INPUT   = 3'd1;
    localparam LOAD_WEIGHT  = 3'd2;
    localparam COMPUTE      = 3'd3;
    localparam DRAIN        = 3'd4;
    localparam DONE         = 3'd5;

    //==========================================================================
    // Memory Controller Instance
    //==========================================================================
    memory_controller #(
        .DATA_WIDTH(MEM_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE)
    ) mem_ctrl (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (mem_start),
        .buffer_switch      (mem_buffer_switch),
        .ping_active        (mem_ping_active),
        .ready              (mem_ready),
        
        // AGU write interface
        .agu_wr_valid       (agu_wr_valid),
        .agu_wr_ready       (agu_wr_ready),
        .agu_wr_data        (agu_wr_data),
        .agu_wr_addr        (agu_wr_addr),
        .wr_buffer_full     (wr_buffer_full),
        
        // AGU read interface
        .agu_rd_data_ready  (agu_rd_data_ready),
        .agu_rd_data_valid  (agu_rd_data_valid),
        .agu_rd_addr        (agu_rd_addr),
        .agu_rd_data        (agu_rd_data),
        
        // SA write interface
        .sa_wr_valid        (sa_wr_valid),
        .sa_wr_ready        (sa_wr_ready),
        .sa_wr_data         (sa_wr_data),
        .sa_wr_addr         (sa_wr_addr),
        
        // SA read interface
        .sa_rd_data_ready   (sa_rd_data_ready),
        .sa_rd_data_valid   (sa_rd_data_valid),
        .sa_rd_addr         (sa_rd_addr),
        .sa_rd_data         (sa_rd_data),
        .rd_buffer_empty    (rd_buffer_empty)
    );

    //==========================================================================
    // Systolic Array Instance
    //==========================================================================
    systolic_array #(
        .ROWS(ARRAY_SIZE),
        .COLS(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) sa (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (sa_enable),
        .load_weight    (sa_load_weight),
        .clear_acc      (sa_clear_acc),
        
        // Data handshake
        .data_valid     (sa_data_valid),
        .data_ready     (sa_data_ready),
        
        // Weight handshake
        .weight_valid   (sa_weight_valid),
        .weight_ready   (sa_weight_ready),
        
        // Result handshake
        .result_valid   (sa_result_valid),
        .result_ready   (sa_result_ready),
        
        // Data buses
        .pixel_in_bus   (sa_pixel_in_bus),
        .psum_in_bus    (sa_psum_in_bus),
        .pixel_out_bus  (sa_pixel_out_bus),
        .psum_out_bus   (sa_psum_out_bus)
    );

    //==========================================================================
    // Control FSM
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            data_counter <= 4'd0;
            pixel_buf_idx <= 3'd0;
            write_addr_counter <= 8'd0;
            read_addr_counter <= 8'd0;
            buffer_switched <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    data_counter <= 4'd0;
                    pixel_buf_idx <= 3'd0;
                    if (state != LOAD_INPUT) begin
                        write_addr_counter <= 8'd0;
                        buffer_switched <= 1'b0;
                    end
                    read_addr_counter <= 8'd0;
                    
                    if (start && mode_load)
                        state <= LOAD_INPUT;
                    else if (start && mode_weight)
                        state <= LOAD_WEIGHT;
                    else if (start && mode_compute)
                        state <= COMPUTE;
                end
                
                LOAD_INPUT: begin
                    // Loading input data to memory
                    if (agu_wr_valid && agu_wr_ready) begin
                        write_addr_counter <= write_addr_counter + 1;
                    end
                    // After loading all data, switch buffers
                    if (write_addr_counter >= 8'd16 && !buffer_switched) begin
                        buffer_switched <= 1'b1;
                    end
                    if (buffer_switched && write_addr_counter >= 8'd16) begin
                        state <= IDLE;
                    end
                end
                
                LOAD_WEIGHT: begin
                    // Loading weights to systolic array
                    if (sa_weight_valid && sa_weight_ready) begin
                        data_counter <= data_counter + 1;
                        if (data_counter >= 4'd7)
                            state <= IDLE;
                    end
                end
                
                COMPUTE: begin
                    // Reading from memory and feeding to SA
                    if (sa_data_valid && sa_data_ready) begin
                        read_addr_counter <= read_addr_counter + 1;
                        if (read_addr_counter >= 8'd63)
                            state <= DRAIN;
                    end
                end
                
                DRAIN: begin
                    // Wait for results to propagate through SA
                    if (sa_result_valid) begin
                        state <= DONE;
                    end
                end
                
                DONE: begin
                    if (!start)
                        state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end

    //==========================================================================
    // Data Path Wiring - External to Memory
    //==========================================================================
    // External input data goes to AGU write path (to memory)
    assign agu_wr_valid = ext_data_valid && (state == LOAD_INPUT);
    assign agu_wr_data  = ext_data_in;
    assign agu_wr_addr  = write_addr_counter;
    assign ext_data_ready = (state == LOAD_INPUT) ? agu_wr_ready : 
                           (state == LOAD_WEIGHT) ? sa_weight_ready : 1'b0;
    
    //==========================================================================
    // Data Path Wiring - Memory to Systolic Array
    //==========================================================================
    // Read from memory for SA input
    assign sa_rd_data_ready = sa_data_ready && (state == COMPUTE);
    assign sa_rd_addr = read_addr_counter;
    
    // MUX for pixel input bus: weight loading OR memory data
    wire [ARRAY_SIZE*DATA_WIDTH-1:0] sa_pixel_from_mem;
    wire [ARRAY_SIZE*DATA_WIDTH-1:0] sa_pixel_from_ext;
    
    // Convert 32-bit memory data to 8-bit pixel data for SA
    genvar g;
    generate
        for (g = 0; g < ARRAY_SIZE; g = g + 1) begin : gen_pixel_mapping
            assign sa_pixel_from_mem[(g+1)*DATA_WIDTH-1 : g*DATA_WIDTH] = 
                   sa_rd_data[(g % 4 + 1)*DATA_WIDTH - 1 : (g % 4)*DATA_WIDTH];
        end
    endgenerate
    
    // External data broadcast for weight loading
    assign sa_pixel_from_ext = {ARRAY_SIZE{ext_data_in[DATA_WIDTH-1:0]}};
    
    // Select between weight loading and memory data
    assign sa_pixel_in_bus = (state == LOAD_WEIGHT) ? sa_pixel_from_ext : sa_pixel_from_mem;
    
    // Data valid when memory has data and we're computing
    assign sa_data_valid = sa_rd_data_valid && (state == COMPUTE);
    
    // Partial sums start at 0
    assign sa_psum_in_bus = {(ARRAY_SIZE*PSUM_WIDTH){1'b0}};
    
    //==========================================================================
    // Data Path Wiring - Systolic Array to External
    //==========================================================================
    // Convert SA output (partial sums) to external format
    assign ext_result_valid = sa_result_valid && (state == DRAIN || state == DONE);
    assign sa_result_ready = ext_result_ready;
    
    // Pack first 4 psum outputs into 32-bit word (truncate to 8-bit each)
    assign ext_result_out = {
        sa_psum_out_bus[3*PSUM_WIDTH +: 8],
        sa_psum_out_bus[2*PSUM_WIDTH +: 8],
        sa_psum_out_bus[1*PSUM_WIDTH +: 8],
        sa_psum_out_bus[0*PSUM_WIDTH +: 8]
    };
    
    //==========================================================================
    // Weight Loading Path
    //==========================================================================
    // When loading weights, use external data
    assign sa_weight_valid = ext_data_valid && (state == LOAD_WEIGHT);
    assign sa_load_weight = (state == LOAD_WEIGHT);
    
    //==========================================================================
    // Control Signal Assignments
    //==========================================================================
    assign sa_enable = (state == COMPUTE);
    assign sa_clear_acc = (state == IDLE) || (state == LOAD_INPUT);
    
    assign mem_start = start && (mode_load || mode_compute);
    assign mem_buffer_switch = (state == LOAD_INPUT) && buffer_switched && (write_addr_counter >= 8'd16);
    
    //==========================================================================
    // Status Outputs
    //==========================================================================
    assign busy = (state != IDLE) && (state != DONE);
    assign done = (state == DONE);
    assign sa_computing = (state == COMPUTE) || (state == DRAIN);
    assign mem_writing = agu_wr_valid && agu_wr_ready;
    assign mem_reading = sa_rd_data_valid;
    
    //==========================================================================
    // Write back results to memory (for future output stage)
    //==========================================================================
    // Not implemented in this simplified version
    assign sa_wr_valid = 1'b0;
    assign sa_wr_data = 32'd0;
    assign sa_wr_addr = 8'd0;
    
    // AGU read not used in this simplified version
    assign agu_rd_data_ready = 1'b0;
    assign agu_rd_addr = 8'd0;

endmodule
