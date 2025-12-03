`timescale 1ns / 1ps

// Simple Testbench for Memory Controller
// Tests basic write and read operations with handshaking

module tb_memory_controller;

    // Parameters
    parameter DATA_WIDTH = 32;
    parameter ADDR_WIDTH = 8;
    parameter ARRAY_SIZE = 8;
    parameter CLK_PERIOD = 10; // 100MHz clock

    // DUT signals
    reg                     clk;
    reg                     rst_n;
    reg                     start;
    reg                     buffer_switch;
    wire                    ping_active;
    wire                    ready;
    
    // AGU Write Interface
    reg                     agu_wr_valid;
    wire                    agu_wr_ready;
    reg  [DATA_WIDTH-1:0]   agu_wr_data;
    reg  [ADDR_WIDTH-1:0]   agu_wr_addr;
    wire                    wr_buffer_full;
    
    // AGU Read Interface
    reg                     agu_rd_data_ready;
    wire                    agu_rd_data_valid;
    reg  [ADDR_WIDTH-1:0]   agu_rd_addr;
    wire [DATA_WIDTH-1:0]   agu_rd_data;
    
    // SA Write Interface (unused in this simple test)
    reg                     sa_wr_valid;
    wire                    sa_wr_ready;
    reg  [DATA_WIDTH-1:0]   sa_wr_data;
    reg  [ADDR_WIDTH-1:0]   sa_wr_addr;
    
    // SA Read Interface (unused in this simple test)
    reg                     sa_rd_data_ready;
    wire                    sa_rd_data_valid;
    reg  [ADDR_WIDTH-1:0]   sa_rd_addr;
    wire [DATA_WIDTH-1:0]   sa_rd_data;
    
    wire                    rd_buffer_empty;
    
    // Test variables
    reg [DATA_WIDTH-1:0] test_data;
    reg [DATA_WIDTH-1:0] read_data;
    integer i;
    integer errors;

    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    memory_controller #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .buffer_switch(buffer_switch),
        .ping_active(ping_active),
        .ready(ready),
        .agu_wr_valid(agu_wr_valid),
        .agu_wr_ready(agu_wr_ready),
        .agu_wr_data(agu_wr_data),
        .agu_wr_addr(agu_wr_addr),
        .wr_buffer_full(wr_buffer_full),
        .agu_rd_data_ready(agu_rd_data_ready),
        .agu_rd_data_valid(agu_rd_data_valid),
        .agu_rd_addr(agu_rd_addr),
        .agu_rd_data(agu_rd_data),
        .sa_wr_valid(sa_wr_valid),
        .sa_wr_ready(sa_wr_ready),
        .sa_wr_data(sa_wr_data),
        .sa_wr_addr(sa_wr_addr),
        .sa_rd_data_ready(sa_rd_data_ready),
        .sa_rd_data_valid(sa_rd_data_valid),
        .sa_rd_addr(sa_rd_addr),
        .sa_rd_data(sa_rd_data),
        .rd_buffer_empty(rd_buffer_empty)
    );

    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //==========================================================================
    // Test Stimulus
    //==========================================================================
    initial begin
        // Initialize signals
        rst_n = 0;
        start = 0;
        buffer_switch = 0;
        agu_wr_valid = 0;
        agu_wr_data = 0;
        agu_wr_addr = 0;
        agu_rd_data_ready = 0;
        agu_rd_addr = 0;
        sa_wr_valid = 0;
        sa_wr_data = 0;
        sa_wr_addr = 0;
        sa_rd_data_ready = 0;
        sa_rd_addr = 0;
        errors = 0;
        
        // Display test start
        $display("========================================");
        $display("Simple Memory Controller Testbench");
        $display("========================================");
        
        // Reset sequence
        #(CLK_PERIOD*2);
        rst_n = 1;
        #(CLK_PERIOD*2);
        start = 1;
        #(CLK_PERIOD);
        start = 0;
        
        // Wait for ready
        wait(ready);
        $display("Time %0t: Controller ready", $time);
        
        //======================================================================
        // TEST 1: Write 5 values to Ping buffer
        //======================================================================
        $display("\n--- TEST 1: Write 5 values ---");
        for (i = 0; i < 5; i = i + 1) begin
            agu_wr_addr = i;
            agu_wr_data = 32'hA0 + i;  // Data: A0, A1, A2, A3, A4
            agu_wr_valid = 1;
            
            @(posedge clk);
            wait(agu_wr_ready);  // Wait for handshake
            $display("Time %0t: Wrote addr=%0d, data=0x%h", $time, i, agu_wr_data);
            @(posedge clk);
            agu_wr_valid = 0;
        end
        
        #(CLK_PERIOD*5);
        
        //======================================================================
        // TEST 2: Switch buffer and read back 5 values
        //======================================================================
        $display("\n--- TEST 2: Switch buffer and read 5 values ---");
        buffer_switch = 1;
        @(posedge clk);
        buffer_switch = 0;
        
        #(CLK_PERIOD*2);
        
        for (i = 0; i < 5; i = i + 1) begin
            agu_rd_addr = i;
            agu_rd_data_ready = 1;
            
            @(posedge clk);
            wait(agu_rd_data_valid);  // Wait for data valid
            @(posedge clk);  // Extra cycle for SRAM latency
            
            read_data = agu_rd_data;
            test_data = 32'hA0 + i;
            
            if (read_data == test_data) begin
                $display("Time %0t: PASS - Read addr=%0d, data=0x%h", $time, i, read_data);
            end else begin
                $display("Time %0t: FAIL - Read addr=%0d, expected=0x%h, got=0x%h", 
                         $time, i, test_data, read_data);
                errors = errors + 1;
            end
            
            agu_rd_data_ready = 0;
            #(CLK_PERIOD*2);
        end
        
        //======================================================================
        // TEST 3: Concurrent operations - Read from Ping, Write to Pong
        //======================================================================
        $display("\n--- TEST 3: Concurrent Read Ping + Write Pong ---");
        
        fork
            // Thread 1: Read from Ping buffer
            begin
                for (i = 0; i < 5; i = i + 1) begin
                    agu_rd_addr = i;
                    agu_rd_data_ready = 1;
                    
                    @(posedge clk);
                    wait(agu_rd_data_valid);
                    @(posedge clk);  // Extra cycle for SRAM latency
                    
                    read_data = agu_rd_data;
                    test_data = 32'hA0 + i;
                    
                    if (read_data == test_data) begin
                        $display("Time %0t: [READ] PASS - addr=%0d, data=0x%h", $time, i, read_data);
                    end else begin
                        $display("Time %0t: [READ] FAIL - addr=%0d, expected=0x%h, got=0x%h", 
                                 $time, i, test_data, read_data);
                        errors = errors + 1;
                    end
                    
                    agu_rd_data_ready = 0;
                    #(CLK_PERIOD*2);
                end
            end
            
            // Thread 2: Write to Pong buffer (concurrent)
            begin
                #(CLK_PERIOD*3);  // Small offset to stagger operations
                for (i = 0; i < 5; i = i + 1) begin
                    agu_wr_addr = i;
                    agu_wr_data = 32'hB0 + i;  // Data: B0, B1, B2, B3, B4
                    agu_wr_valid = 1;
                    
                    @(posedge clk);
                    wait(agu_wr_ready);
                    $display("Time %0t: [WRITE] Wrote to Pong addr=%0d, data=0x%h", $time, i, agu_wr_data);
                    @(posedge clk);
                    agu_wr_valid = 0;
                    #(CLK_PERIOD);
                end
            end
        join
        
        #(CLK_PERIOD*5);
        
        //======================================================================
        // TEST 4: Switch back and read from Pong
        //======================================================================
        $display("\n--- TEST 4: Switch to Pong and read ---");
        buffer_switch = 1;
        @(posedge clk);
        buffer_switch = 0;
        
        #(CLK_PERIOD*2);
        
        for (i = 0; i < 5; i = i + 1) begin
            agu_rd_addr = i;
            agu_rd_data_ready = 1;
            
            @(posedge clk);
            wait(agu_rd_data_valid);
            @(posedge clk);  // Extra cycle for SRAM latency
            
            read_data = agu_rd_data;
            test_data = 32'hB0 + i;
            
            if (read_data == test_data) begin
                $display("Time %0t: PASS - Read addr=%0d, data=0x%h", $time, i, read_data);
            end else begin
                $display("Time %0t: FAIL - Read addr=%0d, expected=0x%h, got=0x%h", 
                         $time, i, test_data, read_data);
                errors = errors + 1;
            end
            
            agu_rd_data_ready = 0;
            #(CLK_PERIOD*2);
        end
        
        //======================================================================
        // TEST 5: Concurrent Read from Pong, Write to Ping
        //======================================================================
        $display("\n--- TEST 5: Concurrent Read Pong + Write Ping ---");
        
        fork
            // Thread 1: Read from Pong buffer
            begin
                for (i = 0; i < 5; i = i + 1) begin
                    agu_rd_addr = i;
                    agu_rd_data_ready = 1;
                    
                    @(posedge clk);
                    wait(agu_rd_data_valid);
                    @(posedge clk);
                    
                    read_data = agu_rd_data;
                    test_data = 32'hB0 + i;
                    
                    if (read_data == test_data) begin
                        $display("Time %0t: [READ] PASS - addr=%0d, data=0x%h", $time, i, read_data);
                    end else begin
                        $display("Time %0t: [READ] FAIL - addr=%0d, expected=0x%h, got=0x%h", 
                                 $time, i, test_data, read_data);
                        errors = errors + 1;
                    end
                    
                    agu_rd_data_ready = 0;
                    #(CLK_PERIOD*2);
                end
            end
            
            // Thread 2: Write to Ping buffer (concurrent)
            begin
                #(CLK_PERIOD*2);
                for (i = 0; i < 5; i = i + 1) begin
                    agu_wr_addr = i;
                    agu_wr_data = 32'hC0 + i;  // Data: C0, C1, C2, C3, C4
                    agu_wr_valid = 1;
                    
                    @(posedge clk);
                    wait(agu_wr_ready);
                    $display("Time %0t: [WRITE] Wrote to Ping addr=%0d, data=0x%h", $time, i, agu_wr_data);
                    @(posedge clk);
                    agu_wr_valid = 0;
                    #(CLK_PERIOD);
                end
            end
        join
        
        #(CLK_PERIOD*5);
        
        //======================================================================
        // TEST 6: Verify Ping buffer data
        //======================================================================
        $display("\n--- TEST 6: Switch to Ping and verify ---");
        buffer_switch = 1;
        @(posedge clk);
        buffer_switch = 0;
        
        #(CLK_PERIOD*2);
        
        for (i = 0; i < 5; i = i + 1) begin
            agu_rd_addr = i;
            agu_rd_data_ready = 1;
            
            @(posedge clk);
            wait(agu_rd_data_valid);
            @(posedge clk);
            
            read_data = agu_rd_data;
            test_data = 32'hC0 + i;
            
            if (read_data == test_data) begin
                $display("Time %0t: PASS - Read addr=%0d, data=0x%h", $time, i, read_data);
            end else begin
                $display("Time %0t: FAIL - Read addr=%0d, expected=0x%h, got=0x%h", 
                         $time, i, test_data, read_data);
                errors = errors + 1;
            end
            
            agu_rd_data_ready = 0;
            #(CLK_PERIOD*2);
        end
        
        //======================================================================
        // TEST 7: Stress test - Multiple rapid concurrent operations
        //======================================================================
        $display("\n--- TEST 7: Stress test with rapid concurrent ops ---");
        buffer_switch = 1;
        @(posedge clk);
        buffer_switch = 0;
        #(CLK_PERIOD*2);
        
        fork
            // Rapid reads
            begin
                for (i = 0; i < 8; i = i + 1) begin
                    agu_rd_addr = i % 5;  // Cycle through 0-4
                    agu_rd_data_ready = 1;
                    
                    @(posedge clk);
                    wait(agu_rd_data_valid);
                    @(posedge clk);
                    
                    $display("Time %0t: [STRESS READ] addr=%0d, data=0x%h", $time, agu_rd_addr, agu_rd_data);
                    
                    agu_rd_data_ready = 0;
                    #(CLK_PERIOD);
                end
            end
            
            // Rapid writes
            begin
                #(CLK_PERIOD);
                for (i = 0; i < 8; i = i + 1) begin
                    agu_wr_addr = i % 5;
                    agu_wr_data = 32'hD0 + i;
                    agu_wr_valid = 1;
                    
                    @(posedge clk);
                    wait(agu_wr_ready);
                    $display("Time %0t: [STRESS WRITE] addr=%0d, data=0x%h", $time, agu_wr_addr, agu_wr_data);
                    @(posedge clk);
                    agu_wr_valid = 0;
                end
            end
        join
        
        //======================================================================
        // Test Summary
        //======================================================================
        #(CLK_PERIOD*10);
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        if (errors == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("TESTS FAILED - %0d errors", errors);
        end
        $display("========================================");
        
        $finish;
    end
    
    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        #100000; // 100us timeout
        $display("ERROR: Testbench timeout!");
        $finish;
    end

endmodule
