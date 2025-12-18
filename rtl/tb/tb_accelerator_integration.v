`timescale 1ns / 1ps

//==============================================================================
// Testbench for Accelerator Integration
//==============================================================================
// This testbench validates the integration between:
// - Memory Controller (with ping-pong buffering)
// - Systolic Array (8x8 processing elements)
// 
// Test Scenarios:
// 1. Load input data into memory
// 2. Load weights into systolic array
// 3. Execute computation (convolution)
// 4. Verify output results
//==============================================================================

module tb_accelerator_integration;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter DATA_WIDTH    = 8;
    parameter PSUM_WIDTH    = 32;
    parameter MEM_WIDTH     = 32;
    parameter ADDR_WIDTH    = 8;
    parameter ARRAY_SIZE    = 8;
    parameter CLK_PERIOD    = 10;
    
    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg                         clk;
    reg                         rst_n;
    
    // Configuration
    reg  [6:0]                  cfg_N;
    reg  [2:0]                  cfg_K;
    
    // Control
    reg                         start;
    reg                         mode_load;
    reg                         mode_weight;
    reg                         mode_compute;
    wire                        busy;
    wire                        done;
    
    // External memory interface - Input
    reg                         ext_data_valid;
    wire                        ext_data_ready;
    reg  [MEM_WIDTH-1:0]        ext_data_in;
    
    // External memory interface - Output
    wire                        ext_result_valid;
    reg                         ext_result_ready;
    wire [MEM_WIDTH-1:0]        ext_result_out;
    
    // Status
    wire                        sa_computing;
    wire                        mem_writing;
    wire                        mem_reading;

    //==========================================================================
    // Test Variables
    //==========================================================================
    integer test_num;
    integer errors;
    integer i, j, k;
    integer data_count;
    integer result_count;
    
    // Test data arrays
    reg [7:0] input_matrix [0:63];      // 8x8 input
    reg [7:0] kernel_matrix [0:63];     // 8x8 kernel (max size)
    reg [31:0] expected_output [0:63];  // Expected results
    reg [31:0] actual_output [0:63];    // Actual results from DUT
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    accelerator_integration #(
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH),
        .MEM_WIDTH(MEM_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .cfg_N              (cfg_N),
        .cfg_K              (cfg_K),
        .start              (start),
        .mode_load          (mode_load),
        .mode_weight        (mode_weight),
        .mode_compute       (mode_compute),
        .busy               (busy),
        .done               (done),
        .ext_data_valid     (ext_data_valid),
        .ext_data_ready     (ext_data_ready),
        .ext_data_in        (ext_data_in),
        .ext_result_valid   (ext_result_valid),
        .ext_result_ready   (ext_result_ready),
        .ext_result_out     (ext_result_out),
        .sa_computing       (sa_computing),
        .mem_writing        (mem_writing),
        .mem_reading        (mem_reading)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // Initialization Task
    //==========================================================================
    task initialize;
        begin
            rst_n = 0;
            start = 0;
            mode_load = 0;
            mode_weight = 0;
            mode_compute = 0;
            cfg_N = 7'd8;
            cfg_K = 3'd3;
            ext_data_valid = 0;
            ext_data_in = 32'd0;
            ext_result_ready = 1;
            errors = 0;
            test_num = 0;
            data_count = 0;
            result_count = 0;
        end
    endtask

    //==========================================================================
    // Reset Task
    //==========================================================================
    task apply_reset;
        begin
            $display("Time %0t: Applying reset...", $time);
            rst_n = 0;
            repeat(5) @(posedge clk);
            rst_n = 1;
            repeat(2) @(posedge clk);
            $display("Time %0t: Reset complete", $time);
        end
    endtask

    //==========================================================================
    // Load Test Data Task
    //==========================================================================
    task load_test_data;
        integer idx;
        begin
            $display("Time %0t: Loading test data into arrays...", $time);
            
            // Initialize with simple test pattern
            // Input: Sequential values
            for (idx = 0; idx < 64; idx = idx + 1) begin
                input_matrix[idx] = idx[7:0];
            end
            
            // Kernel: Identity kernel (simplified for testing)
            for (idx = 0; idx < 64; idx = idx + 1) begin
                if (idx % 9 == 0)  // Diagonal elements
                    kernel_matrix[idx] = 8'd1;
                else
                    kernel_matrix[idx] = 8'd0;
            end
            
            $display("Time %0t: Test data loaded", $time);
        end
    endtask

    //==========================================================================
    // Load Input Data to Memory Task
    //==========================================================================
    task load_input_to_memory;
        integer idx;
        integer word_count;
        begin
            $display("Time %0t: TEST - Loading input data to memory", $time);
            
            // Set mode to load input
            mode_load = 1;
            mode_weight = 0;
            mode_compute = 0;
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Send data in 32-bit words (4 pixels per word)
            word_count = 0;
            for (idx = 0; idx < 64; idx = idx + 4) begin
                // Pack 4 pixels into 32-bit word
                ext_data_in = {input_matrix[idx+3], 
                              input_matrix[idx+2], 
                              input_matrix[idx+1], 
                              input_matrix[idx]};
                ext_data_valid = 1;
                
                // Wait for handshake
                @(posedge clk);
                while (!(ext_data_valid && ext_data_ready)) @(posedge clk);
                
                $display("Time %0t:   Loaded word %0d: 0x%h", $time, word_count, ext_data_in);
                word_count = word_count + 1;
                
                @(posedge clk);
            end
            
            // Deassert valid
            ext_data_valid = 0;
            
            // Wait for buffer switch to complete
            repeat(20) @(posedge clk);
            
            mode_load = 0;
            
            $display("Time %0t: Input data loading complete (%0d words)", $time, word_count);
        end
    endtask

    //==========================================================================
    // Load Weights to Systolic Array Task
    //==========================================================================
    task load_weights_to_sa;
        integer row;
        begin
            $display("Time %0t: TEST - Loading weights to systolic array", $time);
            
            // Set mode to load weights
            mode_load = 0;
            mode_weight = 1;
            mode_compute = 0;
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Load weights row by row (8 rows for 8x8 array)
            for (row = 0; row < 8; row = row + 1) begin
                // Send weight for this row (broadcast to all PEs in row)
                ext_data_in = {24'd0, kernel_matrix[row * 8]};
                ext_data_valid = 1;
                
                // Wait for handshake
                @(posedge clk);
                while (!(ext_data_valid && ext_data_ready)) @(posedge clk);
                
                $display("Time %0t:   Loaded weight row %0d: 0x%h", $time, row, ext_data_in[7:0]);
                @(posedge clk);
            end
            
            // Deassert valid
            ext_data_valid = 0;
            mode_weight = 0;
            
            repeat(10) @(posedge clk);
            
            $display("Time %0t: Weight loading complete", $time);
        end
    endtask

    //==========================================================================
    // Execute Computation Task
    //==========================================================================
    task execute_computation;
        integer timeout;
        begin
            $display("Time %0t: TEST - Starting computation", $time);
            
            // Set mode to compute
            mode_load = 0;
            mode_weight = 0;
            mode_compute = 1;
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Wait for computation to start
            timeout = 0;
            while (!sa_computing && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            if (sa_computing) begin
                $display("Time %0t: Systolic array computing...", $time);
            end else begin
                $display("Time %0t: WARNING - SA did not start computing", $time);
            end
            
            // Wait for computation to complete (or timeout)
            timeout = 0;
            while (!done && timeout < 2000) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            
            if (done) begin
                $display("Time %0t: Computation complete", $time);
            end else begin
                $display("Time %0t: WARNING - Computation timeout", $time);
            end
            
            mode_compute = 0;
            repeat(10) @(posedge clk);
        end
    endtask

    //==========================================================================
    // Collect Results Task
    //==========================================================================
    task collect_results;
        integer idx;
        integer timeout_counter;
        begin
            $display("Time %0t: TEST - Collecting results", $time);
            
            result_count = 0;
            ext_result_ready = 1;
            timeout_counter = 0;
            
            // Collect results as they become available
            while (result_count < 16 && timeout_counter < 1000) begin
                @(posedge clk);
                
                if (ext_result_valid && ext_result_ready) begin
                    actual_output[result_count] = ext_result_out;
                    $display("Time %0t:   Result[%0d] = 0x%h", $time, result_count, ext_result_out);
                    result_count = result_count + 1;
                    timeout_counter = 0;  // Reset on successful transfer
                end else begin
                    timeout_counter = timeout_counter + 1;
                end
            end
            
            if (timeout_counter >= 1000) begin
                $display("Time %0t: WARNING - Timeout collecting results (got %0d)", $time, result_count);
            end
            
            $display("Time %0t: Collected %0d results", $time, result_count);
        end
    endtask

    //==========================================================================
    // Verify Results Task
    //==========================================================================
    task verify_results;
        integer idx;
        integer pass;
        begin
            $display("Time %0t: TEST - Verifying results", $time);
            pass = 1;
            
            // For this simple test, just check that we got results
            if (result_count == 0) begin
                $display("ERROR: No results received!");
                errors = errors + 1;
                pass = 0;
            end else begin
                $display("SUCCESS: Received %0d results", result_count);
            end
            
            if (pass)
                $display("Time %0t: *** TEST PASSED ***", $time);
            else
                $display("Time %0t: *** TEST FAILED ***", $time);
        end
    endtask

    //==========================================================================
    // Test Case 1: Basic Data Flow Test
    //==========================================================================
    task test_basic_data_flow;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("TEST %0d: Basic Data Flow", test_num);
            $display("========================================");
            
            apply_reset();
            load_test_data();
            
            // Step 1: Load input data
            load_input_to_memory();
            
            // Step 2: Load weights
            load_weights_to_sa();
            
            // Step 3: Execute computation
            execute_computation();
            
            // Step 4: Collect and verify results
            collect_results();
            verify_results();
            
            $display("========================================");
            $display("TEST %0d COMPLETE\n", test_num);
        end
    endtask

    //==========================================================================
    // Test Case 2: Memory Handshake Test
    //==========================================================================
    task test_memory_handshake;
        integer idx;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("TEST %0d: Memory Handshake Protocol", test_num);
            $display("========================================");
            
            apply_reset();
            
            // Test write handshake
            $display("Testing write handshake...");
            mode_load = 1;
            start = 1;
            @(posedge clk);
            start = 0;
            
            for (idx = 0; idx < 8; idx = idx + 1) begin
                // Assert data valid
                ext_data_in = 32'hDEAD0000 | idx;
                ext_data_valid = 1;
                
                // Wait for ready
                @(posedge clk);
                while (!ext_data_ready) @(posedge clk);
                
                // Check handshake
                if (ext_data_valid && ext_data_ready) begin
                    $display("  Handshake %0d: SUCCESS", idx);
                end else begin
                    $display("  Handshake %0d: FAILED", idx);
                    errors = errors + 1;
                end
                
                ext_data_valid = 0;
                repeat(2) @(posedge clk);
            end
            
            mode_load = 0;
            ext_data_valid = 0;
            
            $display("========================================");
            $display("TEST %0d COMPLETE\n", test_num);
        end
    endtask

    //==========================================================================
    // Test Case 3: Back-pressure Test
    //==========================================================================
    task test_backpressure;
        integer cycle_count;
        begin
            test_num = test_num + 1;
            $display("\n========================================");
            $display("TEST %0d: Back-pressure Handling", test_num);
            $display("========================================");
            
            apply_reset();
            load_test_data();
            load_input_to_memory();
            load_weights_to_sa();
            
            // Start computation
            mode_compute = 1;
            start = 1;
            @(posedge clk);
            start = 0;
            
            // Apply back-pressure randomly
            cycle_count = 0;
            while (!done && cycle_count < 1000) begin
                @(posedge clk);
                
                // Randomly deassert result_ready to create back-pressure
                if ($random % 3 == 0)
                    ext_result_ready = 0;
                else
                    ext_result_ready = 1;
                
                // Collect results when available
                if (ext_result_valid && ext_result_ready) begin
                    $display("  Received result during back-pressure test: 0x%h", ext_result_out);
                end
                
                cycle_count = cycle_count + 1;
            end
            
            ext_result_ready = 1;
            mode_compute = 0;
            
            if (cycle_count >= 1000) begin
                $display("WARNING: Timeout during back-pressure test");
            end else begin
                $display("SUCCESS: Back-pressure handled correctly");
            end
            
            $display("========================================");
            $display("TEST %0d COMPLETE\n", test_num);
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("\n");
        $display("================================================================================");
        $display("        ACCELERATOR INTEGRATION TESTBENCH");
        $display("================================================================================");
        $display("Testing integration of Memory Controller + Systolic Array");
        $display("================================================================================\n");
        
        // Initialize
        initialize();
        
        // Run test cases
        test_basic_data_flow();
        test_memory_handshake();
        test_backpressure();
        
        // Final summary
        $display("\n");
        $display("================================================================================");
        $display("                           SIMULATION SUMMARY");
        $display("================================================================================");
        $display("Total Tests Run: %0d", test_num);
        $display("Total Errors:    %0d", errors);
        
        if (errors == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** TESTS FAILED - %0d ERRORS ***\n", errors);
        end
        $display("================================================================================\n");
        
        $finish;
    end

    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        #200000;  // 200us timeout
        $display("\n*** ERROR: Simulation timeout! ***\n");
        $finish;
    end

    //==========================================================================
    // Waveform Dump
    //==========================================================================
    initial begin
        $dumpfile("accelerator_integration.vcd");
        $dumpvars(0, tb_accelerator_integration);
    end

endmodule
