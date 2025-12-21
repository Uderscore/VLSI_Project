`timescale 1ns / 1ps

//==============================================================================
// Full System Testbench - Following project.txt Requirements
//==============================================================================
// This testbench:
// 1. Generates test input and kernel data
// 2. Computes expected output using software golden model
// 3. Drives AXI-Stream interface (Valid/Ready handshake)
// 4. Compares results with ±1 tolerance as per project.txt
//==============================================================================

module tb_full_system;

    //==========================================================================
    // Parameters
    //==========================================================================
    parameter DATA_WIDTH    = 8;
    parameter PSUM_WIDTH    = 32;
    parameter MEM_WIDTH     = 32;
    parameter ADDR_WIDTH    = 8;
    parameter ARRAY_SIZE    = 8;
    parameter CLK_PERIOD    = 10;   // 100 MHz
    parameter TIMEOUT_CYCLES = 10000000;

    //==========================================================================
    // Clock and Reset
    //==========================================================================
    reg clk;
    reg rst_n;

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // DUT Signals
    //==========================================================================
    reg         start;
    reg  [6:0]  cfg_N;
    reg  [4:0]  cfg_K;  // 5-bit to support K=16
    wire        done;
    wire        busy;
    
    reg  [DATA_WIDTH-1:0] rx_data;
    reg                   rx_valid;
    wire                  rx_ready;
    
    wire [DATA_WIDTH-1:0] tx_data;
    wire                  tx_valid;
    reg                   tx_ready;
    
    wire [3:0]  current_state;
    wire        sa_active;
    wire        loading_data;
    wire        draining_results;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    convolution_accelerator_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH),
        .MEM_WIDTH(MEM_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .start              (start),
        .cfg_N              (cfg_N),
        .cfg_K              (cfg_K),
        .done               (done),
        .busy               (busy),
        .rx_data            (rx_data),
        .rx_valid           (rx_valid),
        .rx_ready           (rx_ready),
        .tx_data            (tx_data),
        .tx_valid           (tx_valid),
        .tx_ready           (tx_ready),
        .current_state      (current_state),
        .sa_active          (sa_active),
        .loading_data       (loading_data),
        .draining_results   (draining_results)
    );

    //==========================================================================
    // Test Data Storage
    //==========================================================================
    reg [7:0] input_data  [0:4095];   // Max 64x64
    reg [7:0] kernel_data [0:255];    // Max 16x16
    reg [31:0] expected_output [0:4095]; // Golden model output (32-bit for accumulation)
    reg [7:0] actual_output [0:4095]; // DUT output
    
    //==========================================================================
    // Test Variables
    //==========================================================================
    integer test_N, test_K, out_size;
    integer total_input, total_kernel, total_output;
    integer i, j, kx, ky, x, y, idx;
    integer acc;
    integer errors, total_tests, pass_count;
    integer sent, received, timeout;
    integer diff;

    //==========================================================================
    // Golden Model: 2D Convolution
    //==========================================================================
    task compute_golden_model;
        input integer N;
        input integer K;
        integer ox, oy, kxx, kyy;
        integer pixel_idx, kernel_idx, out_idx;
        integer sum;
        begin
            out_size = N - K + 1;
            
            for (oy = 0; oy < out_size; oy = oy + 1) begin
                for (ox = 0; ox < out_size; ox = ox + 1) begin
                    sum = 0;
                    for (kyy = 0; kyy < K; kyy = kyy + 1) begin
                        for (kxx = 0; kxx < K; kxx = kxx + 1) begin
                            pixel_idx = (oy + kyy) * N + (ox + kxx);
                            kernel_idx = kyy * K + kxx;
                            sum = sum + input_data[pixel_idx] * kernel_data[kernel_idx];
                        end
                    end
                    out_idx = oy * out_size + ox;
                    expected_output[out_idx] = sum;
                end
            end
        end
    endtask

    //==========================================================================
    // Generate Test Data
    //==========================================================================
    task generate_test_data;
        input integer N;
        input integer K;
        integer ii;
        begin
            // Generate input: Sequential pattern (1 to N*N, wrap at 256)
            for (ii = 0; ii < N*N; ii = ii + 1) begin
                input_data[ii] = ((ii % 251) + 1) & 8'hFF;
            end
            
            // Generate kernel: Simple pattern (alternating 1 and 0)
            for (ii = 0; ii < K*K; ii = ii + 1) begin
                kernel_data[ii] = (ii % 2 == 0) ? 8'd1 : 8'd0;
            end
            
            // Compute golden model
            compute_golden_model(N, K);
        end
    endtask

    //==========================================================================
    // Run Single Test
    //==========================================================================
    //==========================================================================
    // Run Single Test
    //==========================================================================
    //==========================================================================
    // Execute Test Sequence (Data must be pre-loaded)
    //==========================================================================
    task execute_test_sequence;
        input integer N;
        input integer K;
        input string test_name;
        
        integer local_errors;
        integer exp_val, act_val;
        integer f_out;
        string outfile_name;
        
        begin
            test_N = N;
            test_K = K;
            out_size = N - K + 1;
            total_input = N * N;
            total_kernel = K * K;
            total_output = out_size * out_size;
            total_tests = total_tests + 1;
            local_errors = 0;
            
            $display("\n");
            $display("================================================================");
            $display("TEST CASE: %s (Output: %0dx%0d = %0d pixels)", test_name, out_size, out_size, total_output);
            $display("================================================================");
            
            // Data generation/loading removed - assumed pre-loaded

            
            // Reset
            rst_n = 0;
            start = 0;
            rx_valid = 0;
            tx_ready = 1;
            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);
            
            //------------------------------------------------------------------
            // Phase 1: Start and load input data
            //------------------------------------------------------------------
            $display("  Phase 1: Loading %0d input pixels...", total_input);
            
            cfg_N = N[6:0];
            cfg_K = K[4:0];  // 5-bit to support K=16
            start = 1;
            rx_valid = 1;
            rx_data = input_data[0];
            @(posedge clk);
            start = 0;
            
            sent = 0;
            timeout = 0;
            while (sent < total_input && timeout < TIMEOUT_CYCLES) begin
                @(posedge clk);
                if (rx_ready && rx_valid) begin
                    sent = sent + 1;
                    if (sent < total_input) begin
                        rx_data = input_data[sent];
                    end
                    timeout = 0;
                end else begin
                    timeout = timeout + 1;
                end
            end
            
            if (timeout >= TIMEOUT_CYCLES) begin
                $display("  FAIL: Timeout loading input at %0d/%0d", sent, total_input);
                errors = errors + 1;
                disable run_test;
            end
            $display("  Input loaded: %0d pixels", sent);
            
            //------------------------------------------------------------------
            // Phase 2: Load kernel weights
            //------------------------------------------------------------------
            $display("  Phase 2: Loading %0d kernel weights...", total_kernel);
            
            sent = 0;
            rx_data = kernel_data[0];
            timeout = 0;
            
            while (sent < total_kernel && timeout < TIMEOUT_CYCLES) begin
                @(posedge clk);
                if (rx_ready && rx_valid) begin
                    sent = sent + 1;
                    if (sent < total_kernel) begin
                        rx_data = kernel_data[sent];
                    end else begin
                        rx_valid = 0;  // Done loading
                    end
                    timeout = 0;
                end else begin
                    timeout = timeout + 1;
                end
            end
            
            if (timeout >= TIMEOUT_CYCLES) begin
                $display("  FAIL: Timeout loading kernel at %0d/%0d", sent, total_kernel);
                errors = errors + 1;
                disable execute_test_sequence;
            end
            $display("  Kernel loaded: %0d weights", sent);
            
            //------------------------------------------------------------------
            // Phase 3: Wait for computation
            //------------------------------------------------------------------
            $display("  Phase 3: Computing convolution...");
            
            timeout = 0;
            while (!draining_results && !done && timeout < TIMEOUT_CYCLES) begin
                @(posedge clk);
                timeout = timeout + 1;
                if (timeout % 50000 == 0)
                    $display("    ... waiting, state=%0d, cycle=%0d", current_state, timeout);
            end
            
            if (timeout >= TIMEOUT_CYCLES) begin
                $display("  FAIL: Computation timeout");
                errors = errors + 1;
                disable execute_test_sequence;
            end
            $display("  Computation complete in %0d cycles", timeout);
            
            //------------------------------------------------------------------
            // Phase 4: Collect results
            //------------------------------------------------------------------
            $display("  Phase 4: Collecting %0d output pixels...", total_output);
            
            received = 0;
            timeout = 0;
            tx_ready = 1;
            
            while (received < total_output && timeout < TIMEOUT_CYCLES) begin
                @(posedge clk);
                if (tx_valid && tx_ready) begin
                    actual_output[received] = tx_data;
                    received = received + 1;
                    timeout = 0;
                end else begin
                    timeout = timeout + 1;
                end
            end
            
            if (timeout >= TIMEOUT_CYCLES) begin
                $display("  FAIL: Timeout collecting results at %0d/%0d", received, total_output);
                errors = errors + 1;
                disable execute_test_sequence;
            end
            $display("  Results collected: %0d pixels", received);
            
            //------------------------------------------------------------------
            // Phase 4.5: Save actual results to file
            //------------------------------------------------------------------
            $sformat(outfile_name, "sim/testdata/%s_actual.txt", test_name);
                
            f_out = $fopen(outfile_name, "w");
            if (f_out) begin
                $fwrite(f_out, "// Dimensions: %0d x %0d\n", out_size, out_size);
                for (idx = 0; idx < total_output; idx = idx + 1) begin
                    $fwrite(f_out, "%0d\n", actual_output[idx]);
                end
                $fclose(f_out);
                $display("  Saved actual output to %s", outfile_name);
            end else begin
                $display("  ERROR: Could not open file %s for writing", outfile_name);
            end
            
            //------------------------------------------------------------------
            // Phase 5: Verify results with ±1 tolerance
            //------------------------------------------------------------------
            $display("  Phase 5: Verifying results (tolerance: +/-1)...");
            
            for (idx = 0; idx < total_output; idx = idx + 1) begin
                // Truncate expected to 8-bit (saturate at 255)
                if (expected_output[idx] > 255)
                    exp_val = 255;
                else
                    exp_val = expected_output[idx];
                
                act_val = actual_output[idx];
                
                // Check with ±1 tolerance
                if (exp_val > act_val)
                    diff = exp_val - act_val;
                else
                    diff = act_val - exp_val;
                
                if (diff > 1) begin
                    local_errors = local_errors + 1;
                    if (local_errors <= 10) begin
                        $display("    MISMATCH[%0d]: Expected=%0d, Actual=%0d, Diff=%0d",
                                 idx, exp_val, act_val, diff);
                    end
                end
            end
            
            errors = errors + local_errors;
            
            if (local_errors == 0) begin
                $display("  PASS: All %0d results match!", total_output);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: %0d/%0d mismatches", local_errors, total_output);
            end
        end
    endtask

    //==========================================================================
    // Run Standard Test (Internal Generation)
    //Wrapper for backwards compatibility / internal tests
    //==========================================================================
    //==========================================================================
    // Helper Task: Explicit DUT Reset
    //==========================================================================
    task reset_dut;
        begin
            rst_n = 0;
            start = 0;
            rx_valid = 0;
            tx_ready = 1;
            repeat(10) @(posedge clk);
            rst_n = 1;
            repeat(5) @(posedge clk);
        end
    endtask

    task run_test;
        input integer N;
        input integer K;
        string tname;
        
        begin
            generate_test_data(N, K);
            $sformat(tname, "N%0d_K%0d_internal", N, K);
            execute_test_sequence(N, K, tname);
            reset_dut(); // Explicit reset after test
        end
    endtask

    //==========================================================================
    // Run From File (Supports Patterns)
    //==========================================================================
    task run_file_test;
        input integer N;
        input integer K;
        input string pattern; // "random", "zeros", etc.
        string tname;
        string input_file, kernel_file, expect_file;
        
        begin
            if (pattern == "random")
                $sformat(tname, "N%0d_K%0d", N, K);
            else
                $sformat(tname, "N%0d_K%0d_%0s", N, K, pattern);
            
            // Construct filenames
            $sformat(input_file,  "sim/testdata/%s_input.hex", tname);
            $sformat(kernel_file, "sim/testdata/%s_kernel.hex", tname);
            $sformat(expect_file, "sim/testdata/%s_expected_32bit.hex", tname);
            
            // Invoke the generator script via system command
            // Note: In a real environment, you'd call the python script here.
            // For now, we assume the python script has already run or files exist.
            // $system($sformatf("python3 scripts/gen_test_vectors.py --n %0d --k %0d --pattern %s", N, K, pattern));
            
            // Load data from files
            $display("Loading files: %s", input_file);
            $readmemh(input_file, input_data);
            $readmemh(kernel_file, kernel_data);
            $readmemh(expect_file, expected_output);
            
            execute_test_sequence(N, K, tname);
            reset_dut(); // Explicit reset after test
        end
    endtask
    
    task run_custom_test;
        input string tname;
        
        integer cfg_fd;
        integer scan_res;
        integer N, K;
        reg [1023:0] line_buf; 
        string cfg_path;
        string file_path;
        
        begin
            $sformat(cfg_path, "test_cases/%s_config.txt", tname);
            cfg_fd = $fopen(cfg_path, "r");
            if (cfg_fd == 0) begin
                $display("ERROR: Could not open config file: %s", cfg_path);
                errors = errors + 1;
                disable run_custom_test;
            end
            
            // Parse Config File (Simple N=.., K=.. format)
            // Assumes lines like "N=16", "K=3"
            while (!$feof(cfg_fd)) begin
                scan_res = $fgets(line_buf, cfg_fd);
                if (scan_res > 0) begin
                    scan_res = $sscanf(line_buf, "N=%d", N);
                    scan_res = $sscanf(line_buf, "K=%d", K);
                end
            end
            $fclose(cfg_fd);
            
            $display("Loaded Custom Test: %s (N=%0d, K=%0d)", tname, N, K);
            
            // Load Hex Files
            $sformat(file_path, "test_cases/%s_in.hex", tname);
            $readmemh(file_path, input_data);
            
            $sformat(file_path, "test_cases/%s_weight.hex", tname);
            $readmemh(file_path, kernel_data);
            
            $sformat(file_path, "test_cases/%s_gold.hex", tname);
            $readmemh(file_path, expected_output);
            
            execute_test_sequence(N, K, tname);
            reset_dut(); // Explicit reset after test
        end
    endtask

    //==========================================================================
    // Main Test Sequence
    //==========================================================================
    initial begin
        $display("\n");
        $display("================================================================");
        $display("    CONVOLUTION ACCELERATOR - FULL SYSTEM TESTBENCH");
        $display("    Following project.txt Requirements");
        $display("================================================================");
        $display("Array Size: %0dx%0d", ARRAY_SIZE, ARRAY_SIZE);
        $display("Data Width: %0d-bit input, %0d-bit accumulator", DATA_WIDTH, PSUM_WIDTH);
        $display("================================================================\n");
        
        // Initialize
        errors = 0;
        total_tests = 0;
        pass_count = 0;
        rst_n = 0;
        start = 0;
        rx_valid = 0;
        rx_data = 0;
        tx_ready = 1;
        
        // Run test cases from project.txt specification
        // Min: N=16, K=2
        // Max: N=64, K=16
        
        // Internal Tests (Alternating Pattern)
        run_test(16, 3);
        run_test(16, 5);
        run_test(32, 3);
        
        // External Random Tests (from files)
        run_file_test(16, 3, "random"); 
        run_file_test(16, 5, "random");
        run_file_test(32, 3, "random");

        // Corner Case Tests (from files)
        run_file_test(16, 3, "zeros");
        run_file_test(16, 3, "max");
        run_file_test(16, 3, "sparse");
        run_file_test(16, 3, "checker");
        
        // Custom Tests from test_cases directory
        run_custom_test("01_Basic_Minimal");
        run_custom_test("02_Basic_Identity");
        run_custom_test("03_Basic_AllOnes");
        run_custom_test("04_Regular_Standard");
        run_custom_test("05_Regular_LargeHalo");
        run_custom_test("06_Regular_PingPong");
        run_custom_test("07_Adv_MaxSpec");
        run_custom_test("08_Adv_Throughput");
        run_custom_test("09_Pro_PartialTile");
        run_custom_test("10_Pro_Saturation");
        
        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("\n");
        $display("================================================================");
        $display("                    SIMULATION SUMMARY");
        $display("================================================================");
        $display("Total Tests:  %0d", total_tests);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", total_tests - pass_count);
        $display("Total Errors: %0d", errors);
        
        if (errors == 0) begin
            $display("\n*** ALL TESTS PASSED ***\n");
        end else begin
            $display("\n*** TESTS FAILED: %0d ERRORS ***\n", errors);
        end
        $display("================================================================\n");
        
        $finish;
    end

    //==========================================================================
    // Watchdog Timer
    //==========================================================================
    initial begin
        #(CLK_PERIOD * TIMEOUT_CYCLES * 10);
        $display("\n*** GLOBAL TIMEOUT - SIMULATION TERMINATED ***\n");
        $finish;
    end

endmodule
