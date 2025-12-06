/*
 * DRAM Module - External Memory Interface
 * 
 * This module simulates external DRAM for the systolic array accelerator.
 * It provides a streaming interface with valid/ready handshake for data transfer.
 * 
 * Features:
 * - Configurable bus width (8-32 bits)
 * - Valid/Ready handshake protocol
 * - Separate RX (accelerator reads from DRAM) and TX (accelerator writes to DRAM) streams
 * - Storage for input matrix, kernel, and output results
 * - File-based initialization for verification
 */

module dram #(
    parameter DATA_WIDTH = 32,           // External bus width: 8, 16, or 32 bits
    parameter ADDR_WIDTH = 20,           // Address space: 1MB addressable
    parameter INPUT_SIZE = 64*64,        // Max input matrix size (64x64)
    parameter KERNEL_SIZE = 16*16,       // Max kernel size (16x16)
    parameter OUTPUT_SIZE = 64*64,       // Max output size
    parameter INPUT_FILE = "input_matrix.txt",
    parameter KERNEL_FILE = "kernel.txt",
    parameter OUTPUT_FILE = "results_hw.txt"
) (
    input wire clk,
    input wire rst_n,
    
    // RX Stream Interface (DRAM → Accelerator)
    output reg [DATA_WIDTH-1:0] rx_data,
    output reg rx_valid,
    input wire rx_ready,
    
    // TX Stream Interface (Accelerator → DRAM)
    input wire [DATA_WIDTH-1:0] tx_data,
    input wire tx_valid,
    output reg tx_ready,
    
    // Control Interface
    input wire [ADDR_WIDTH-1:0] read_addr,      // Address to read from
    input wire read_enable,                      // Start read transaction
    input wire [ADDR_WIDTH-1:0] write_addr,     // Address to write to
    input wire write_enable,                     // Start write transaction
    input wire [15:0] transfer_length,           // Number of transfers
    
    // Status
    output reg read_complete,
    output reg write_complete,
    output reg dram_busy
);

    // Memory organization
    localparam MEM_DEPTH = 1 << ADDR_WIDTH;
    localparam BYTES_PER_WORD = DATA_WIDTH / 8;
    
    // Memory arrays (byte-addressable)
    reg [7:0] memory [0:MEM_DEPTH-1];
    
    // Internal state machine
    localparam IDLE = 2'b00;
    localparam READ = 2'b01;
    localparam WRITE = 2'b10;
    
    reg [1:0] state;
    reg [ADDR_WIDTH-1:0] current_addr;
    reg [15:0] transfer_count;
    reg [15:0] transfers_remaining;
    
    // Initialize memory from files
    integer i;
    initial begin
        // Initialize all memory to zero
        for (i = 0; i < MEM_DEPTH; i = i + 1) begin
            memory[i] = 8'h00;
        end
        
        // Load input matrix if file exists
        if (INPUT_FILE != "") begin
            $readmemh(INPUT_FILE, memory, 0);
        end
        
        // Load kernel if file exists (at offset)
        if (KERNEL_FILE != "") begin
            $readmemh(KERNEL_FILE, memory, INPUT_SIZE);
        end
    end
    
    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            rx_data <= {DATA_WIDTH{1'b0}};
            rx_valid <= 1'b0;
            tx_ready <= 1'b0;
            read_complete <= 1'b0;
            write_complete <= 1'b0;
            dram_busy <= 1'b0;
            current_addr <= {ADDR_WIDTH{1'b0}};
            transfer_count <= 16'h0;
            transfers_remaining <= 16'h0;
        end else begin
            // Clear single-cycle flags
            read_complete <= 1'b0;
            write_complete <= 1'b0;
            
            case (state)
                IDLE: begin
                    dram_busy <= 1'b0;
                    rx_valid <= 1'b0;
                    tx_ready <= 1'b0;
                    
                    if (read_enable) begin
                        // Start read transaction
                        state <= READ;
                        current_addr <= read_addr;
                        transfer_count <= transfer_length;
                        transfers_remaining <= transfer_length;
                        dram_busy <= 1'b1;
                        rx_valid <= 1'b0;  // Will be set in READ state
                    end else if (write_enable) begin
                        // Start write transaction
                        state <= WRITE;
                        current_addr <= write_addr;
                        transfer_count <= transfer_length;
                        transfers_remaining <= transfer_length;
                        dram_busy <= 1'b1;
                        tx_ready <= 1'b1;  // Ready to accept data
                    end
                end
                
                READ: begin
                    // Read data from memory and stream to accelerator
                    if (transfers_remaining > 0) begin
                        // Only load/advance when previous data was accepted or no valid data yet
                        if (!rx_valid) begin
                            // Load next data word from memory
                            case (DATA_WIDTH)
                                8: begin
                                    rx_data <= memory[current_addr];
                                end
                                16: begin
                                    rx_data <= {memory[current_addr+1], memory[current_addr]};
                                end
                                32: begin
                                    rx_data <= {memory[current_addr+3], memory[current_addr+2], 
                                               memory[current_addr+1], memory[current_addr]};
                                end
                                default: begin
                                    rx_data <= memory[current_addr];
                                end
                            endcase
                            rx_valid <= 1'b1;
                        end else if (rx_ready) begin
                            // Handshake complete - advance and load next
                            current_addr <= current_addr + BYTES_PER_WORD;
                            transfers_remaining <= transfers_remaining - 1;
                            
                            // If more data remaining, load next word immediately
                            if (transfers_remaining > 1) begin
                                case (DATA_WIDTH)
                                    8: begin
                                        rx_data <= memory[current_addr + BYTES_PER_WORD];
                                    end
                                    16: begin
                                        rx_data <= {memory[current_addr + BYTES_PER_WORD + 1], 
                                                   memory[current_addr + BYTES_PER_WORD]};
                                    end
                                    32: begin
                                        rx_data <= {memory[current_addr + BYTES_PER_WORD + 3], 
                                                   memory[current_addr + BYTES_PER_WORD + 2], 
                                                   memory[current_addr + BYTES_PER_WORD + 1], 
                                                   memory[current_addr + BYTES_PER_WORD]};
                                    end
                                    default: begin
                                        rx_data <= memory[current_addr + BYTES_PER_WORD];
                                    end
                                endcase
                                rx_valid <= 1'b1;
                            end else begin
                                rx_valid <= 1'b0;
                            end
                        end
                        // else: rx_valid && !rx_ready -> backpressure, hold current data
                    end else begin
                        // Read transaction complete
                        rx_valid <= 1'b0;
                        read_complete <= 1'b1;
                        state <= IDLE;
                    end
                end
                
                WRITE: begin
                    // Receive data from accelerator and write to memory
                    tx_ready <= 1'b1;
                    
                    if (transfers_remaining > 0) begin
                        if (tx_valid && tx_ready) begin
                            // Write data to memory
                            case (DATA_WIDTH)
                                8: begin
                                    memory[current_addr] <= tx_data[7:0];
                                end
                                16: begin
                                    memory[current_addr] <= tx_data[7:0];
                                    memory[current_addr+1] <= tx_data[15:8];
                                end
                                32: begin
                                    memory[current_addr] <= tx_data[7:0];
                                    memory[current_addr+1] <= tx_data[15:8];
                                    memory[current_addr+2] <= tx_data[23:16];
                                    memory[current_addr+3] <= tx_data[31:24];
                                end
                            endcase
                            
                            current_addr <= current_addr + BYTES_PER_WORD;
                            transfers_remaining <= transfers_remaining - 1;
                        end
                    end else begin
                        // Write transaction complete
                        tx_ready <= 1'b0;
                        write_complete <= 1'b1;
                        state <= IDLE;
                    end
                end
                
                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
    
    // Task to dump memory contents to file (for verification)
    task dump_memory;
        input [ADDR_WIDTH-1:0] start_addr;
        input [ADDR_WIDTH-1:0] end_addr;
        input [256*8-1:0] filename;  // String for filename
        integer file_handle;
        integer addr;
        begin
            file_handle = $fopen(filename, "w");
            if (file_handle) begin
                for (addr = start_addr; addr <= end_addr; addr = addr + 1) begin
                    $fwrite(file_handle, "%02h\n", memory[addr]);
                end
                $fclose(file_handle);
                $display("[DRAM] Memory dumped to %s (0x%h to 0x%h)", filename, start_addr, end_addr);
            end else begin
                $display("[DRAM] Error: Could not open file %s", filename);
            end
        end
    endtask
    
    // Task to write results to file
    task write_results;
        input [256*8-1:0] filename;
        integer file_handle;
        integer addr;
        begin
            file_handle = $fopen(filename, "w");
            if (file_handle) begin
                // Write output data (assuming it starts at OUTPUT_SIZE offset)
                for (addr = 0; addr < OUTPUT_SIZE * BYTES_PER_WORD; addr = addr + BYTES_PER_WORD) begin
                    case (DATA_WIDTH)
                        8: begin
                            $fwrite(file_handle, "%02h\n", memory[INPUT_SIZE + KERNEL_SIZE + addr]);
                        end
                        16: begin
                            $fwrite(file_handle, "%04h\n", 
                                {memory[INPUT_SIZE + KERNEL_SIZE + addr + 1], 
                                 memory[INPUT_SIZE + KERNEL_SIZE + addr]});
                        end
                        32: begin
                            $fwrite(file_handle, "%08h\n", 
                                {memory[INPUT_SIZE + KERNEL_SIZE + addr + 3],
                                 memory[INPUT_SIZE + KERNEL_SIZE + addr + 2],
                                 memory[INPUT_SIZE + KERNEL_SIZE + addr + 1],
                                 memory[INPUT_SIZE + KERNEL_SIZE + addr]});
                        end
                    endcase
                end
                $fclose(file_handle);
                $display("[DRAM] Results written to %s", filename);
            end else begin
                $display("[DRAM] Error: Could not open file %s", filename);
            end
        end
    endtask
    
    // Debug: Monitor DRAM transactions
    always @(posedge clk) begin
        if (rx_valid && rx_ready) begin
            $display("[DRAM] READ: addr=0x%h, data=0x%h, remaining=%d", 
                     current_addr, rx_data, transfers_remaining);
        end
        if (tx_valid && tx_ready) begin
            $display("[DRAM] WRITE: addr=0x%h, data=0x%h, remaining=%d", 
                     current_addr, tx_data, transfers_remaining);
        end
    end

endmodule
