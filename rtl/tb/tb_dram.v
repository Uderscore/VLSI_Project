/*
 * Testbench for DRAM Module
 * 
 * This testbench verifies the DRAM streaming interface:
 * - Valid/Ready handshake for RX stream (DRAM → Accelerator)
 * - Valid/Ready handshake for TX stream (Accelerator → DRAM)
 * - Read and write transactions
 * - Different bus widths (8, 16, 32 bits)
 */

`timescale 1ns / 1ps

module tb_dram;

    // Parameters
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 20;
    parameter CLK_PERIOD = 10;
    
    // Clock and reset
    reg clk;
    reg rst_n;
    
    // RX Stream (DRAM → Accelerator)
    wire [DATA_WIDTH-1:0] rx_data;
    wire rx_valid;
    reg rx_ready;
    
    // TX Stream (Accelerator → DRAM)
    reg [DATA_WIDTH-1:0] tx_data;
    reg tx_valid;
    wire tx_ready;
    
    // Control interface
    reg [ADDR_WIDTH-1:0] read_addr;
    reg read_enable;
    reg [ADDR_WIDTH-1:0] write_addr;
    reg write_enable;
    reg [15:0] transfer_length;
    
    // Status
    wire read_complete;
    wire write_complete;
    wire dram_busy;
    
    // Test data
    reg [DATA_WIDTH-1:0] test_data [0:255];
    reg [DATA_WIDTH-1:0] received_data [0:255];
    integer i, j;
    integer errors;
    
    // DUT instantiation
    dram #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .INPUT_FILE(""),     // Don't load files in basic test
        .KERNEL_FILE(""),
        .OUTPUT_FILE("")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_ready(rx_ready),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .read_addr(read_addr),
        .read_enable(read_enable),
        .write_addr(write_addr),
        .write_enable(write_enable),
        .transfer_length(transfer_length),
        .read_complete(read_complete),
        .write_complete(write_complete),
        .dram_busy(dram_busy)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // Test stimulus
    initial begin
        // Initialize signals
        rst_n = 0;
        rx_ready = 0;
        tx_data = 0;
        tx_valid = 0;
        read_addr = 0;
        read_enable = 0;
        write_addr = 0;
        write_enable = 0;
        transfer_length = 0;
        errors = 0;
        
        // Generate test data
        for (i = 0; i < 256; i = i + 1) begin
            test_data[i] = $random;
            received_data[i] = 0;
        end
        
        // Reset
        #(CLK_PERIOD * 5);
        rst_n = 1;
        #(CLK_PERIOD * 2);
        
        $display("=== Starting DRAM Testbench ===");
        $display("Data Width: %d bits", DATA_WIDTH);
        
        // Test 1: Write data to DRAM
        $display("\n[TEST 1] Writing data to DRAM...");
        test_write(20'h1000, 16);  // Write 16 words at address 0x1000
        
        // Test 2: Read data from DRAM
        $display("\n[TEST 2] Reading data from DRAM...");
        test_read(20'h1000, 16);  // Read 16 words from address 0x1000
        
        // Test 3: Verify data integrity
        $display("\n[TEST 3] Verifying data integrity...");
        verify_data(16);
        
        // Test 4: Test with backpressure (slow receiver)
        $display("\n[TEST 4] Testing read with backpressure...");
        test_read_with_backpressure(20'h2000, 8);
        
        // Test 5: Test with slow transmitter
        $display("\n[TEST 5] Testing write with slow transmitter...");
        test_write_slow(20'h3000, 8);
        
        // Test 6: Burst write and read
        $display("\n[TEST 6] Testing burst write and read...");
        test_burst(20'h4000, 64);
        
        // Summary
        #(CLK_PERIOD * 10);
        $display("\n=== Test Summary ===");
        if (errors == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("TESTS FAILED with %d errors", errors);
        end
        
        $display("\n=== Simulation Complete ===");
        $finish;
    end
    
    // Task: Write test
    task test_write;
        input [ADDR_WIDTH-1:0] addr;
        input integer count;
        integer idx;
        begin
            write_addr = addr;
            transfer_length = count;
            write_enable = 1;
            
            @(posedge clk);
            write_enable = 0;
            
            // Send data
            idx = 0;
            while (idx < count) begin
                @(posedge clk);
                if (tx_ready) begin
                    tx_data = test_data[idx];
                    tx_valid = 1;
                    @(posedge clk);
                    tx_valid = 0;
                    idx = idx + 1;
                end
            end
            
            // Wait for completion
            @(posedge write_complete);
            $display("  Write complete: %d words written to 0x%h", count, addr);
        end
    endtask
    
    // Task: Read test
    task test_read;
        input [ADDR_WIDTH-1:0] addr;
        input integer count;
        integer idx;
        begin
            read_addr = addr;
            transfer_length = count;
            rx_ready = 1;  // Always ready for this test
            read_enable = 1;
            
            @(posedge clk);
            read_enable = 0;
            
            // Receive data
            idx = 0;
            while (idx < count) begin
                @(posedge clk);
                if (rx_valid && rx_ready) begin
                    received_data[idx] = rx_data;
                    idx = idx + 1;
                end
            end
            
            rx_ready = 0;
            @(posedge read_complete);
            $display("  Read complete: %d words read from 0x%h", count, addr);
        end
    endtask
    
    // Task: Verify data
    task verify_data;
        input integer count;
        integer idx;
        integer local_errors;
        begin
            local_errors = 0;
            for (idx = 0; idx < count; idx = idx + 1) begin
                if (received_data[idx] !== test_data[idx]) begin
                    $display("  ERROR: Mismatch at index %d: expected 0x%h, got 0x%h", 
                             idx, test_data[idx], received_data[idx]);
                    local_errors = local_errors + 1;
                end
            end
            
            if (local_errors == 0) begin
                $display("  Data verification PASSED (%d words)", count);
            end else begin
                $display("  Data verification FAILED (%d errors)", local_errors);
                errors = errors + local_errors;
            end
        end
    endtask
    
    // Task: Read with backpressure
    task test_read_with_backpressure;
        input [ADDR_WIDTH-1:0] addr;
        input integer count;
        integer idx;
        begin
            // First write some data
            for (idx = 0; idx < count; idx = idx + 1) begin
                test_data[idx] = idx + 32'hA000;
            end
            test_write(addr, count);
            
            // Read with random backpressure
            read_addr = addr;
            transfer_length = count;
            read_enable = 1;
            
            @(posedge clk);
            read_enable = 0;
            
            idx = 0;
            while (idx < count) begin
                rx_ready = $random % 2;  // Random backpressure
                @(posedge clk);
                if (rx_valid && rx_ready) begin
                    received_data[idx] = rx_data;
                    idx = idx + 1;
                end
            end
            
            // Ensure we wait for completion
            rx_ready = 0;
            if (!read_complete) begin
                @(posedge read_complete);
            end
            
            // Verify
            verify_data(count);
        end
    endtask
    
    // Task: Write with slow transmitter
    task test_write_slow;
        input [ADDR_WIDTH-1:0] addr;
        input integer count;
        integer idx;
        begin
            write_addr = addr;
            transfer_length = count;
            write_enable = 1;
            
            @(posedge clk);
            write_enable = 0;
            
            // Send data with delays
            idx = 0;
            while (idx < count) begin
                @(posedge clk);
                if (tx_ready) begin
                    tx_data = 32'hB000 + idx;
                    tx_valid = 1;
                    @(posedge clk);
                    tx_valid = 0;
                    // Random delay
                    repeat ($random % 3) @(posedge clk);
                    idx = idx + 1;
                end
            end
            
            @(posedge write_complete);
            $display("  Slow write test complete");
        end
    endtask
    
    // Task: Burst test
    task test_burst;
        input [ADDR_WIDTH-1:0] addr;
        input integer count;
        integer idx;
        begin
            // Generate burst data
            for (idx = 0; idx < count; idx = idx + 1) begin
                test_data[idx] = 32'hC000_0000 + idx;
            end
            
            // Write burst
            test_write(addr, count);
            
            // Read burst
            read_addr = addr;
            transfer_length = count;
            rx_ready = 1;
            read_enable = 1;
            
            @(posedge clk);
            read_enable = 0;
            
            idx = 0;
            while (idx < count) begin
                @(posedge clk);
                if (rx_valid && rx_ready) begin
                    received_data[idx] = rx_data;
                    idx = idx + 1;
                end
            end
            
            rx_ready = 0;
            @(posedge read_complete);
            
            // Verify burst
            verify_data(count);
        end
    endtask
    
    // Monitor
    initial begin
        $dumpfile("tb_dram.vcd");
        $dumpvars(0, tb_dram);
    end
    
    // Timeout watchdog
    initial begin
        #(CLK_PERIOD * 10000);
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
