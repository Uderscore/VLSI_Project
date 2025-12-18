`timescale 1ns / 1ps

//==============================================================================
// Testbench for Control Unit (Main FSM)
//==============================================================================
// Tests:
// 1. Reset behavior
// 2. Configuration latching
// 3. State transitions: IDLE -> CONFIG -> LOAD -> COMPUTE -> DRAIN -> DONE
// 4. Host handshake protocol
// 5. AGU triggering with correct modes
// 6. Multi-tile processing flow
//==============================================================================

module tb_control_unit;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter CLK_PERIOD = 10;  // 100 MHz clock
    
    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg         clk;
    reg         rst_n;
    
    // Host interface
    reg  [6:0]  cfg_N;
    reg  [2:0]  cfg_K;
    reg         host_start;
    reg         host_data_valid;
    reg         host_ready;
    wire        host_ack;
    wire        busy;
    wire        done;
    
    // Configuration output
    wire [6:0]  cfg_N_latched;
    wire [2:0]  cfg_K_latched;
    wire        cfg_valid;
    
    // AGU control
    wire        agu_start;
    wire [1:0]  agu_mode;
    wire [2:0]  agu_tile_x;
    wire [2:0]  agu_tile_y;
    wire        agu_next_tile;
    reg         agu_busy;
    reg         agu_tile_done;
    reg         agu_frame_done;
    
    // Data loader
    wire        loader_is_loading;
    
    // Systolic array
    wire        sa_enable;
    wire        sa_load_weight;
    wire        sa_clear_acc;
    
    // Memory controller
    wire        mem_start;
    wire        mem_buffer_switch;
    
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
    integer i;
    reg     agu_start_seen;  // Flag to capture if agu_start was ever pulsed

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    control_unit #(
        .ADDR_WIDTH(8),
        .ARRAY_SIZE(8),
        .MAX_IMG_SIZE(64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        
        // Host interface
        .cfg_N(cfg_N),
        .cfg_K(cfg_K),
        .host_start(host_start),
        .host_data_valid(host_data_valid),
        .host_ready(host_ready),
        .host_ack(host_ack),
        .busy(busy),
        .done(done),
        
        // Configuration output
        .cfg_N_latched(cfg_N_latched),
        .cfg_K_latched(cfg_K_latched),
        .cfg_valid(cfg_valid),
        
        // AGU control
        .agu_start(agu_start),
        .agu_mode(agu_mode),
        .agu_tile_x(agu_tile_x),
        .agu_tile_y(agu_tile_y),
        .agu_next_tile(agu_next_tile),
        .agu_busy(agu_busy),
        .agu_tile_done(agu_tile_done),
        .agu_frame_done(agu_frame_done),
        
        // Data loader
        .loader_is_loading(loader_is_loading),
        
        // Systolic array
        .sa_enable(sa_enable),
        .sa_load_weight(sa_load_weight),
        .sa_clear_acc(sa_clear_acc),
        
        // Memory controller
        .mem_start(mem_start),
        .mem_buffer_switch(mem_buffer_switch)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // Task: Reset DUT
    //==========================================================================
    task reset_dut;
        begin
            rst_n = 0;
            cfg_N = 7'd16;
            cfg_K = 3'd3;
            host_start = 0;
            host_data_valid = 0;
            host_ready = 1;
            agu_busy = 0;
            agu_tile_done = 0;
            agu_frame_done = 0;
            
            #(CLK_PERIOD * 3);
            rst_n = 1;
            #(CLK_PERIOD * 2);
        end
    endtask

    //==========================================================================
    // Task: Simulate AGU tile completion
    //==========================================================================
    task simulate_agu_tile;
        input integer cycles;
        begin
            agu_busy = 1;
            repeat(cycles) @(posedge clk);
            agu_busy = 0;
            agu_tile_done = 1;
            @(posedge clk);
            agu_tile_done = 0;
            @(posedge clk);
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        test_num = 0;
        errors = 0;
        total_tests = 0;
        agu_start_seen = 0;
        
        $display("========================================");
        $display("Control Unit Testbench Starting");
        $display("========================================");
        
        //======================================================================
        // Test 1: Reset Behavior
        //======================================================================
        test_num = 1;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Reset Behavior ---", test_num);
        
        reset_dut();
        
        if (!busy && !done && !agu_start && agu_mode == MODE_IDLE) begin
            $display("Test %0d: PASS - Reset correctly initialized outputs", test_num);
        end else begin
            $display("Test %0d: FAIL - Outputs not properly reset", test_num);
            $display("  busy=%b, done=%b, agu_start=%b, agu_mode=%b", 
                     busy, done, agu_start, agu_mode);
            errors = errors + 1;
        end
        
        //======================================================================
        // Test 2: Configuration Latching
        //======================================================================
        test_num = 2;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Configuration Latching ---", test_num);
        
        cfg_N = 7'd32;
        cfg_K = 3'd5;
        host_start = 1;
        host_data_valid = 1;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);  // Wait for CONFIG state
        
        if (cfg_N_latched == 7'd32 && cfg_K_latched == 3'd5 && cfg_valid) begin
            $display("Test %0d: PASS - Configuration latched (N=%0d, K=%0d)", 
                     test_num, cfg_N_latched, cfg_K_latched);
        end else begin
            $display("Test %0d: FAIL - Configuration not latched correctly", test_num);
            $display("  cfg_N_latched=%0d (expected 32), cfg_K_latched=%0d (expected 5)", 
                     cfg_N_latched, cfg_K_latched);
            errors = errors + 1;
        end
        
        //======================================================================
        // Test 3: State Transition to LOAD and Test 4: AGU Start Signal
        // Combined because agu_start is a one-cycle pulse
        //======================================================================
        test_num = 3;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: State Transition to LOAD ---", test_num);
        
        // Wait for LOAD state and capture agu_start pulse
        agu_start_seen = 0;
        repeat(5) begin
            @(posedge clk);
            if (agu_start) agu_start_seen = 1;
        end
        
        if (busy && agu_mode == MODE_LOAD_INPUT && loader_is_loading) begin
            $display("Test %0d: PASS - Entered LOAD state with correct AGU mode", test_num);
        end else begin
            $display("Test %0d: FAIL - Did not enter LOAD state correctly", test_num);
            $display("  busy=%b, agu_mode=%b, loader_is_loading=%b", 
                     busy, agu_mode, loader_is_loading);
            errors = errors + 1;
        end
        
        //======================================================================
        // Test 4: AGU Start Signal (captured during LOAD entry)
        //======================================================================
        test_num = 4;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: AGU Start Signal ---", test_num);
        
        if (agu_start_seen) begin
            $display("Test %0d: PASS - AGU start signal was pulsed", test_num);
        end else begin
            $display("Test %0d: FAIL - AGU start not asserted", test_num);
            errors = errors + 1;
        end
        
        //======================================================================
        // Test 5: LOAD to COMPUTE Transition (Single Tile)
        //======================================================================
        test_num = 5;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: LOAD to COMPUTE Transition ---", test_num);
        
        // Simulate 4 tiles for 32x32 image (4x4 tiles)
        for (i = 0; i < 16; i = i + 1) begin
            simulate_agu_tile(5);
        end
        
        // Wait for state transition
        @(posedge clk);
        @(posedge clk);
        
        if (agu_mode == MODE_STREAM && sa_enable) begin
            $display("Test %0d: PASS - Transitioned to COMPUTE state", test_num);
        end else begin
            $display("Test %0d: FAIL - Did not transition to COMPUTE", test_num);
            $display("  agu_mode=%b, sa_enable=%b", agu_mode, sa_enable);
            errors = errors + 1;
        end
        
        //======================================================================
        // Test 6: COMPUTE to DRAIN Transition
        //======================================================================
        test_num = 6;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: COMPUTE to DRAIN Transition ---", test_num);
        
        // Simulate compute for all tiles
        for (i = 0; i < 16; i = i + 1) begin
            simulate_agu_tile(5);
        end
        
        @(posedge clk);
        @(posedge clk);
        
        if (agu_mode == MODE_UNLOAD && !sa_enable) begin
            $display("Test %0d: PASS - Transitioned to DRAIN state", test_num);
        end else begin
            $display("Test %0d: FAIL - Did not transition to DRAIN", test_num);
            $display("  agu_mode=%b, sa_enable=%b", agu_mode, sa_enable);
            errors = errors + 1;
        end
        
        //======================================================================
        // Test 7: DRAIN to DONE Transition
        //======================================================================
        test_num = 7;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: DRAIN to DONE Transition ---", test_num);
        
        // Simulate drain for all tiles
        for (i = 0; i < 16; i = i + 1) begin
            simulate_agu_tile(5);
        end
        
        @(posedge clk);
        @(posedge clk);
        
        if (done && !busy) begin
            $display("Test %0d: PASS - Transitioned to DONE state", test_num);
        end else begin
            $display("Test %0d: FAIL - Did not transition to DONE", test_num);
            $display("  done=%b, busy=%b", done, busy);
            errors = errors + 1;
        end
        
        //======================================================================
        // Test 8: Return to IDLE
        //======================================================================
        test_num = 8;
        total_tests = total_tests + 1;
        $display("\n--- Test %0d: Return to IDLE ---", test_num);
        
        host_start = 0;
        host_data_valid = 0;
        
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        
        if (!done && !busy) begin
            $display("Test %0d: PASS - Returned to IDLE state", test_num);
        end else begin
            $display("Test %0d: FAIL - Did not return to IDLE", test_num);
            $display("  done=%b, busy=%b", done, busy);
            errors = errors + 1;
        end
        
        //======================================================================
        // Summary
        //======================================================================
        #(CLK_PERIOD * 10);
        $display("\n========================================");
        $display("Control Unit Testbench Results");
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
        #500000;  // 500us timeout
        $display("ERROR: Simulation timeout!");
        $finish;
    end

    //==========================================================================
    // VCD Dump for Waveform Viewing
    //==========================================================================
    initial begin
        $dumpfile("tb_control_unit.vcd");
        $dumpvars(0, tb_control_unit);
    end

endmodule
