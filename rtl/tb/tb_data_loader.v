`timescale 1ns / 1ps

//==============================================================================
// Testbench for Data Loader Module
//==============================================================================
// Tests:
// 1. LOAD Mode: DRAM -> Memory Controller handshaking
// 2. UNLOAD Mode: Memory Controller -> DRAM with 3-cycle latency handling
// 3. AGU address stepping alignment
// 4. Back-pressure scenarios (tx_ready toggling)
//==============================================================================

module tb_data_loader;

    //==========================================================================
    // Testbench Signals
    //==========================================================================
    reg          clk;
    reg          rst_n;
    reg          is_loading;
    
    // External Interface (DRAM)
    reg  [31:0]  rx_data;
    reg          rx_valid;
    wire         rx_ready;
    wire [7:0]   tx_data;
    wire         tx_valid;
    reg          tx_ready;
    
    // AGU Interface
    reg  [7:0]   agu_addr;
    reg          agu_addr_valid;
    wire         agu_next_addr;
    
    // Memory Controller Interface - Write
    wire [31:0]  agu_wr_data;
    wire [7:0]   agu_wr_addr;
    wire         agu_wr_valid;
    reg          agu_wr_ready;
    
    // Memory Controller Interface - Read
    wire [7:0]   agu_rd_addr;
    wire         agu_rd_data_ready;
    reg  [31:0]  agu_rd_data;
    reg          agu_rd_data_valid;
    
    // Test tracking
    integer test_num;
    integer error_count;
    integer load_count;
    integer unload_count;
    
    //==========================================================================
    // DUT Instantiation
    //==========================================================================
    data_loader dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .is_loading         (is_loading),
        
        .rx_data            (rx_data),
        .rx_valid           (rx_valid),
        .rx_ready           (rx_ready),
        
        .tx_data            (tx_data),
        .tx_valid           (tx_valid),
        .tx_ready           (tx_ready),
        
        .agu_addr           (agu_addr),
        .agu_addr_valid     (agu_addr_valid),
        .agu_next_addr      (agu_next_addr),
        
        .agu_wr_data        (agu_wr_data),
        .agu_wr_addr        (agu_wr_addr),
        .agu_wr_valid       (agu_wr_valid),
        .agu_wr_ready       (agu_wr_ready),
        
        .agu_rd_addr        (agu_rd_addr),
        .agu_rd_data_ready  (agu_rd_data_ready),
        .agu_rd_data        (agu_rd_data),
        .agu_rd_data_valid  (agu_rd_data_valid)
    );
    
    //==========================================================================
    // Clock Generation
    //==========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz clock
    end
    
    //==========================================================================
    // Memory Controller Read Latency Simulator
    //==========================================================================
    // Simulates the 3-cycle read latency of the SRAM
    reg [2:0] read_delay_counter;
    reg       read_pending;
    reg [7:0] latched_rd_addr;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            agu_rd_data_valid   <= 1'b0;
            agu_rd_data         <= 32'd0;
            read_delay_counter  <= 3'd0;
            read_pending        <= 1'b0;
            latched_rd_addr     <= 8'd0;
        end else begin
            // When read request comes in
            if (agu_rd_data_ready && !read_pending && !agu_rd_data_valid) begin
                read_pending       <= 1'b1;
                read_delay_counter <= 3'd0;
                latched_rd_addr    <= agu_rd_addr;
                agu_rd_data_valid  <= 1'b0;
            end
            // Count delay cycles
            else if (read_pending) begin
                if (read_delay_counter < 3'd2) begin
                    read_delay_counter <= read_delay_counter + 1'b1;
                    agu_rd_data_valid  <= 1'b0;
                end else begin
                    // Data ready after 3 cycles
                    // Return address + 0x100 as test pattern
                    agu_rd_data        <= {24'd0, latched_rd_addr} + 32'h100;
                    agu_rd_data_valid  <= 1'b1;
                    read_pending       <= 1'b0;
                end
            end else begin
                agu_rd_data_valid <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // AGU Simulator
    //==========================================================================
    // Simulates AGU behavior: provides addresses and advances on next_addr
    reg [7:0] agu_counter;
    reg       agu_running;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            agu_addr       <= 8'd0;
            agu_addr_valid <= 1'b0;
            agu_counter    <= 8'd0;
            agu_running    <= 1'b0;
        end else begin
            // Start AGU when test begins
            if (!agu_running && (rx_valid || tx_ready)) begin
                agu_running    <= 1'b1;
                agu_addr       <= agu_counter;
                agu_addr_valid <= 1'b1;
            end
            // Advance on next_addr request
            else if (agu_next_addr && agu_addr_valid) begin
                agu_counter    <= agu_counter + 1'b1;
                agu_addr       <= agu_counter + 1'b1;
                agu_addr_valid <= 1'b0;  // Briefly invalidate
            end
            // Re-validate after one cycle (simulates AGU behavior)
            else if (!agu_addr_valid && agu_running) begin
                agu_addr_valid <= 1'b1;
            end
        end
    end
    
    //==========================================================================
    // Test Stimulus
    //==========================================================================
    initial begin
        // Initialize
        rst_n           = 0;
        is_loading      = 0;
        rx_data         = 32'd0;
        rx_valid        = 0;
        tx_ready        = 0;
        agu_wr_ready    = 1;
        test_num        = 0;
        error_count     = 0;
        load_count      = 0;
        unload_count    = 0;
        
        // Reset
        #20;
        rst_n = 1;
        #20;
        
        $display("================================================================================");
        $display("Data Loader Testbench Started");
        $display("================================================================================");
        
        //----------------------------------------------------------------------
        // TEST 1: LOAD Mode - Basic Handshaking
        //----------------------------------------------------------------------
        test_num = 1;
        $display("\n[TEST %0d] LOAD Mode - Basic Write Transaction", test_num);
        is_loading = 1;
        
        // Reset AGU simulator
        @(posedge clk);
        agu_running = 0;
        agu_counter = 8'd0;
        
        // Send 8 data words
        repeat (8) begin
            @(posedge clk);
            rx_data  = 32'h1000 + load_count;
            rx_valid = 1;
            
            // Wait for handshake
            wait (rx_ready && agu_wr_valid);
            @(posedge clk);
            
            // Check address alignment
            if (agu_wr_addr !== load_count) begin
                $display("ERROR: Address mismatch! Expected: %0d, Got: %0d", load_count, agu_wr_addr);
                error_count = error_count + 1;
            end
            if (agu_wr_data !== (32'h1000 + load_count)) begin
                $display("ERROR: Data mismatch! Expected: 0x%h, Got: 0x%h", 
                         32'h1000 + load_count, agu_wr_data);
                error_count = error_count + 1;
            end
            
            load_count = load_count + 1;
            rx_valid = 0;
            @(posedge clk);
        end
        
        $display("[TEST %0d] Loaded %0d words - PASSED", test_num, load_count);
        
        //----------------------------------------------------------------------
        // TEST 2: LOAD Mode - Back-pressure from Memory Controller
        //----------------------------------------------------------------------
        test_num = 2;
        $display("\n[TEST %0d] LOAD Mode - Memory Controller Back-pressure", test_num);
        
        @(posedge clk);
        agu_wr_ready = 0;  // Simulate full buffer
        rx_data  = 32'hDEAD;
        rx_valid = 1;
        
        repeat (5) @(posedge clk);
        
        if (agu_wr_valid || rx_ready) begin
            $display("ERROR: Transaction occurred when memory not ready!");
            error_count = error_count + 1;
        end
        
        // Release back-pressure
        agu_wr_ready = 1;
        @(posedge clk);
        wait (rx_ready);
        @(posedge clk);
        rx_valid = 0;
        
        $display("[TEST %0d] Back-pressure handled correctly - PASSED", test_num);
        
        //----------------------------------------------------------------------
        // TEST 3: UNLOAD Mode - Basic Read Transaction with 3-cycle latency
        //----------------------------------------------------------------------
        test_num = 3;
        $display("\n[TEST %0d] UNLOAD Mode - Read with 3-cycle SRAM latency", test_num);
        is_loading = 0;
        
        // Reset AGU simulator
        @(posedge clk);
        agu_running = 0;
        agu_counter = 8'd10;  // Start from address 10
        
        // Request first read
        @(posedge clk);
        tx_ready = 1;
        
        // Wait for FSM to request read
        wait (agu_rd_data_ready);
        $display("  [Cycle %0t] Read requested for address 0x%h", $time, agu_rd_addr);
        
        // Wait for data valid (3 cycles)
        wait (agu_rd_data_valid);
        $display("  [Cycle %0t] Data valid: 0x%h", $time, agu_rd_data);
        
        // Wait for output
        wait (tx_valid);
        $display("  [Cycle %0t] Output valid: 0x%h", $time, tx_data);
        
        // Check truncation (should be lower 8 bits of agu_rd_data)
        if (tx_data !== 8'h0A) begin  // addr 10 + 0x100 = 0x10A, truncate to 0x0A
            $display("ERROR: Truncation failed! Expected: 0x0A, Got: 0x%h", tx_data);
            error_count = error_count + 1;
        end
        
        // Handshake should request next address
        wait (agu_next_addr);
        $display("  [Cycle %0t] Next address requested", $time);
        
        @(posedge clk);
        tx_ready = 0;
        @(posedge clk);
        
        $display("[TEST %0d] UNLOAD with latency handling - PASSED", test_num);
        
        //----------------------------------------------------------------------
        // TEST 4: UNLOAD Mode - Multiple reads with continuous flow
        //----------------------------------------------------------------------
        test_num = 4;
        $display("\n[TEST %0d] UNLOAD Mode - Continuous read flow", test_num);
        
        // Reset AGU
        @(posedge clk);
        agu_running = 0;
        agu_counter = 8'd20;
        tx_ready = 1;
        
        // Read 8 consecutive values
        repeat (8) begin
            // Wait for output valid
            wait (tx_valid && tx_ready);
            $display("  [Cycle %0t] Addr=%0d, Data=0x%h", $time, agu_rd_addr, tx_data);
            unload_count = unload_count + 1;
            
            @(posedge clk);
            // Keep tx_ready high for continuous flow
        end
        
        tx_ready = 0;
        $display("[TEST %0d] Read %0d consecutive values - PASSED", test_num, unload_count);
        
        //----------------------------------------------------------------------
        // TEST 5: UNLOAD Mode - Back-pressure from external interface
        //----------------------------------------------------------------------
        test_num = 5;
        $display("\n[TEST %0d] UNLOAD Mode - External back-pressure", test_num);
        
        @(posedge clk);
        agu_running = 0;
        agu_counter = 8'd50;
        tx_ready = 1;
        
        // Wait for first data
        wait (tx_valid);
        $display("  [Cycle %0t] First data ready", $time);
        
        // Remove tx_ready to simulate back-pressure
        @(posedge clk);
        tx_ready = 0;
        
        // Data should stay valid
        repeat (5) begin
            @(posedge clk);
            if (!tx_valid) begin
                $display("ERROR: tx_valid dropped during back-pressure!");
                error_count = error_count + 1;
            end
        end
        
        // Release back-pressure
        tx_ready = 1;
        wait (agu_next_addr);
        $display("  [Cycle %0t] Back-pressure released, next address requested", $time);
        
        @(posedge clk);
        tx_ready = 0;
        
        $display("[TEST %0d] Back-pressure handling - PASSED", test_num);
        
        //----------------------------------------------------------------------
        // TEST 6: UNLOAD Mode - Saturation logic test
        //----------------------------------------------------------------------
        test_num = 6;
        $display("\n[TEST %0d] UNLOAD Mode - Saturation to 0xFF", test_num);
        
        // Override the memory controller simulator to return large value
        @(posedge clk);
        agu_running = 0;
        agu_counter = 8'd60;
        tx_ready = 1;
        
        // Wait for read request
        wait (agu_rd_data_ready);
        
        // Inject large value
        repeat (3) @(posedge clk);
        agu_rd_data = 32'h12345678;  // Should saturate to 0xFF
        agu_rd_data_valid = 1;
        @(posedge clk);
        agu_rd_data_valid = 0;
        
        // Wait for output
        wait (tx_valid);
        if (tx_data !== 8'hFF) begin
            $display("ERROR: Saturation failed! Expected: 0xFF, Got: 0x%h", tx_data);
            error_count = error_count + 1;
        end else begin
            $display("  Saturation correct: 0x%h -> 0xFF", agu_rd_data);
        end
        
        @(posedge clk);
        tx_ready = 0;
        
        $display("[TEST %0d] Saturation logic - PASSED", test_num);
        
        //----------------------------------------------------------------------
        // Test Summary
        //----------------------------------------------------------------------
        #100;
        $display("\n================================================================================");
        $display("Test Summary");
        $display("================================================================================");
        $display("Tests Run:    %0d", test_num);
        $display("Errors:       %0d", error_count);
        $display("Load Ops:     %0d", load_count);
        $display("Unload Ops:   %0d", unload_count);
        
        if (error_count == 0) begin
            $display("\n*** ALL TESTS PASSED ***");
        end else begin
            $display("\n*** %0d TESTS FAILED ***", error_count);
        end
        $display("================================================================================\n");
        
        $finish;
    end
    
    //==========================================================================
    // Timeout Watchdog
    //==========================================================================
    initial begin
        #100000;  // 100us timeout
        $display("\n*** ERROR: Testbench timeout! ***");
        $finish;
    end
    
    //==========================================================================
    // Optional Waveform Dump
    //==========================================================================
    initial begin
        $dumpfile("tb_data_loader.vcd");
        $dumpvars(0, tb_data_loader);
    end

endmodule
