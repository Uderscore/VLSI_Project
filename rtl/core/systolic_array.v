module systolic_array #(
    parameter ROWS = 8,
    parameter COLS = 8,
    parameter DATA_WIDTH = 8,
    parameter PSUM_WIDTH = 32
)(
    input  wire                                clk,
    input  wire                                rst_n,
    
    // Global Control
    input  wire                                enable,
    input  wire                                load_weight,
    input  wire                                clear_acc,
    
    // Array Inputs
    // Flattened buses: [Row 0, Row 1, ... Row 7]
    input  wire [ROWS*DATA_WIDTH-1:0]          pixel_in_bus,
    // Flattened buses: [Col 0, Col 1, ... Col 7]
    input  wire [COLS*PSUM_WIDTH-1:0]          psum_in_bus,
    
    // Array Outputs
    output wire [ROWS*DATA_WIDTH-1:0]          pixel_out_bus,
    output wire [COLS*PSUM_WIDTH-1:0]          psum_out_bus
);

    // Internal connections
    // wires to connect PEs horizontally (pixel path)
    // pixel_conn[r][c] connects PE(r,c) output to PE(r,c+1) input
    // We need COLS+1 vertical wires for each row (including input and output of the array)
    wire [DATA_WIDTH-1:0] pixel_conn [ROWS-1:0][COLS:0];
    
    // wires to connect PEs vertically (psum path)
    // psum_conn[r][c] connects PE(r,c) output to PE(r+1,c) input
    // We need ROWS+1 horizontal wires for each column
    wire [PSUM_WIDTH-1:0] psum_conn [ROWS:0][COLS-1:0];

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
                    .enable      (enable),
                    .load_weight (load_weight),
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

endmodule
