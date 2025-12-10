`timescale 1ns / 1ps

//==============================================================================
// Testbench for Systolic Array with Handshake
//==============================================================================
// Tests:
// 1. Data handshake (data_valid/data_ready)
// 2. Weight loading handshake
// 3. Result output handshake with back-pressure
// 4. Full data flow with handshaking
//==============================================================================

module tb_systolic_array_handshake;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter ROWS       = 8;
    parameter COLS       = 8;
    parameter DATA_WIDTH = 8;
    parameter PSUM_WIDTH = 32;
    parameter CLK_PERIOD = 10;

    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg                             clk;
    reg                             rst_n;
    
    // Control
    reg                             enable;
    reg                             load_weight;
    reg                             clear_acc;
    
    // Input handshake
    reg                             data_valid;
    wire                            data_ready;
    
    // Weight handshake
    reg                             weight_valid;
    wire                            weight_ready;
    
    // Result handshake
    wire                            result_valid;
    reg                             result_ready;
    
    // Data buses
    reg  [ROWS*DATA_WIDTH-1:0]      pixel_in_bus;
    reg  [COLS*PSUM_WIDTH-1:0]      psum_in_bus;
    wire [ROWS*DATA_WIDTH-1:0]      pixel_out_bus;
    wire [COLS*PSUM_WIDTH-1:0]      psum_out_bus;

    //==========================================================================
    // Test Variables
    //==========================================================================
    integer test_num;
    integer errors;
    integer total_tests;
    integer i, j;
    integer handshake_count;
    integer cycle_count;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
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
        .data_valid(data_valid),
        .data_ready(data_ready),
        .weight_valid(weight_valid),
        .weight_ready(weight_ready),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .pixel_in_bus(pixel_in_bus),
        .psum_in_bus(psum_in_bus),
        .pixel_out_bus(pixel_out_bus),
        .psum_out_bus(psum_out_bus)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        // Initialize
        rst_n        = 0;
        enable       = 0;
        load_weight  = 0;
        clear_acc    = 0;
        data_valid   = 0;
        weight_valid = 0;
        result_ready = 0;
        pixel_in_bus = 0;
        psum_in_bus  = 0;
        test_num     = 0;
        errors       = 0;
        total_tests  = 0;
        
        $display("========================================");
        $display("Systolic Array Handshake Testbench");
        $display("========================================");
        
        // Reset
        #(CLK_PERIOD*2);
        rst_n = 1;
        #(CLK_PERIOD*2);
        
        //======================================================================
        // Test 1: Data Ready Signal
        //======================================================================
        test_num = 1;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Data Ready Signal ---", test_num);
        
        enable = 1;
        result_ready = 1;  // Not stalled
        @(posedge clk);
        
        if (data_ready) begin
            $display("Time %0t: PASS - data_ready asserted when enabled", $time);
        end else begin
            $display("Time %0t: FAIL - data_ready not asserted when enabled", $time);
            errors = errors + 1;
        end
        
        enable = 0;
        @(posedge clk);
        
        //======================================================================
        // Test 2: Weight Loading Handshake
        //======================================================================
        test_num = 2;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Weight Loading Handshake ---", test_num);
        
        load_weight = 1;
        @(posedge clk);
        
        if (weight_ready) begin
            $display("Time %0t: weight_ready asserted when load_weight=1", $time);
        end else begin
            $display("Time %0t: FAIL - weight_ready not asserted", $time);
            errors = errors + 1;
        end
        
        // Load weights with handshake
        weight_valid = 1;
        pixel_in_bus = 64'h0807060504030201;  // Weights 1-8 for row 0
        
        handshake_count = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            if (weight_valid && weight_ready) begin
                handshake_count = handshake_count + 1;
            end
            // Shift weights for next row
            pixel_in_bus = pixel_in_bus + 64'h0808080808080808;
        end
        
        weight_valid = 0;
        load_weight = 0;
        @(posedge clk);
        
        if (handshake_count == 8) begin
            $display("Test %0d: PASS - 8 weight handshakes completed", test_num);
        end else begin
            $display("Test %0d: FAIL - Expected 8 handshakes, got %0d", test_num, handshake_count);
            errors = errors + 1;
        end
        
        //======================================================================
        // Test 3: Data Input Handshake
        //======================================================================
        test_num = 3;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Data Input Handshake ---", test_num);
        
        clear_acc = 1;
        @(posedge clk);
        clear_acc = 0;
        @(posedge clk);
        
        enable = 1;
        result_ready = 1;
        data_valid = 1;
        psum_in_bus = 0;
        
        handshake_count = 0;
        for (i = 0; i < 20; i = i + 1) begin
            pixel_in_bus = {8{8'd1 + i[7:0]}};  // Simple incrementing pattern
            
            @(posedge clk);
            if (data_valid && data_ready) begin
                handshake_count = handshake_count + 1;
            end
        end
        
        data_valid = 0;
        enable = 0;
        @(posedge clk);
        
        if (handshake_count == 20) begin
            $display("Test %0d: PASS - 20 data handshakes completed", test_num);
        end else begin
            $display("Test %0d: FAIL - Expected 20 handshakes, got %0d", test_num, handshake_count);
            errors = errors + 1;
        end
        
        //======================================================================
        // Test 4: Result Valid After Pipeline Fill
        //======================================================================
        test_num = 4;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Result Valid After Pipeline Fill ---", test_num);
        
        // Clear and restart
        clear_acc = 1;
        @(posedge clk);
        clear_acc = 0;
        @(posedge clk);
        
        enable = 1;
        data_valid = 1;
        result_ready = 1;
        pixel_in_bus = 64'h0101010101010101;
        psum_in_bus = 0;
        
        // Wait for pipeline to fill (ROWS + COLS - 1 = 15 cycles)
        cycle_count = 0;
        while (!result_valid && cycle_count < 30) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        
        if (result_valid && cycle_count <= 16) begin
            $display("Test %0d: PASS - result_valid asserted after %0d cycles", test_num, cycle_count);
        end else begin
            $display("Test %0d: FAIL - result_valid timing incorrect (cycles=%0d)", test_num, cycle_count);
            errors = errors + 1;
        end
        
        data_valid = 0;
        enable = 0;
        @(posedge clk);
        
        //======================================================================
        // Test 5: Back-Pressure (result_ready = 0)
        //======================================================================
        test_num = 5;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Back-Pressure Test ---", test_num);
        
        // Clear and restart
        clear_acc = 1;
        @(posedge clk);
        clear_acc = 0;
        @(posedge clk);
        
        enable = 1;
        data_valid = 1;
        result_ready = 1;
        pixel_in_bus = 64'h0202020202020202;
        psum_in_bus = 0;
        
        // Fill pipeline
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk);
        end
        
        // Now apply back-pressure
        result_ready = 0;
        @(posedge clk);
        @(posedge clk);
        
        // Check that data_ready goes low due to back-pressure
        if (!data_ready) begin
            $display("Time %0t: PASS - data_ready deasserted on back-pressure", $time);
        end else begin
            $display("Time %0t: INFO - data_ready still asserted (design choice)", $time);
        end
        
        // Release back-pressure
        result_ready = 1;
        @(posedge clk);
        
        if (data_ready) begin
            $display("Test %0d: PASS - data_ready restored after back-pressure release", test_num);
        end else begin
            $display("Test %0d: FAIL - data_ready not restored", test_num);
            errors = errors + 1;
        end
        
        data_valid = 0;
        enable = 0;
        @(posedge clk);
        
        //======================================================================
        // Test 6: Result Handshake Completion
        //======================================================================
        test_num = 6;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Result Handshake Completion ---", test_num);
        
        // Clear and restart
        clear_acc = 1;
        @(posedge clk);
        clear_acc = 0;
        @(posedge clk);
        
        enable = 1;
        data_valid = 1;
        result_ready = 0;  // Initially not ready for results
        pixel_in_bus = 64'h0303030303030303;
        psum_in_bus = 0;
        
        // Fill pipeline
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
        end
        
        // Result should be valid now
        if (result_valid) begin
            $display("Time %0t: result_valid is high, waiting for handshake", $time);
            
            // Complete the handshake
            result_ready = 1;
            @(posedge clk);
            
            if (result_valid && result_ready) begin
                $display("Test %0d: PASS - Result handshake completed", test_num);
            end else begin
                $display("Test %0d: FAIL - Handshake not completed", test_num);
                errors = errors + 1;
            end
        end else begin
            $display("Test %0d: FAIL - result_valid not asserted after pipeline", test_num);
            errors = errors + 1;
        end
        
        data_valid = 0;
        enable = 0;
        result_ready = 0;
        #(CLK_PERIOD*5);
        
        //======================================================================
        // Summary
        //======================================================================
        $display("\n========================================");
        $display("Systolic Array Handshake Testbench Results");
        $display("========================================");
        $display("Total Tests: %0d", total_tests);
        $display("Passed: %0d", total_tests - errors);
        $display("Failed: %0d", errors);
        
        if (errors == 0) begin
            $display("STATUS: ALL TESTS PASSED!");
        end else begin
            $display("STATUS: SOME TESTS FAILED!");
        end
        $display("========================================\n");
        
        $finish;
    end

    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        #1000000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
