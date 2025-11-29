module processing_element (
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,
    
    // Control Signals
    input  wire        enable,
    input  wire        load_weight,
    input  wire        clear_acc,
    
    // Data Inputs
    input  wire [7:0]  pixel_in,      // From West neighbor
    input  wire [7:0]  weight_in,     // For loading weight
    input  wire [31:0] psum_in,       // From North neighbor
    
    // Data Outputs
    output reg  [7:0]  pixel_out,     // To East neighbor
    output reg  [31:0] psum_out       // To South neighbor
);

    // Internal Registers
    reg [7:0]  weight_reg;             // Weight Stationary register
    reg [31:0] accumulator;            // Accumulation register
    
    // Combinational signals
    wire [15:0] product;
    wire [31:0] new_psum;
    
    // Multiply: 8-bit × 8-bit = 16-bit
    assign product = pixel_in * weight_reg;
    
    // Add to partial sum: 16-bit + 32-bit = 32-bit
    
    assign new_psum = psum_in + {{16{1'b0}}, product};  // Zero-extend product
    
    // Sequential Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers
            weight_reg   <= 8'd0;
            accumulator  <= 32'd0;
            pixel_out    <= 8'd0;
            psum_out     <= 32'd0;
            
        end else begin
            
            // Always forward pixel (creates pipeline)
            pixel_out <= pixel_in;
            
            // Weight Loading
            if (load_weight) begin
                weight_reg <= weight_in;
            end
            
            // Clear Accumulator
            if (clear_acc) begin
                accumulator <= 32'd0;
                psum_out    <= 32'd0;
            end
            
            // Compute MAC
            else if (enable) begin
                psum_out <= new_psum;
            end
            
        end
    end

endmodule