module systolic_array #(
    parameter ROWS = 8,
    parameter COLS = 8,
    parameter DATA_WIDTH = 8,
    parameter PSUM_WIDTH = 32
)(
    input  wire                                clk,
    input  wire                                rst_n,
    
    //==========================================================================
    // Global Control
    //==========================================================================
    input  wire                                enable,
    input  wire                                load_weight,
    input  wire                                clear_acc,
    
    //==========================================================================
    // Handshake Interface - Input Data (from Memory Controller)
    //==========================================================================
    input  wire                                data_valid,     // Memory has valid input data
    output wire                                data_ready,     // SA ready to accept data
    
    //==========================================================================
    // Handshake Interface - Weight Loading
    //==========================================================================
    input  wire                                weight_valid,   // Memory has valid weight data
    output wire                                weight_ready,   // SA ready to accept weights
    
    //==========================================================================
    // Handshake Interface - Output Results (to Memory Controller)
    //==========================================================================
    output reg                                 result_valid,   // SA has valid output results
    input  wire                                result_ready,   // Memory ready to accept results
    
    //==========================================================================
    // Array Inputs
    //==========================================================================
    // Flattened buses: [Row 0, Row 1, ... Row 7]
    input  wire [ROWS*DATA_WIDTH-1:0]          pixel_in_bus,
    // Flattened buses: [Col 0, Col 1, ... Col 7]
    input  wire [COLS*PSUM_WIDTH-1:0]          psum_in_bus,
    
    //==========================================================================
    // Array Outputs
    //==========================================================================
    output wire [ROWS*DATA_WIDTH-1:0]          pixel_out_bus,
    output wire [COLS*PSUM_WIDTH-1:0]          psum_out_bus
);

    //==========================================================================
    // Internal Signals
    //==========================================================================
    // Registered input data for handshake
    reg  [ROWS*DATA_WIDTH-1:0]  pixel_in_reg;
    reg  [COLS*PSUM_WIDTH-1:0]  psum_in_reg;
    reg                         input_valid_reg;
    
    // Internal enable signals
    wire                        internal_enable;
    wire                        internal_load_weight;
    
    // Pipeline delay counter for result valid
    reg  [4:0]                  pipeline_count;
    reg                         processing_active;
    
    // Internal connections
    // Wires to connect PEs horizontally (pixel path)
    wire [DATA_WIDTH-1:0] pixel_conn [ROWS-1:0][COLS:0];
    
    // Wires to connect PEs vertically (psum path)
    wire [PSUM_WIDTH-1:0] psum_conn [ROWS:0][COLS-1:0];

    //==========================================================================
    // Handshake Logic
    //==========================================================================
    // Data ready: SA can accept new data when enabled and not stalled
    assign data_ready = enable && (!result_valid || result_ready);
    
    // Weight ready: SA can accept weights when in load_weight mode
    assign weight_ready = load_weight;
    
    // Internal enable: only process when handshake complete
    assign internal_enable = enable && (data_valid && data_ready);
    assign internal_load_weight = load_weight && (weight_valid && weight_ready);

    //==========================================================================
    // Input Registration with Handshake
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pixel_in_reg    <= {(ROWS*DATA_WIDTH){1'b0}};
            psum_in_reg     <= {(COLS*PSUM_WIDTH){1'b0}};
            input_valid_reg <= 1'b0;
        end else begin
            // Latch input data on valid handshake
            if (data_valid && data_ready) begin
                pixel_in_reg    <= pixel_in_bus;
                psum_in_reg     <= psum_in_bus;
                input_valid_reg <= 1'b1;
            end else if (internal_enable) begin
                input_valid_reg <= 1'b0;
            end
        end
    end

    //==========================================================================
    // Result Valid Generation
    //==========================================================================
    // Track when results are available (after pipeline delay)
    // For 8x8 array, results propagate after ROWS+COLS-1 = 15 cycles
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipeline_count    <= 5'd0;
            processing_active <= 1'b0;
            result_valid      <= 1'b0;
        end else begin
            if (clear_acc) begin
                // Clear resets the pipeline
                pipeline_count    <= 5'd0;
                processing_active <= 1'b0;
                result_valid      <= 1'b0;
            end else if (internal_enable) begin
                // Start or continue pipeline count
                processing_active <= 1'b1;
                if (pipeline_count < ROWS + COLS - 1) begin
                    pipeline_count <= pipeline_count + 1'b1;
                end
            end
            
            // Result valid after full pipeline fill
            if (processing_active && pipeline_count >= ROWS + COLS - 1) begin
                result_valid <= 1'b1;
            end
            
            // Clear result_valid when result is consumed
            if (result_valid && result_ready) begin
                result_valid <= 1'b0;
                // If still processing, result will become valid again next cycle
            end
        end
    end

    //==========================================================================
    // PE Array Connections
    //==========================================================================
    genvar r, c;
    generate
        // 1. Assign Inputs to the first column of connections (West side)
        for (r = 0; r < ROWS; r = r + 1) begin : gen_input_pixels
            assign pixel_conn[r][0] = pixel_in_bus[(r+1)*DATA_WIDTH-1 : r*DATA_WIDTH];
        end

        // 2. Assign Inputs to the first row of connections (North side)
        for (c = 0; c < COLS; c = c + 1) begin : gen_input_psums
            assign psum_conn[0][c] = psum_in_bus[(c+1)*PSUM_WIDTH-1 : c*PSUM_WIDTH];
        end

        // 3. Instantiate the Grid of PEs
        for (r = 0; r < ROWS; r = r + 1) begin : gen_rows
            for (c = 0; c < COLS; c = c + 1) begin : gen_cols
                
                processing_element pe_inst (
                    .clk         (clk),
                    .rst_n       (rst_n),
                    .enable      (internal_enable),
                    .load_weight (internal_load_weight),
                    .clear_acc   (clear_acc),
                    
                    // Pixel flows West -> East
                    .pixel_in    (pixel_conn[r][c]),
                    .pixel_out   (pixel_conn[r][c+1]),
                    
                    // Weight loading reuses pixel path
                    .weight_in   (pixel_conn[r][c]), 
                    
                    // Partial Sum flows North -> South
                    .psum_in     (psum_conn[r][c]),
                    .psum_out    (psum_conn[r+1][c])
                );
                
            end
        end

        // 4. Assign Outputs from the last column (East side)
        for (r = 0; r < ROWS; r = r + 1) begin : gen_output_pixels
            assign pixel_out_bus[(r+1)*DATA_WIDTH-1 : r*DATA_WIDTH] = pixel_conn[r][COLS];
        end

        // 5. Assign Outputs from the last row (South side)
        for (c = 0; c < COLS; c = c + 1) begin : gen_output_psums
            assign psum_out_bus[(c+1)*PSUM_WIDTH-1 : c*PSUM_WIDTH] = psum_conn[ROWS][c];
        end

    endgenerate

    //==========================================================================
    // Debug Output (Simulation Only)
    //==========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (data_valid && data_ready) begin
            $display("Time %0t: SA Data Handshake - input data latched", $time);
        end
        if (weight_valid && weight_ready) begin
            $display("Time %0t: SA Weight Handshake - weights loaded", $time);
        end
        if (result_valid && result_ready) begin
            $display("Time %0t: SA Result Handshake - results transferred", $time);
        end
    end
    `endif

endmodule
