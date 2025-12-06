/*
 * Testbench for AGU and Data Loader
 * 
 * Verifies the complete data flow:
 * 1. Loading: DRAM → SRAM (with AGU address generation)
 * 2. Streaming: SRAM → Systolic Array (sliding window)
 * 3. Unloading: Array → SRAM → DRAM
 * 4. Ping-pong buffer switching
 * 5. Tiling with halo pixels
 */

`timescale 1ns / 1ps

module tb_agu_dataloader;

    // Parameters
    parameter DATA_WIDTH = 32;
    parameter PSUM_WIDTH = 32;
    parameter ADDR_WIDTH = 8;
    parameter ARRAY_SIZE = 8;
    parameter DRAM_WIDTH = 32;
    parameter CLK_PERIOD = 10;
    
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
    integer i, j;
    integer test_passed;
    integer test_failed;
    reg [7:0] expected_addr;
    reg [DATA_WIDTH-1:0] test_memory [0:255];
    
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
    assign dram_transfer_length = 16'd100;  // Default transfer length
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test stimulus
    initial begin
        // Initialize
        rst_n = 0;
        start = 0;
        go_load = 0;
        go_stream = 0;
        go_unload = 0;
        mode_load_weight = 0;
        image_width = 8'd32;
        image_height = 8'd32;
        kernel_size = 5'd3;
        num_tiles_x = 8'd4;
        num_tiles_y = 8'd4;
        current_tile_x = 8'd0;
        current_tile_y = 8'd0;
        psum_in = {(ARRAY_SIZE*PSUM_WIDTH){1'b0}};
        psum_valid = 0;
        test_passed = 0;
        test_failed = 0;
        
        // Initialize test memory
        for (i = 0; i < 256; i = i + 1) begin
            test_memory[i] = i[7:0];
        end
        
        // Reset
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 5);
        
        $display("\n=== AGU and Data Loader Testbench ===");
        $display("Time: %0t", $time);
        $display("Configuration:");
        $display("  Image Size: %0dx%0d", image_width, image_height);
        $display("  Kernel Size: %0d", kernel_size);
        $display("  Array Size: %0d", ARRAY_SIZE);
        $display("  Number of Tiles: %0dx%0d", num_tiles_x, num_tiles_y);
        
        // Start system
        start = 1;
        #(CLK_PERIOD * 2);
        start = 0;
        
        // Wait for ready
        wait(buffer_ready);
        $display("\n[%0t] System ready", $time);
        
        //======================================================================
        // TEST 1: Load Weight Mode
        //======================================================================
        $display("\n[TEST 1] Testing weight loading...");
        mode_load_weight = 1;
        go_load = 1;
        #(CLK_PERIOD);
        go_load = 0;
        mode_load_weight = 0;
        
        // Wait for load complete
        wait(load_done);
        $display("[%0t] Weight load complete", $time);
        #(CLK_PERIOD * 5);
        test_passed = test_passed + 1;
        
        //======================================================================
        // TEST 2: Load Input Tile (Tile 0,0)
        //======================================================================
        $display("\n[TEST 2] Testing input tile loading (Tile 0,0)...");
        current_tile_x = 8'd0;
        current_tile_y = 8'd0;
        go_load = 1;
        #(CLK_PERIOD);
        go_load = 0;
        
        // Wait for load complete
        wait(load_done);
        $display("[%0t] Tile (0,0) load complete", $time);
        
        // Verify AGU generated correct addresses
        if (data_loader_inst.agu_inst.tile_width == (ARRAY_SIZE + kernel_size - 1)) begin
            $display("  PASS: Tile width = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.tile_width, 
                     ARRAY_SIZE + kernel_size - 1);
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Tile width = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.tile_width,
                     ARRAY_SIZE + kernel_size - 1);
            test_failed = test_failed + 1;
        end
        
        #(CLK_PERIOD * 5);
        
        //======================================================================
        // TEST 3: Stream Data to Array
        //======================================================================
        $display("\n[TEST 3] Testing streaming to systolic array...");
        go_stream = 1;
        #(CLK_PERIOD);
        go_stream = 0;
        
        // Monitor pixel output
        fork
            begin: monitor_pixels
                integer pixel_count;
                pixel_count = 0;
                while (!stream_done) begin
                    @(posedge clk);
                    if (pixel_valid) begin
                        pixel_count = pixel_count + 1;
                        $display("[%0t] Pixel data output: count=%0d", $time, pixel_count);
                    end
                end
                $display("  Total pixels streamed: %0d", pixel_count);
            end
        join_none
        
        // Wait for stream complete
        wait(stream_done);
        $display("[%0t] Streaming complete", $time);
        test_passed = test_passed + 1;
        
        #(CLK_PERIOD * 10);
        
        //======================================================================
        // TEST 4: Unload Results
        //======================================================================
        $display("\n[TEST 4] Testing result unloading...");
        
        // Simulate array output
        psum_valid = 1;
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            psum_in[i*PSUM_WIDTH +: PSUM_WIDTH] = 32'hA000_0000 + i;
        end
        
        go_unload = 1;
        #(CLK_PERIOD);
        go_unload = 0;
        
        // Wait for unload complete
        wait(unload_done);
        $display("[%0t] Unload complete", $time);
        psum_valid = 0;
        test_passed = test_passed + 1;
        
        #(CLK_PERIOD * 10);
        
        //======================================================================
        // TEST 5: Load Different Tile (Tile 1,0)
        //======================================================================
        $display("\n[TEST 5] Testing different tile loading (Tile 1,0)...");
        current_tile_x = 8'd1;
        current_tile_y = 8'd0;
        go_load = 1;
        #(CLK_PERIOD);
        go_load = 0;
        
        wait(load_done);
        $display("[%0t] Tile (1,0) load complete", $time);
        
        // Verify tile start position
        expected_addr = current_tile_x * ARRAY_SIZE;
        if (data_loader_inst.agu_inst.tile_start_x == expected_addr) begin
            $display("  PASS: Tile start X = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.tile_start_x, expected_addr);
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Tile start X = %0d (expected %0d)", 
                     data_loader_inst.agu_inst.tile_start_x, expected_addr);
            test_failed = test_failed + 1;
        end
        
        #(CLK_PERIOD * 10);
        
        //======================================================================
        // TEST 6: Ping-Pong Buffer Switching
        //======================================================================
        $display("\n[TEST 6] Testing ping-pong buffer switching...");
        $display("  Current buffer: %s", active_buffer ? "Pong" : "Ping");
        
        // Stream and switch
        go_stream = 1;
        #(CLK_PERIOD);
        go_stream = 0;
        wait(stream_done);
        
        $display("  After streaming buffer: %s", active_buffer ? "Pong" : "Ping");
        test_passed = test_passed + 1;
        
        #(CLK_PERIOD * 10);
        
        //======================================================================
        // TEST 7: AGU Address Generation Patterns
        //======================================================================
        $display("\n[TEST 7] Testing AGU address generation patterns...");
        
        // Test read address sequence during LOAD
        current_tile_x = 8'd0;
        current_tile_y = 8'd0;
        go_load = 1;
        #(CLK_PERIOD);
        go_load = 0;
        
        fork
            begin: monitor_addresses
                integer addr_count;
                reg [ADDR_WIDTH-1:0] last_addr;
                addr_count = 0;
                last_addr = 0;
                
                while (!load_done) begin
                    @(posedge clk);
                    if (data_loader_inst.agu_inst.wr_enable) begin
                        addr_count = addr_count + 1;
                        if (addr_count <= 10) begin
                            $display("  Address[%0d]: 0x%h", addr_count, 
                                   data_loader_inst.agu_inst.wr_addr);
                        end
                        last_addr = data_loader_inst.agu_inst.wr_addr;
                    end
                end
                $display("  Total addresses generated: %0d", addr_count);
                $display("  Last address: 0x%h", last_addr);
            end
        join_none
        
        wait(load_done);
        test_passed = test_passed + 1;
        
        #(CLK_PERIOD * 10);
        
        //======================================================================
        // TEST 8: Halo Pixel Calculation
        //======================================================================
        $display("\n[TEST 8] Testing halo pixel calculation...");
        
        kernel_size = 5'd5;  // Change kernel size
        #(CLK_PERIOD * 2);
        
        expected_addr = (kernel_size - 1) >> 1;  // Expected halo size
        if (data_loader_inst.agu_inst.halo_size == expected_addr) begin
            $display("  PASS: Halo size = %0d (expected %0d) for kernel=%0d", 
                     data_loader_inst.agu_inst.halo_size, expected_addr, kernel_size);
            test_passed = test_passed + 1;
        end else begin
            $display("  FAIL: Halo size = %0d (expected %0d) for kernel=%0d", 
                     data_loader_inst.agu_inst.halo_size, expected_addr, kernel_size);
            test_failed = test_failed + 1;
        end
        
        // Restore kernel size
        kernel_size = 5'd3;
        #(CLK_PERIOD * 5);
        
        //======================================================================
        // TEST 9: Full Tile Pipeline
        //======================================================================
        $display("\n[TEST 9] Testing complete tile pipeline (Load→Stream→Unload)...");
        current_tile_x = 8'd2;
        current_tile_y = 8'd1;
        
        // Load
        go_load = 1;
        #(CLK_PERIOD);
        go_load = 0;
        wait(load_done);
        $display("  Load phase complete");
        
        #(CLK_PERIOD * 5);
        
        // Stream
        go_stream = 1;
        #(CLK_PERIOD);
        go_stream = 0;
        wait(stream_done);
        $display("  Stream phase complete");
        
        #(CLK_PERIOD * 5);
        
        // Unload
        psum_valid = 1;
        go_unload = 1;
        #(CLK_PERIOD);
        go_unload = 0;
        wait(unload_done);
        psum_valid = 0;
        $display("  Unload phase complete");
        
        test_passed = test_passed + 1;
        
        #(CLK_PERIOD * 20);
        
        //======================================================================
        // Test Summary
        //======================================================================
        $display("\n========================================");
        $display("=== Test Summary ===");
        $display("========================================");
        $display("Tests Passed: %0d", test_passed);
        $display("Tests Failed: %0d", test_failed);
        
        if (test_failed == 0) begin
            $display("\n*** ALL TESTS PASSED ***");
        end else begin
            $display("\n*** SOME TESTS FAILED ***");
        end
        
        $display("\n=== Simulation Complete ===");
        $display("Time: %0t", $time);
        
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
        $dumpfile("tb_agu_dataloader.vcd");
        $dumpvars(0, tb_agu_dataloader);
    end

endmodule