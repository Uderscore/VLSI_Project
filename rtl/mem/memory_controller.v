// Memory Controller with Ping-Pong Buffering for Systolic Array Accelerator
// Uses Sky130 1KB SRAM (1rw1r - Pseudo Dual Port) for efficient data management
// 
// This module implements a ping-pong buffer scheme to enable continuous data flow:
// - While one buffer is being read by the systolic array, the other can be written
// - Supports concurrent read and write operations through dual-port SRAM
// - Manages automatic buffer switching when a buffer is exhausted
//
// Memory Organization:
// - 2x SRAM blocks (1KB each) for ping-pong buffering
// - Each SRAM: 256 words x 32 bits
// - Supports up to 2KB total buffered data

module memory_controller #(
    parameter DATA_WIDTH = 32,      // Width of data bus to/from systolic array
    parameter ADDR_WIDTH = 8,       // Address width for SRAM (256 locations)
    parameter ARRAY_SIZE = 8        // Size of systolic array (8x8)
)(
    // System signals
    input  wire                     clk,
    input  wire                     rst_n,
    
    // Control signals
    input  wire                     start,          // Start memory operations
    input  wire                     buffer_switch,  // Request buffer switch
    output reg                      ping_active,    // Indicates which buffer is active for reading
    output reg                      ready,          // Controller is ready for new data
    
    // Write interface from AGU (AGU → SRAM)
    input  wire                     agu_wr_valid,   // AGU has valid data to write
    output reg                      agu_wr_ready,   // SRAM ready to accept write
    input  wire [DATA_WIDTH-1:0]    agu_wr_data,
    input  wire [ADDR_WIDTH-1:0]    agu_wr_addr,
    output wire                     wr_buffer_full, // Current write buffer is full
    
    // Read interface to AGU (SRAM → AGU)
    input  wire                     agu_rd_data_ready,  // AGU ready to accept data
    output reg                      agu_rd_data_valid,  // SRAM has valid data
    input  wire [ADDR_WIDTH-1:0]    agu_rd_addr,
    output reg  [DATA_WIDTH-1:0]    agu_rd_data,
    
    // Write interface from Systolic Array (SA → SRAM)
    input  wire                     sa_wr_valid,    // SA has valid data to write
    output reg                      sa_wr_ready,    // SRAM ready to accept write
    input  wire [DATA_WIDTH-1:0]    sa_wr_data,
    input  wire [ADDR_WIDTH-1:0]    sa_wr_addr,
    
    // Read interface to Systolic Array (SRAM → SA)
    input  wire                     sa_rd_data_ready,   // SA ready to accept data
    output reg                      sa_rd_data_valid,   // SRAM has valid data
    input  wire [ADDR_WIDTH-1:0]    sa_rd_addr,
    output reg  [DATA_WIDTH-1:0]    sa_rd_data,
    
    output wire                     rd_buffer_empty // Current read buffer is empty
);

    // Ping-Pong buffer state
    reg ping_write_active;          // Ping buffer is being written
    reg [ADDR_WIDTH-1:0] ping_wr_count;
    reg [ADDR_WIDTH-1:0] pong_wr_count;
    
    // SRAM Interface signals for Ping Buffer
    wire        ping_clk0, ping_csb0, ping_web0;
    wire [3:0]  ping_wmask0;
    wire [ADDR_WIDTH-1:0] ping_addr0;
    wire [DATA_WIDTH-1:0] ping_din0, ping_dout0;
    wire        ping_clk1, ping_csb1;
    wire [ADDR_WIDTH-1:0] ping_addr1;
    wire [DATA_WIDTH-1:0] ping_dout1;
    
    // SRAM Interface signals for Pong Buffer
    wire        pong_clk0, pong_csb0, pong_web0;
    wire [3:0]  pong_wmask0;
    wire [ADDR_WIDTH-1:0] pong_addr0;
    wire [DATA_WIDTH-1:0] pong_din0, pong_dout0;
    wire        pong_clk1, pong_csb1;
    wire [ADDR_WIDTH-1:0] pong_addr1;
    wire [DATA_WIDTH-1:0] pong_dout1;

    // Buffer status for DRAM
    assign wr_buffer_full = ping_write_active ? 
                           (ping_wr_count >= 8'd255) : 
                           (pong_wr_count >= 8'd255);
    
    assign rd_buffer_empty = ping_active ? 
                            (ping_wr_count == 0) : 
                            (pong_wr_count == 0);

    //==========================================================================
    // Ping Buffer SRAM Instance
    //==========================================================================
    // Port 0: Read/Write operations (RW)
    // Port 1: Read-only operations (R)
    
    // Write can come from AGU or Systolic Array
    wire wr_en_internal = (agu_wr_valid && agu_wr_ready) || (sa_wr_valid && sa_wr_ready);
    wire [ADDR_WIDTH-1:0] wr_addr_internal = (agu_wr_valid && agu_wr_ready) ? agu_wr_addr : sa_wr_addr;
    wire [DATA_WIDTH-1:0] wr_data_internal = (agu_wr_valid && agu_wr_ready) ? agu_wr_data : sa_wr_data;
    
    // Read can go to AGU or Systolic Array
    // Use Port 0 for AGU reads, Port 1 for SA reads (simultaneous)
    wire agu_rd_req = agu_rd_data_ready && !rd_buffer_empty;  // AGU requests read
    wire sa_rd_req = sa_rd_data_ready && !rd_buffer_empty;    // SA requests read
    
    // Port 0 (RW): Used for writes and AGU reads
    assign ping_clk0 = clk;
    assign ping_csb0 = !((wr_en_internal && ping_write_active) || (agu_rd_req && ping_active));  // Active for write OR AGU read request
    assign ping_web0 = !(wr_en_internal && ping_write_active);  // web0=0 for write, web0=1 for read
    assign ping_wmask0 = 4'b1111;                       // Enable all bytes
    assign ping_addr0 = (wr_en_internal && ping_write_active) ? wr_addr_internal : agu_rd_addr;  // Write addr or AGU read addr
    assign ping_din0 = wr_data_internal;
    
    // Port 1 (Read-Only): Used for SA reads
    assign ping_clk1 = clk;
    assign ping_csb1 = !(sa_rd_req && ping_active);        // Active for SA read requests
    assign ping_addr1 = sa_rd_addr;  // SA read address
    
    sky130_sram_1kbyte_1rw1r_32x256_8 ping_sram (
        .clk0   (ping_clk0),
        .csb0   (ping_csb0),
        .web0   (ping_web0),
        .wmask0 (ping_wmask0),
        .addr0  (ping_addr0),
        .din0   (ping_din0),
        .dout0  (ping_dout0),
        .clk1   (ping_clk1),
        .csb1   (ping_csb1),
        .addr1  (ping_addr1),
        .dout1  (ping_dout1)
    );

    //==========================================================================
    // Pong Buffer SRAM Instance
    //==========================================================================
    // Port 0: Read/Write operations (RW)
    // Port 1: Read-only operations (R)
    
    // Port 0 (RW): Used for writes and AGU reads
    assign pong_clk0 = clk;
    assign pong_csb0 = !((wr_en_internal && !ping_write_active) || (agu_rd_req && !ping_active)); // Active for write OR AGU read request
    assign pong_web0 = !(wr_en_internal && !ping_write_active); // web0=0 for write, web0=1 for read
    assign pong_wmask0 = 4'b1111;                       // Enable all bytes
    assign pong_addr0 = (wr_en_internal && !ping_write_active) ? wr_addr_internal : agu_rd_addr;  // Write addr or AGU read addr
    assign pong_din0 = wr_data_internal;
    
    // Port 1 (Read-Only): Used for SA reads
    assign pong_clk1 = clk;
    assign pong_csb1 = !(sa_rd_req && !ping_active);       // Active for SA read requests
    assign pong_addr1 = sa_rd_addr;  // SA read address
    
    sky130_sram_1kbyte_1rw1r_32x256_8 pong_sram (
        .clk0   (pong_clk0),
        .csb0   (pong_csb0),
        .web0   (pong_web0),
        .wmask0 (pong_wmask0),
        .addr0  (pong_addr0),
        .din0   (pong_din0),
        .dout0  (pong_dout0),
        .clk1   (pong_clk1),
        .csb1   (pong_csb1),
        .addr1  (pong_addr1),
        .dout1  (pong_dout1)
    );

    //==========================================================================
    // Read Data Multiplexer
    //==========================================================================
    // Port 0 (dout0) -> AGU reads
    // Port 1 (dout1) -> SA reads
    // Select from ping or pong buffer based on ping_active
    
    always @(*) begin
        // AGU reads from Port 0 (dout0)
        if (ping_active)
            agu_rd_data = ping_dout0;  // AGU reads from Ping Port 0
        else
            agu_rd_data = pong_dout0;  // AGU reads from Pong Port 0
        
        // SA reads from Port 1 (dout1)
        if (ping_active)
            sa_rd_data = ping_dout1;   // SA reads from Ping Port 1
        else
            sa_rd_data = pong_dout1;   // SA reads from Pong Port 1
    end

    //==========================================================================
    // Handshaking Logic for 4-way Data Transfer
    //==========================================================================
    // Path 1: AGU → SRAM (Write)
    // Path 2: SRAM → AGU (Read)
    // Path 3: SA → SRAM (Write) 
    // Path 4: SRAM → SA (Read)
    
    reg [2:0] agu_rd_delay_count;  // 3-cycle read delay for SRAM
    reg [2:0] sa_rd_delay_count;   // 3-cycle read delay for SRAM
    reg agu_rd_pending;            // AGU read in progress
    reg sa_rd_pending;             // SA read in progress
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            agu_wr_ready <= 1'b0;
            agu_rd_data_valid <= 1'b0;
            sa_wr_ready <= 1'b0;
            sa_rd_data_valid <= 1'b0;
            agu_rd_delay_count <= 3'd0;
            sa_rd_delay_count <= 3'd0;
            agu_rd_pending <= 1'b0;
            sa_rd_pending <= 1'b0;
        end
        else begin
            // Path 1: AGU Write Ready - SRAM ready when buffer not full and no SA write conflict
            agu_wr_ready <= !wr_buffer_full && !sa_wr_valid;
            
            // Path 3: SA Write Ready - SRAM ready when buffer not full and no AGU write conflict
            sa_wr_ready <= !wr_buffer_full && !agu_wr_valid;
            
            // Path 2: AGU Read Data Valid - Account for 3-cycle SRAM read latency
            if (!agu_rd_pending && agu_rd_data_ready && !rd_buffer_empty) begin
                // Start new read request
                agu_rd_pending <= 1'b1;
                agu_rd_delay_count <= 3'd0;
                agu_rd_data_valid <= 1'b0;
            end else if (agu_rd_pending) begin
                // Continue counting delay for ongoing read
                if (agu_rd_delay_count < 3'd2) begin
                    agu_rd_delay_count <= agu_rd_delay_count + 1'b1;
                    agu_rd_data_valid <= 1'b0;
                end else begin
                    // Data is valid after 3 cycles
                    agu_rd_data_valid <= 1'b1;
                    agu_rd_pending <= 1'b0;  // Complete this read
                end
            end else begin
                agu_rd_data_valid <= 1'b0;
            end
            
            // Path 4: SA Read Data Valid - Account for 3-cycle SRAM read latency
            if (!sa_rd_pending && sa_rd_data_ready && !rd_buffer_empty) begin
                // Start new read request
                sa_rd_pending <= 1'b1;
                sa_rd_delay_count <= 3'd0;
                sa_rd_data_valid <= 1'b0;
            end else if (sa_rd_pending) begin
                // Continue counting delay for ongoing read
                if (sa_rd_delay_count < 3'd2) begin
                    sa_rd_delay_count <= sa_rd_delay_count + 1'b1;
                    sa_rd_data_valid <= 1'b0;
                end else begin
                    // Data is valid after 3 cycles
                    sa_rd_data_valid <= 1'b1;
                    sa_rd_pending <= 1'b0;  // Complete this read
                end
            end else begin
                sa_rd_data_valid <= 1'b0;
            end
        end
    end
    
    //==========================================================================
    // Ping-Pong Buffer Control Logic
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ping_write_active <= 1'b1;      // Start with Ping buffer for writing
            ping_active <= 1'b0;            // Start with Pong buffer for reading
            ping_wr_count <= 8'd0;
            pong_wr_count <= 8'd0;
            ready <= 1'b0;
        end
        else begin
            if (start) begin // data is valid
                ready <= 1'b1;
            end
            
            // Track write counts for each buffer (from AGU or SA)
            if (wr_en_internal && ping_write_active && !wr_buffer_full) begin
                ping_wr_count <= ping_wr_count + 1'b1;
            end
            
            if (wr_en_internal && !ping_write_active && !wr_buffer_full) begin
                pong_wr_count <= pong_wr_count + 1'b1;
            end
            
            // Buffer switching logic
            if (buffer_switch && ready) begin
                // Swap read buffer
                ping_active <= ~ping_active;
                
                // Swap write buffer
                ping_write_active <= ~ping_write_active;
                
                // Reset the counter of the buffer that was just read from
                // (it's now available for writing)
                if (ping_active)
                    ping_wr_count <= 8'd0;
                else
                    pong_wr_count <= 8'd0;
            end
        end
    end

    //==========================================================================
    // Debug & Monitoring (optional, can be disabled in synthesis)
    //==========================================================================
    `ifdef SIMULATION
    always @(posedge clk) begin
        // Monitor handshaking transactions
        if (agu_wr_valid && agu_wr_ready) begin
            $display("Time %0t: AGU→SRAM Write: addr=0x%h, data=0x%h", $time, agu_wr_addr, agu_wr_data);
        end
        if (agu_rd_data_ready && agu_rd_data_valid) begin
            $display("Time %0t: SRAM→AGU Read: addr=0x%h, data=0x%h", $time, agu_rd_addr, agu_rd_data);
        end
        if (sa_wr_valid && sa_wr_ready) begin
            $display("Time %0t: SA→SRAM Write: addr=0x%h, data=0x%h", $time, sa_wr_addr, sa_wr_data);
        end
        if (sa_rd_data_ready && sa_rd_data_valid) begin
            $display("Time %0t: SRAM→SA Read: addr=0x%h, data=0x%h", $time, sa_rd_addr, sa_rd_data);
        end
        
        if (buffer_switch && ready) begin
            $display("Time %0t: Buffer Switch - Now Reading from %s, Writing to %s",
                     $time, 
                     ping_active ? "Pong" : "Ping",
                     ping_write_active ? "Pong" : "Ping");
        end
        
        if (wr_buffer_full) begin
            $display("Time %0t: WARNING - Write buffer full!", $time);
        end
        
        if (rd_buffer_empty) begin
            $display("Time %0t: WARNING - Read buffer empty!", $time);
        end
    end
    `endif

endmodule
