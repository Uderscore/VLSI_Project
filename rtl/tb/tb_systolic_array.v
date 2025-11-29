`timescale 1ns / 1ps

module tb_systolic_array;

    // Parameters
    parameter ROWS = 8;
    parameter COLS = 8;
    parameter DATA_WIDTH = 8;
    parameter PSUM_WIDTH = 32;
    parameter CLK_PERIOD = 10;

    // Signals
    reg clk;
    reg rst_n;
    reg enable;
    reg load_weight;
    reg clear_acc;
    
    reg [ROWS*DATA_WIDTH-1:0] pixel_in_bus;
    reg [COLS*PSUM_WIDTH-1:0] psum_in_bus;
    
    wire [ROWS*DATA_WIDTH-1:0] pixel_out_bus;
    wire [COLS*PSUM_WIDTH-1:0] psum_out_bus;

    // DUT Instantiation
    systolic_array #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .load_weight(load_weight),
        .clear_acc(clear_acc),
        .pixel_in_bus(pixel_in_bus),
        .psum_in_bus(psum_in_bus),
        .pixel_out_bus(pixel_out_bus),
        .psum_out_bus(psum_out_bus)
    );

    // Clock Generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // Helper task to drive pixels for a cycle
    task drive_pixels;
        input [ROWS*DATA_WIDTH-1:0] pixels;
        begin
            pixel_in_bus = pixels;
        end
    endtask

    // Helper task to drive psums for a cycle
    task drive_psums;
        input [COLS*PSUM_WIDTH-1:0] psums;
        begin
            psum_in_bus = psums;
        end
    endtask

    // Integer for loops
    integer i, j;

    // Test Sequence
    initial begin
        // Initialize Inputs
        rst_n = 0;
        enable = 0;
        load_weight = 0;
        clear_acc = 0;
        pixel_in_bus = 0;
        psum_in_bus = 0;

        // Reset
        #(CLK_PERIOD*2);
        rst_n = 1;
        #(CLK_PERIOD);

        // -------------------------------------------------------
        // Test Case 1: Weight Loading
        // -------------------------------------------------------
        $display("Starting Weight Loading Test...");
        
        // We want to load an Identity Matrix (or similar pattern)
        // Row 0 gets 1, Row 1 gets 2, etc. in the diagonal?
        // Let's load all 1s for simplicity first, or a specific pattern.
        // To load weights, we shift them in from the West.
        // Column 7 is loaded first, then Col 6, ..., Col 0.
        
        // Let's load a pattern where Weight(r, c) = r + c
        // Sequence:
        // Cycle 1: Input for Col 7
        // Cycle 2: Input for Col 6
        // ...
        // Cycle 8: Input for Col 0
        
        load_weight = 0; // Don't latch yet, just shift
        
        for (j = COLS-1; j >= 0; j = j - 1) begin
            // Construct the input vector for this cycle
            // pixel_in_bus slices: [Row 7 ... Row 0]
            for (i = 0; i < ROWS; i = i + 1) begin
                // Using blocking assignment for the reg array slice simulation
                // pixel_in_bus[(i+1)*8-1 : i*8] = i + j; 
                // Verilog doesn't support variable part select on LHS easily in loop without generated block or temp var
                // So we construct the full vector.
            end
            
            // Manual construction for 8x8
            // We want pixel_in_bus to have (0+j) at bottom, (7+j) at top
            // But wait, weight loading happens when we assert load_weight?
            // The PE logic says: if (load_weight) weight_reg <= weight_in;
            // weight_in is connected to pixel_in.
            // So we must have the correct weights sitting at the pixel_in port of EVERY PE
            // at the moment we assert load_weight.
            // This means we need to SHIFT the weights in first.
            // But the PE only passes pixel_in to pixel_out.
            // So we shift for 8 cycles.
            
            // Drive inputs for Col j
            // For simplicity, let's set all rows to value 'j+1'
            // So Col 7 will have all 8s, Col 0 will have all 1s.
            pixel_in_bus = {
                8'd8, 8'd8, 8'd8, 8'd8, 8'd8, 8'd8, 8'd8, 8'd8
            };
            if (j == 7) pixel_in_bus = {64{8'd8}};
            if (j == 6) pixel_in_bus = {64{8'd7}};
            if (j == 5) pixel_in_bus = {64{8'd6}};
            if (j == 4) pixel_in_bus = {64{8'd5}};
            if (j == 3) pixel_in_bus = {64{8'd4}};
            if (j == 2) pixel_in_bus = {64{8'd3}};
            if (j == 1) pixel_in_bus = {64{8'd2}};
            if (j == 0) pixel_in_bus = {64{8'd1}};
            
            // Assert load_weight during the last cycle (j=0)
            // so that at the next edge, the values are latched into weight_reg
            // instead of just shifting.
            if (j == 0) load_weight = 1;
            
            #(CLK_PERIOD);
        end
        
        load_weight = 0;
        
        $display("Weights Loaded.");
        
        // -------------------------------------------------------
        // Test Case 2: Computation (All 1s inputs)
        // -------------------------------------------------------
        $display("Starting Computation Test...");
        
        // Clear Accumulator
        clear_acc = 1;
        #(CLK_PERIOD);
        clear_acc = 0;
        
        // Enable Computation
        enable = 1;
        
        // Stream in Pixels = 1 for all rows
        // We expect:
        // PE(r, c) weight = c + 1
        // Input = 1
        // Product = 1 * (c+1) = c+1
        // PSUM out should accumulate these.
        
        // We need to account for the skew if we want valid results at the bottom.
        // But for a basic connectivity test, we can just blast 1s and see them propagate.
        
        // Drive 1s for 20 cycles
        pixel_in_bus = {64{8'd1}};
        psum_in_bus = 0; // No partial sums from top
        
        // Wait for pipeline to fill and produce results
        // Latency = ROWS (8) + maybe some overhead?
        // Let's wait 15 cycles and check.
        repeat(15) #(CLK_PERIOD);
        
        // Check Results
        $display("Checking Results...");
        for (j = 0; j < COLS; j = j + 1) begin
            // Extract the 32-bit psum for Col j
            // psum_out_bus is [COLS*32-1 : 0]
            // Col 0 is at [31:0]
            // Col j is at [(j+1)*32-1 : j*32]
            
            // Expected value: 8 * (j + 1)
            // Col 0 (Weight 1) -> 8
            // Col 7 (Weight 8) -> 64
            
            if (psum_out_bus[(j+1)*32-1 -: 32] !== (8 * (j + 1))) begin
                $display("ERROR: Col %0d Failed. Expected %0d, Got %0d", j, 8*(j+1), psum_out_bus[(j+1)*32-1 -: 32]);
            end else begin
                $display("PASS: Col %0d Correct. Value = %0d", j, psum_out_bus[(j+1)*32-1 -: 32]);
            end
        end
        
        enable = 0;
        
        $display("Test Complete.");
        $finish;
    end
    
    // Monitor
    initial begin
        $dumpfile("systolic_array_tb.vcd");
        $dumpvars(0, tb_systolic_array);
    end

endmodule
