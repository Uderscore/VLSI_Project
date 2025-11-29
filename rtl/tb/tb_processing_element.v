`timescale 1ns/1ps

module tb_processing_element;

    // Clock and Reset
    reg        clk;
    reg        rst_n;
    
    // Control Signals
    reg        enable;
    reg        load_weight;
    reg        clear_acc;
    
    // Data Inputs
    reg  [7:0]  pixel_in;
    reg  [7:0]  weight_in;
    reg  [31:0] psum_in;
    
    // Data Outputs
    wire [7:0]  pixel_out;
    wire [31:0] psum_out;
    
    // Instantiate PE
    processing_element uut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .load_weight(load_weight),
        .clear_acc(clear_acc),
        .pixel_in(pixel_in),
        .weight_in(weight_in),
        .psum_in(psum_in),
        .pixel_out(pixel_out),
        .psum_out(psum_out)
    );
    
    // Clock Generation: 10ns period (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test Procedure
    initial begin
        // Initialize signals
        rst_n = 0;
        enable = 0;
        load_weight = 0;
        clear_acc = 0;
        pixel_in = 0;
        weight_in = 0;
        psum_in = 0;
        
        // Dump waveform
        $dumpfile("pe_test.vcd");
        $dumpvars(0, tb_processing_element);
        
        // Apply Reset
        #20;
        rst_n = 1;
        #10;
        
        //===================================
        // TEST 1: Load Weight
        //===================================
        $display("TEST 1: Loading Weight = 5");
        weight_in = 8'd5;
        load_weight = 1;
        #10;
        load_weight = 0;
        #10;
        
        if (uut.weight_reg == 8'd5)
            $display("✓ PASS: Weight loaded correctly");
        else
            $display("✗ FAIL: Weight = %d, expected 5", uut.weight_reg);
        
        //===================================
        // TEST 2: Single MAC Operation
        //===================================
        $display("\nTEST 2: MAC with pixel=3, weight=5, psum_in=0");
        pixel_in = 8'd3;
        psum_in = 32'd0;
        enable = 1;
        #10;
        
        // Expected: 3 × 5 + 0 = 15
        if (psum_out == 32'd15)
            $display("✓ PASS: psum_out = %d", psum_out);
        else
            $display("✗ FAIL: psum_out = %d, expected 15", psum_out);
            
        // Check pixel forwarding
        if (pixel_out == 8'd3)
            $display("✓ PASS: Pixel forwarded correctly");
        else
            $display("✗ FAIL: pixel_out = %d, expected 3", pixel_out);
        
        //===================================
        // TEST 3: Accumulation
        //===================================
        $display("\nTEST 3: Accumulation over multiple cycles");
        pixel_in = 8'd2;
        psum_in = 32'd15;  // Previous result
        #10;
        
        // Expected: 2 × 5 + 15 = 25
        if (psum_out == 32'd25)
            $display("✓ PASS: Accumulated psum_out = %d", psum_out);
        else
            $display("✗ FAIL: psum_out = %d, expected 25", psum_out);
        
        //===================================
        // TEST 4: Stream of Operations
        //===================================
        $display("\nTEST 4: Processing stream [4, 6, 1, 8]");
        psum_in = 32'd0;
        
        // Cycle 1: 4 × 5 = 20
        pixel_in = 8'd4;
        #10;
        $display("  Cycle 1: psum_out = %d (expected 20)", psum_out);
        
        // Cycle 2: 6 × 5 = 30, total = 50
        pixel_in = 8'd6;
        psum_in = psum_out;
        #10;
        $display("  Cycle 2: psum_out = %d (expected 50)", psum_out);
        
        // Cycle 3: 1 × 5 = 5, total = 55
        pixel_in = 8'd1;
        psum_in = psum_out;
        #10;
        $display("  Cycle 3: psum_out = %d (expected 55)", psum_out);
        
        // Cycle 4: 8 × 5 = 40, total = 95
        pixel_in = 8'd8;
        psum_in = psum_out;
        #10;
        $display("  Cycle 4: psum_out = %d (expected 95)", psum_out);
        
        //===================================
        // TEST 5: Clear Accumulator
        //===================================
        $display("\nTEST 5: Clear Accumulator");
        clear_acc = 1;
        #10;
        clear_acc = 0;
        
        if (psum_out == 32'd0)
            $display("✓ PASS: Accumulator cleared");
        else
            $display("✗ FAIL: psum_out = %d after clear", psum_out);
        
        //===================================
        // TEST 6: Maximum Values
        //===================================
        $display("\nTEST 6: Maximum value handling");
        load_weight = 1;
        weight_in = 8'd255;
        #10;
        load_weight = 0;
        
        pixel_in = 8'd255;
        psum_in = 32'd0;
        enable = 1;
        #10;
        
        // Expected: 255 × 255 = 65025
        if (psum_out == 32'd65025)
            $display("✓ PASS: Max multiplication = %d", psum_out);
        else
            $display("✗ FAIL: psum_out = %d, expected 65025", psum_out);
        
        //===================================
        // TEST 7: Overflow Check
        //===================================
        $display("\nTEST 7: Large accumulation (64 max values)");
        clear_acc = 1;
        #10;
        clear_acc = 0;
        psum_in = 32'd0;
        #10;  // Wait one cycle for clear to take effect

        repeat(64) begin
            pixel_in = 8'd255;
            #10;
            psum_in = psum_out;  // Update for next iteration
        end
        
        // Expected: 64 × (255 × 255) = 4,161,600
        $display("  Final accumulated value: %d", psum_out);
        $display("  Expected: 4,161,600");
        
        if (psum_out == 32'd4161600)
            $display("✓ PASS: Large accumulation correct");
        else
            $display("⚠ WARNING: Check if 32-bit is sufficient");
        
        //===================================
        // End Simulation
        //===================================
        $display("\n=== PE Testbench Complete ===");
        $finish;
    end
    
    // Monitor changes
    initial begin
        $monitor("Time=%0t | pixel_in=%d weight=%d psum_in=%d | pixel_out=%d psum_out=%d", 
                 $time, pixel_in, uut.weight_reg, psum_in, pixel_out, psum_out);
    end

endmodule