/*
 * Real Data Testbench for AGU and Data Loader
 * 
 * Loads input image and kernel from text files
 * Processes tiles through AGU and Data Loader
 * Stores results to output file
 */

`timescale 1ns / 1ps

module tb_agu_dataloader_real;

    // Parameters
    parameter DATA_WIDTH = 32;
    parameter PSUM_WIDTH = 32;
    parameter ADDR_WIDTH = 8;
    parameter ARRAY_SIZE = 8;
    parameter DRAM_WIDTH = 32;
    parameter CLK_PERIOD = 10;
    
    // File paths
    parameter INPUT_FILE = "./input_matrix_AGU.txt";
    parameter KERNEL_FILE = "./kernel_AGU.txt";
    parameter OUTPUT_FILE = "./agu_dataloader_output_AGU.txt";
    // parameter INPUT_FILE = "../../sim/data/inputs/input_matrix.txt";
    // parameter KERNEL_FILE = "../../sim/data/inputs/kernel.txt";
    // parameter OUTPUT_FILE = "../../sim/data/results/agu_dataloader_output.txt";
    
    // Clock and reset
    reg clk;
    reg rst_n;
    
    // Control signals
    reg start;
    reg go_load;
    reg go_stream;
    reg go_unload;
    reg mode_load_weight;
    
    // Configuration
    reg [7:0] image_width;
    reg [7:0] image_height;
    reg [4:0] kernel_size;
    reg [7:0] num_tiles_x;
    reg [7:0] num_tiles_y;
    reg [7:0] current_tile_x;
    reg [7:0] current_tile_y;
    
    // Status outputs
    wire load_done;
    wire stream_done;
    wire unload_done;
    wire buffer_ready;
    wire active_buffer;
    
    // DRAM Interface
    wire [DRAM_WIDTH-1:0] dram_rx_data;
    wire dram_rx_valid;
    wire dram_rx_ready;
    wire [DRAM_WIDTH-1:0] dram_tx_data;
    wire dram_tx_valid;
    wire dram_tx_ready;
    
    // DRAM control interface
    wire [19:0] dram_read_addr;
    wire dram_read_enable;
    wire [19:0] dram_write_addr;
    wire dram_write_enable;
    wire [15:0] dram_transfer_length;
    wire dram_read_complete;
    wire dram_write_complete;
    wire dram_busy;
    
    // SRAM Interface
    wire sram_start;
    wire sram_buffer_switch;
    wire sram_ready;
    wire sram_wr_buffer_full;
    wire sram_rd_buffer_empty;
    wire sram_wr_valid;
    wire sram_wr_ready;
    wire [DATA_WIDTH-1:0] sram_wr_data;
    wire [ADDR_WIDTH-1:0] sram_wr_addr;
    wire sram_rd_ready;
    wire sram_rd_valid;
    wire [DATA_WIDTH-1:0] sram_rd_data;
    wire [ADDR_WIDTH-1:0] sram_rd_addr;
    
    // Systolic Array Interface
    wire [ARRAY_SIZE*DATA_WIDTH-1:0] pixel_out;
    wire pixel_valid;
    reg [ARRAY_SIZE*PSUM_WIDTH-1:0] psum_in;
    reg psum_valid;
    
    // Test variables
    integer i, j, k;
    integer test_passed;
    integer test_failed;
    integer input_file, kernel_file, output_file;
    integer scan_result;
    
    // Memory arrays
    reg [7:0] input_image [0:4095];   // 64x64 max
    reg [7:0] kernel_weights [0:24];  // 5x5 max kernel
    reg [31:0] output_results [0:1023]; // Store output
    integer num_input_pixels;
    integer num_kernel_weights;
    integer output_count;
    
    // Instantiate DRAM
    dram #(
        .DATA_WIDTH(DRAM_WIDTH),
        .ADDR_WIDTH(20),
        .INPUT_FILE(""),
        .KERNEL_FILE(""),
        .OUTPUT_FILE("")
    ) dram_inst (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(dram_rx_data),
        .rx_valid(dram_rx_valid),
        .rx_ready(dram_rx_ready),
        .tx_data(dram_tx_data),
        .tx_valid(dram_tx_valid),
        .tx_ready(dram_tx_ready),
        .read_addr(dram_read_addr),
        .read_enable(dram_read_enable),
        .write_addr(dram_write_addr),
        .write_enable(dram_write_enable),
        .transfer_length(dram_transfer_length),
        .read_complete(dram_read_complete),
        .write_complete(dram_write_complete),
        .dram_busy(dram_busy)
    );
    
    // Instantiate SRAM
    sram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE),
        .DRAM_WIDTH(DRAM_WIDTH)
    ) sram_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(sram_start),
        .buffer_switch(sram_buffer_switch),
        .ping_active(active_buffer),
        .ready(sram_ready),
        .agu_wr_valid(sram_wr_valid),
        .agu_wr_ready(sram_wr_ready),
        .agu_wr_data(sram_wr_data),
        .agu_wr_addr(sram_wr_addr),
        .wr_buffer_full(sram_wr_buffer_full),
        .agu_rd_data_ready(sram_rd_ready),
        .agu_rd_data_valid(sram_rd_valid),
        .agu_rd_addr(sram_rd_addr),
        .agu_rd_data(sram_rd_data),
        .sa_wr_valid(1'b0),
        .sa_wr_ready(),
        .sa_wr_data(8'h0),
        .sa_wr_addr(8'h0),
        .sa_rd_data_ready(1'b0),
        .sa_rd_data_valid(),
        .sa_rd_addr(8'h0),
        .sa_rd_data(),
        .rd_buffer_empty(sram_rd_buffer_empty),
        .rx_data(dram_rx_data),
        .rx_valid(dram_rx_valid),
        .rx_ready(dram_rx_ready),
        .tx_data(dram_tx_data),
        .tx_valid(dram_tx_valid),
        .tx_ready(dram_tx_ready)
    );
    
    // Instantiate Data Loader
    data_loader #(
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE),
        .DRAM_WIDTH(DRAM_WIDTH)
    ) data_loader_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .go_load(go_load),
        .go_stream(go_stream),
        .go_unload(go_unload),
        .mode_load_weight(mode_load_weight),
        .image_width(image_width),
        .image_height(image_height),
        .kernel_size(kernel_size),
        .num_tiles_x(num_tiles_x),
        .num_tiles_y(num_tiles_y),
        .current_tile_x(current_tile_x),
        .current_tile_y(current_tile_y),
        .load_done(load_done),
        .stream_done(stream_done),
        .unload_done(unload_done),
        .buffer_ready(buffer_ready),
        .active_buffer(active_buffer),
        .dram_rx_data(dram_rx_data),
        .dram_rx_valid(dram_rx_valid),
        .dram_rx_ready(dram_rx_ready),
        .dram_tx_data(dram_tx_data),
        .dram_tx_valid(dram_tx_valid),
        .dram_tx_ready(dram_tx_ready),
        .sram_start(sram_start),
        .sram_buffer_switch(sram_buffer_switch),
        .sram_ready(sram_ready),
        .sram_wr_buffer_full(sram_wr_buffer_full),
        .sram_rd_buffer_empty(sram_rd_buffer_empty),
        .sram_wr_valid(sram_wr_valid),
        .sram_wr_ready(sram_wr_ready),
        .sram_wr_data(sram_wr_data),
        .sram_wr_addr(sram_wr_addr),
        .sram_rd_ready(sram_rd_ready),
        .sram_rd_valid(sram_rd_valid),
        .sram_rd_data(sram_rd_data),
        .sram_rd_addr(sram_rd_addr),
        .pixel_out(pixel_out),
        .pixel_valid(pixel_valid),
        .psum_in(psum_in),
        .psum_valid(psum_valid)
    );
    
    // Connect DRAM control signals from AGU
    assign dram_read_addr = data_loader_inst.agu_inst.dram_rd_addr;
    assign dram_read_enable = data_loader_inst.agu_inst.dram_rd_req;
    assign dram_write_addr = data_loader_inst.agu_inst.dram_wr_addr;
    assign dram_write_enable = data_loader_inst.agu_inst.dram_wr_req;
    assign dram_transfer_length = 16'd100;
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Load input image from file
    task load_input_image;
        integer i;
        integer value;
        begin
            $display("Loading input image from: %s", INPUT_FILE);
            input_file = $fopen(INPUT_FILE, "r");
            if (input_file == 0) begin
                $display("ERROR: Cannot open input file: %s", INPUT_FILE);
                $display("Current working directory needs this file.");
                $finish;
            end else begin
                $display("  ✓ File opened successfully");
            end
            
            num_input_pixels = 0;
            while (num_input_pixels < 4096) begin
                scan_result = $fscanf(input_file, "%d", value);
                if (scan_result != 1) begin
                    break;  // Stop if scan fails or EOF
                end
                input_image[num_input_pixels] = value[7:0];
                num_input_pixels = num_input_pixels + 1;
                
                // Print progress every 100 pixels
                if (num_input_pixels % 100 == 0) begin
                    $display("  Reading input: %0d pixels read so far...", num_input_pixels);
                end
            end
            $fclose(input_file);
            
            $display("  ✓ Finished reading file: %0d pixels total", num_input_pixels);
            
            // Display first few values
            $display("  First 10 pixel values: %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                     input_image[0], input_image[1], input_image[2], input_image[3], input_image[4],
                     input_image[5], input_image[6], input_image[7], input_image[8], input_image[9]);
            
            // Load into DRAM starting at address 0
            $display("  Loading pixels into DRAM memory...");
            for (i = 0; i < num_input_pixels; i = i + 1) begin
                dram_inst.memory[i] = input_image[i];
            end
            
            $display("  ✓ Loaded %0d pixels into DRAM (addresses 0x0000-0x%h)", 
                     num_input_pixels, num_input_pixels-1);
        end
    endtask
    
    // Load kernel weights from file
    task load_kernel_weights;
        integer i;
        integer value;
        begin
            $display("\nLoading kernel weights from: %s", KERNEL_FILE);
            kernel_file = $fopen(KERNEL_FILE, "r");
            if (kernel_file == 0) begin
                $display("ERROR: Cannot open kernel file: %s", KERNEL_FILE);
                $finish;
            end else begin
                $display("  ✓ File opened successfully");
            end
            
            num_kernel_weights = 0;
            while (num_kernel_weights < 25) begin
                scan_result = $fscanf(kernel_file, "%d", value);
                if (scan_result != 1) begin
                    break;  // Stop if scan fails or EOF
                end
                kernel_weights[num_kernel_weights] = value[7:0];
                $display("  Read kernel[%0d] = %0d", num_kernel_weights, value);
                num_kernel_weights = num_kernel_weights + 1;
            end
            $fclose(kernel_file);
            
            $display("  ✓ Finished reading file: %0d weights total", num_kernel_weights);
            
            // Load into DRAM starting at address 0x1000 (4096)
            $display("  Loading kernel weights into DRAM memory...");
            for (i = 0; i < num_kernel_weights; i = i + 1) begin
                dram_inst.memory[20'h1000 + i] = kernel_weights[i];
            end
            
            $display("  ✓ Loaded %0d kernel weights into DRAM (addresses 0x1000-0x%h)", 
                     num_kernel_weights, 20'h1000 + num_kernel_weights - 1);
            
            // Display kernel as matrix
            $display("\n  Kernel %0dx%0d Matrix:", kernel_size, kernel_size);
            for (i = 0; i < num_kernel_weights; i = i + 1) begin
                if (i % kernel_size == 0) $write("    ");
                $write("%4d ", $signed(kernel_weights[i]));
                if ((i + 1) % kernel_size == 0) $write("\n");
            end
        end
    endtask
    
    // Save output results to file
    task save_output_results;
        integer i;
        begin
            $display("\nSaving output results to: %s", OUTPUT_FILE);
            output_file = $fopen(OUTPUT_FILE, "w");
            if (output_file == 0) begin
                $display("ERROR: Cannot open output file: %s", OUTPUT_FILE);
                $finish;
            end
            
            $fwrite(output_file, "# AGU and Data Loader Test Results\n");
            $fwrite(output_file, "# Image Size: %0dx%0d\n", image_width, image_height);
            $fwrite(output_file, "# Kernel Size: %0dx%0d\n", kernel_size, kernel_size);
            $fwrite(output_file, "# Array Size: %0dx%0d\n", ARRAY_SIZE, ARRAY_SIZE);
            $fwrite(output_file, "# Total Output Values: %0d\n", output_count);
            $fwrite(output_file, "#\n");
            
            for (i = 0; i < output_count; i = i + 1) begin
                $fwrite(output_file, "%d\n", output_results[i]);
            end
            
            $fclose(output_file);
            $display("  Saved %0d output values", output_count);
        end
    endtask
    
    // Monitor and capture streaming output
    task monitor_stream_output;
        begin
            output_count = 0;
            fork
                begin
                    while (!stream_done && output_count < 1024) begin
                        @(posedge clk);
                        if (pixel_valid) begin
                            // Capture all 8 pixels from the array output
                            for (k = 0; k < ARRAY_SIZE && output_count < 1024; k = k + 1) begin
                                output_results[output_count] = pixel_out[k*DATA_WIDTH +: DATA_WIDTH];
                                output_count = output_count + 1;
                            end
                            
                            // Display first few outputs
                            if (output_count <= ARRAY_SIZE * 3) begin
                                $display("  [%0t] Stream output [%0d]: %h %h %h %h %h %h %h %h",
                                       $time, (output_count/ARRAY_SIZE) - 1,
                                       pixel_out[0*DATA_WIDTH +: 8],
                                       pixel_out[1*DATA_WIDTH +: 8],
                                       pixel_out[2*DATA_WIDTH +: 8],
                                       pixel_out[3*DATA_WIDTH +: 8],
                                       pixel_out[4*DATA_WIDTH +: 8],
                                       pixel_out[5*DATA_WIDTH +: 8],
                                       pixel_out[6*DATA_WIDTH +: 8],
                                       pixel_out[7*DATA_WIDTH +: 8]);
                            end
                        end
                    end
                end
            join_none
        end
    endtask
    
    // Main test stimulus
    initial begin
        // Initialize
        rst_n = 0;
        start = 0;
        go_load = 0;
        go_stream = 0;
        go_unload = 0;
        mode_load_weight = 0;
        psum_in = {(ARRAY_SIZE*PSUM_WIDTH){1'b0}};
        psum_valid = 0;
        test_passed = 0;
        test_failed = 0;
        output_count = 0;
        
        // Default configuration
        image_width = 8'd32;
        image_height = 8'd32;
        kernel_size = 5'd3;
        num_tiles_x = 8'd4;
        num_tiles_y = 8'd4;
        current_tile_x = 8'd0;
        current_tile_y = 8'd0;
        
        $display("\n========================================");
        $display("=== AGU and Data Loader Real Data Test ===");
        $display("========================================");
        $display("Configuration:");
        $display("  Image Size: %0dx%0d", image_width, image_height);
        $display("  Kernel Size: %0dx%0d", kernel_size, kernel_size);
        $display("  Array Size: %0dx%0d", ARRAY_SIZE, ARRAY_SIZE);
        $display("  Number of Tiles: %0dx%0d", num_tiles_x, num_tiles_y);
        $display("");
        
        // Load data from files
        load_input_image();
        load_kernel_weights();
        
        // Reset
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        // Start system
        $display("\n[%0t] Starting data loader system...", $time);
        start = 1;
        #(CLK_PERIOD * 2);
        start = 0;
        
        // Wait for ready
        wait(buffer_ready);
        $display("[%0t] System ready\n", $time);
        
        //======================================================================
        // Step 1: Load Kernel Weights
        //======================================================================
        $display("========================================");
        $display("[STEP 1] Loading kernel weights from DRAM...");
        $display("========================================");
        mode_load_weight = 1;
        go_load = 1;
        #(CLK_PERIOD);
        go_load = 0;
        mode_load_weight = 0;
        
        wait(load_done);
        $display("[%0t] ✓ Kernel weights loaded to SRAM", $time);
        #(CLK_PERIOD * 5);
        
        //======================================================================
        // Step 2: Process First Tile (0,0)
        //======================================================================
        $display("\n========================================");
        $display("[STEP 2] Processing Tile (0,0)...");
        $display("========================================");
        
        current_tile_x = 8'd0;
        current_tile_y = 8'd0;
        
        // Load tile
        $display("  [2.1] Loading tile data from DRAM to SRAM...");
        $display("        Tile includes halo pixels for convolution");
        $display("        Expected tile size: %0dx%0d", 
                 ARRAY_SIZE + kernel_size - 1, ARRAY_SIZE + kernel_size - 1);
        go_load = 1;
        #(CLK_PERIOD);
        go_load = 0;
        
        wait(load_done);
        $display("  [%0t] ✓ Tile loaded (DRAM → SRAM)", $time);
        #(CLK_PERIOD * 5);
        
        // Stream tile
        $display("\n  [2.2] Streaming tile data to systolic array...");
        monitor_stream_output();
        go_stream = 1;
        #(CLK_PERIOD);
        go_stream = 0;
        
        wait(stream_done);
        $display("  [%0t] ✓ Tile streamed (SRAM → Array) - %0d values captured", 
                 $time, output_count);
        #(CLK_PERIOD * 10);
        
        //======================================================================
        // Step 3: Process Second Tile (1,0)
        //======================================================================
        $display("\n========================================");
        $display("[STEP 3] Processing Tile (1,0)...");
        $display("========================================");
        
        current_tile_x = 8'd1;
        current_tile_y = 8'd0;
        
        // Load tile
        $display("  [3.1] Loading tile data...");
        go_load = 1;
        #(CLK_PERIOD);
        go_load = 0;
        
        wait(load_done);
        $display("  [%0t] ✓ Tile loaded", $time);
        #(CLK_PERIOD * 5);
        
        // Stream tile
        $display("\n  [3.2] Streaming tile data...");
        monitor_stream_output();
        go_stream = 1;
        #(CLK_PERIOD);
        go_stream = 0;
        
        wait(stream_done);
        $display("  [%0t] ✓ Tile streamed - Total outputs: %0d", $time, output_count);
        #(CLK_PERIOD * 10);
        
        //======================================================================
        // Step 4: Verify AGU Functionality
        //======================================================================
        $display("\n========================================");
        $display("[STEP 4] Verifying AGU Functionality...");
        $display("========================================");
        
        // Check tile dimensions
        if (data_loader_inst.agu_inst.tile_width == (ARRAY_SIZE + kernel_size - 1)) begin
            $display("  ✓ PASS: Tile width = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.tile_width, 
                     ARRAY_SIZE + kernel_size - 1);
            test_passed = test_passed + 1;
        end else begin
            $display("  ✗ FAIL: Tile width = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.tile_width,
                     ARRAY_SIZE + kernel_size - 1);
            test_failed = test_failed + 1;
        end
        
        // Check halo size
        if (data_loader_inst.agu_inst.halo_size == ((kernel_size - 1) >> 1)) begin
            $display("  ✓ PASS: Halo size = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.halo_size, 
                     (kernel_size - 1) >> 1);
            test_passed = test_passed + 1;
        end else begin
            $display("  ✗ FAIL: Halo size = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.halo_size,
                     (kernel_size - 1) >> 1);
            test_failed = test_failed + 1;
        end
        
        // Check tile positioning
        if (data_loader_inst.agu_inst.tile_start_x == (current_tile_x * ARRAY_SIZE)) begin
            $display("  ✓ PASS: Tile start X = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.tile_start_x,
                     current_tile_x * ARRAY_SIZE);
            test_passed = test_passed + 1;
        end else begin
            $display("  ✗ FAIL: Tile start X = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.tile_start_x,
                     current_tile_x * ARRAY_SIZE);
            test_failed = test_failed + 1;
        end
        
        //======================================================================
        // Save Results
        //======================================================================
        $display("\n========================================");
        $display("[STEP 5] Saving Results...");
        $display("========================================");
        save_output_results();
        
        //======================================================================
        // Test Summary
        //======================================================================
        $display("\n========================================");
        $display("=== Test Summary ===");
        $display("========================================");
        $display("Input pixels loaded:    %0d", num_input_pixels);
        $display("Kernel weights loaded:  %0d", num_kernel_weights);
        $display("Output values captured: %0d", output_count);
        $display("Tests passed:           %0d", test_passed);
        $display("Tests failed:           %0d", test_failed);
        
        if (test_failed == 0) begin
            $display("\n✓✓✓ ALL TESTS PASSED ✓✓✓");
        end else begin
            $display("\n✗✗✗ SOME TESTS FAILED ✗✗✗");
        end
        
        $display("\nResults saved to: %s", OUTPUT_FILE);
        $display("========================================");
        $display("=== Simulation Complete ===");
        $display("========================================");
        $display("Time: %0t\n", $time);
        
        #(CLK_PERIOD * 10);
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 100000);
        $display("\nERROR: Simulation timeout!");
        $finish;
    end
    
    // Waveform dump
    initial begin
        $dumpfile("tb_agu_dataloader_real.vcd");
        $dumpvars(0, tb_agu_dataloader_real);
    end

endmodule
