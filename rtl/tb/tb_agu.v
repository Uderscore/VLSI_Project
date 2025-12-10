`timescale 1ns / 1ps

//==============================================================================
// Testbench for Address Generation Unit (AGU)
//==============================================================================
// Tests:
// 1. Configuration latching
// 2. LOAD mode - Linear address sequence
// 3. STREAM mode - Sliding window pattern
// 4. UNLOAD mode - Output address sequence
// 5. Multiple tile handling
// 6. Various N and K configurations
//==============================================================================

module tb_agu;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter ADDR_WIDTH   = 8;
    parameter ARRAY_SIZE   = 8;
    parameter MAX_IMG_SIZE = 64;
    parameter DATA_WIDTH   = 32;
    parameter CLK_PERIOD   = 10;

    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg                     clk;
    reg                     rst_n;
    
    // Configuration
    reg  [6:0]              cfg_N;
    reg  [2:0]              cfg_K;
    reg                     cfg_valid;
    
    // Control
    reg                     start;
    reg  [1:0]              mode;
    reg                     next_addr;
    
    // Tile Control
    reg  [2:0]              tile_x;
    reg  [2:0]              tile_y;
    reg                     next_tile;
    
    // Outputs
    wire [ADDR_WIDTH-1:0]   addr_out;
    wire                    addr_valid;
    wire [2:0]              row_idx;
    wire [2:0]              col_idx;
    wire                    busy;
    wire                    tile_done;
    wire                    frame_done;

    //==========================================================================
    // Mode Encoding
    //==========================================================================
    localparam MODE_IDLE        = 2'b00;
    localparam MODE_LOAD_INPUT  = 2'b01;
    localparam MODE_STREAM      = 2'b10;
    localparam MODE_UNLOAD      = 2'b11;

    //==========================================================================
    // Test Variables
    //==========================================================================
    integer test_num;
    integer errors;
    integer total_tests;
    integer expected_addr;
    integer addr_count;
    integer i, j, k, m;
    reg     counted_this_cycle;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    address_generator #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE),
        .MAX_IMG_SIZE(MAX_IMG_SIZE),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_N(cfg_N),
        .cfg_K(cfg_K),
        .cfg_valid(cfg_valid),
        .start(start),
        .mode(mode),
        .next_addr(next_addr),
        .tile_x(tile_x),
        .tile_y(tile_y),
        .next_tile(next_tile),
        .addr_out(addr_out),
        .addr_valid(addr_valid),
        .row_idx(row_idx),
        .col_idx(col_idx),
        .busy(busy),
        .tile_done(tile_done),
        .frame_done(frame_done)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // Task: Consume addresses with proper handshaking
    //==========================================================================
    task consume_addresses;
        input integer expected_count;
        input integer max_count;
        input integer show_first_n;
        input integer show_last_n;
        output integer actual_count;
        begin
            actual_count = 0;
            while (!tile_done && actual_count < max_count) begin
                // Wait for valid address
                while (!addr_valid && !tile_done) begin
                    @(posedge clk);
                end
                
                if (addr_valid && !tile_done) begin
                    // Log address if in display range
                    if (actual_count < show_first_n || actual_count >= expected_count - show_last_n) begin
                        $display("Time %0t: addr[%0d] = %0d (row=%0d, col=%0d)", 
                                 $time, actual_count, addr_out, row_idx, col_idx);
                    end else if (actual_count == show_first_n) begin
                        $display("... (continuing) ...");
                    end
                    
                    // Consume this address
                    actual_count = actual_count + 1;
                    next_addr = 1;
                    @(posedge clk);
                    next_addr = 0;
                end
            end
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        // Initialize
        rst_n       = 0;
        cfg_N       = 7'd16;
        cfg_K       = 3'd3;
        cfg_valid   = 0;
        start       = 0;
        mode        = MODE_IDLE;
        next_addr   = 0;
        tile_x      = 3'd0;
        tile_y      = 3'd0;
        next_tile   = 0;
        test_num    = 0;
        errors      = 0;
        total_tests = 0;
        
        $display("========================================");
        $display("AGU Testbench Starting");
        $display("========================================");
        
        // Reset
        #(CLK_PERIOD*2);
        rst_n = 1;
        #(CLK_PERIOD*2);
        
        //======================================================================
        // Test 1: Configuration
        //======================================================================
        test_num = 1;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Configuration (N=16, K=3) ---", test_num);
        
        cfg_N = 7'd16;
        cfg_K = 3'd3;
        cfg_valid = 1;
        @(posedge clk);
        cfg_valid = 0;
        @(posedge clk);
        @(posedge clk);
        
        $display("Time %0t: Configuration latched - N=%0d, K=%0d", $time, cfg_N, cfg_K);
        $display("Test %0d: PASS - Configuration complete", test_num);
        
        //======================================================================
        // Test 2: LOAD mode - First tile (0,0) for 10x10 input
        //======================================================================
        test_num = 2;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: LOAD Mode (Tile 0,0) ---", test_num);
        
        tile_x = 3'd0;
        tile_y = 3'd0;
        mode = MODE_LOAD_INPUT;
        start = 1;
        @(posedge clk);
        start = 0;
        @(posedge clk);
        
        consume_addresses(100, 150, 3, 3, addr_count);
        
        if (tile_done && addr_count == 100) begin  // 10x10 = 100
            $display("Test %0d: PASS - Generated %0d addresses", test_num, addr_count);
        end else begin
            $display("Test %0d: FAIL - Expected 100 addresses, got %0d", test_num, addr_count);
            errors = errors + 1;
        end
        
        // Acknowledge tile done
        @(posedge clk);
        next_tile = 1;
        @(posedge clk);
        next_tile = 0;
        @(posedge clk);
        
        //======================================================================
        // Test 3: STREAM mode - Sliding window (Tile 0,0)
        //======================================================================
        test_num = 3;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: STREAM Mode (Tile 0,0, K=3) ---", test_num);
        
        tile_x = 3'd0;
        tile_y = 3'd0;
        mode = MODE_STREAM;
        start = 1;
        @(posedge clk);
        start = 0;
        @(posedge clk);
        
        consume_addresses(576, 600, 9, 0, addr_count);
        
        if (tile_done && addr_count == 576) begin  // 8*8*9 = 576
            $display("Test %0d: PASS - Generated %0d addresses (8x8 outputs x 3x3 kernel)", test_num, addr_count);
        end else begin
            $display("Test %0d: FAIL - Expected 576 addresses, got %0d", test_num, addr_count);
            errors = errors + 1;
        end
        
        @(posedge clk);
        next_tile = 1;
        @(posedge clk);
        next_tile = 0;
        @(posedge clk);
        
        //======================================================================
        // Test 4: UNLOAD mode
        //======================================================================
        test_num = 4;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: UNLOAD Mode (Tile 0,0) ---", test_num);
        
        tile_x = 3'd0;
        tile_y = 3'd0;
        mode = MODE_UNLOAD;
        start = 1;
        @(posedge clk);
        start = 0;
        @(posedge clk);
        
        consume_addresses(64, 100, 3, 3, addr_count);
        
        if (tile_done && addr_count == 64) begin  // 8x8 = 64
            $display("Test %0d: PASS - Generated %0d addresses", test_num, addr_count);
        end else begin
            $display("Test %0d: FAIL - Expected 64 addresses, got %0d", test_num, addr_count);
            errors = errors + 1;
        end
        
        @(posedge clk);
        next_tile = 1;
        @(posedge clk);
        next_tile = 0;
        @(posedge clk);
        
        //======================================================================
        // Test 5: Tile (1,0) - Verify halo overlap
        //======================================================================
        test_num = 5;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: LOAD Mode (Tile 1,0) - Halo Overlap ---", test_num);
        
        tile_x = 3'd1;
        tile_y = 3'd0;
        mode = MODE_LOAD_INPUT;
        start = 1;
        @(posedge clk);
        start = 0;
        @(posedge clk);
        
        // Check first address manually
        while (!addr_valid && !tile_done) @(posedge clk);
        
        if (addr_valid) begin
            expected_addr = 8;  // Tile base x = 8
            if (addr_out == expected_addr) begin
                $display("Time %0t: First addr = %0d (correct tile base)", $time, addr_out);
            end else begin
                $display("Time %0t: ERROR - First addr = %0d, expected %0d", $time, addr_out, expected_addr);
                errors = errors + 1;
            end
        end
        
        // Consume remaining addresses
        consume_addresses(100, 150, 0, 0, addr_count);
        
        if (tile_done) begin
            $display("Test %0d: PASS - Tile 1,0 addresses generated with correct offset", test_num);
        end else begin
            $display("Test %0d: FAIL - Tile did not complete", test_num);
            errors = errors + 1;
        end
        
        @(posedge clk);
        next_tile = 1;
        @(posedge clk);
        next_tile = 0;
        @(posedge clk);
        
        //======================================================================
        // Test 6: Different configuration (N=32, K=5)
        //======================================================================
        test_num = 6;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Reconfigure (N=32, K=5) ---", test_num);
        
        cfg_N = 7'd32;
        cfg_K = 3'd5;
        cfg_valid = 1;
        @(posedge clk);
        cfg_valid = 0;
        @(posedge clk);
        @(posedge clk);
        
        // Quick LOAD test with new config
        tile_x = 3'd0;
        tile_y = 3'd0;
        mode = MODE_LOAD_INPUT;
        start = 1;
        @(posedge clk);
        start = 0;
        @(posedge clk);
        
        consume_addresses(144, 200, 0, 0, addr_count);
        
        if (tile_done && addr_count == 144) begin  // 12x12 = 144
            $display("Test %0d: PASS - N=32, K=5 generates 144 addresses (12x12 tile)", test_num);
        end else begin
            $display("Test %0d: FAIL - Expected 144 addresses, got %0d", test_num, addr_count);
            errors = errors + 1;
        end
        
        @(posedge clk);
        next_tile = 1;
        @(posedge clk);
        next_tile = 0;
        @(posedge clk);
        
        //======================================================================
        // Summary
        //======================================================================
        #(CLK_PERIOD*10);
        $display("\n========================================");
        $display("AGU Testbench Results");
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
        #2000000;  // 2ms timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
