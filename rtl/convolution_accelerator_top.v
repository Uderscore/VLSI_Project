//==============================================================================
// Convolution Accelerator - Clean Implementation
//==============================================================================
`timescale 1ns / 1ps

module convolution_accelerator_top #(
    parameter DATA_WIDTH    = 8,
    parameter PSUM_WIDTH    = 32,
    parameter MEM_WIDTH     = 32,
    parameter ADDR_WIDTH    = 8,
    parameter ARRAY_SIZE    = 8,
    parameter MAX_IMG_SIZE  = 64
)(
    input  wire                     clk,
    input  wire                     rst_n,
    
    input  wire                     start,
    input  wire [6:0]               cfg_N,
    input  wire [4:0]               cfg_K,  // 5-bit to support K=16
    output reg                      done,
    output wire                     busy,
    
    input  wire [DATA_WIDTH-1:0]    rx_data,
    input  wire                     rx_valid,
    output reg                      rx_ready,
    
    output reg  [DATA_WIDTH-1:0]    tx_data,
    output reg                      tx_valid,
    input  wire                     tx_ready,
    
    output wire [3:0]               current_state,
    output wire                     sa_active,
    output wire                     loading_data,
    output wire                     draining_results
);

    //==========================================================================
    // FSM States
    //==========================================================================
    localparam S_IDLE        = 4'd0;
    localparam S_LOAD_INPUT  = 4'd1;
    localparam S_LOAD_WEIGHT = 4'd2;
    localparam S_COMPUTE     = 4'd3;
    localparam S_DRAIN       = 4'd4;
    localparam S_DONE        = 4'd5;
    localparam S_TURN_AROUND = 4'd6;
    
    reg [3:0] state, next_state;

    //==========================================================================
    // Configuration
    //==========================================================================
    reg [6:0]  N_reg;
    reg [4:0]  K_reg;  // Extended to 5-bit for safety
    reg [12:0] input_count;  // Expanded to 13-bit for N=64 (4096)
    reg [8:0]  kernel_count; 
    reg [12:0] output_count; // Expanded to 13-bit
    reg [6:0]  out_size;
    
    //==========================================================================
    // Counters - Use 13-bit for wider range
    //==========================================================================
    reg [12:0] load_counter;
    reg [8:0]  weight_counter;  
    reg [12:0] drain_counter;
    reg [11:0] out_x, out_y;     // 12-bit to prevent overflow in address calc
    reg [4:0]  kx, ky;
    reg        compute_done;
    
    // 8 Parallel Accumulators (one per PE)
    reg [PSUM_WIDTH-1:0] acc [0:7];
    integer p;  // Loop variable for parallel operations
    
    //==========================================================================
    // Memory
    //==========================================================================
    reg [DATA_WIDTH-1:0] input_mem  [0:4095];
    reg [DATA_WIDTH-1:0] kernel_mem [0:255];
    reg [DATA_WIDTH-1:0] output_mem [0:4095];
    
    //==========================================================================
    // Wider intermediates for address calculation
    //==========================================================================
    wire [11:0] out_size_12 = {5'b0, out_size};
    wire [11:0] N_reg_12 = {5'b0, N_reg};
    wire [11:0] output_addr = out_y * out_size_12 + out_x;
    wire [11:0] input_addr = (out_y + ky) * N_reg_12 + (out_x + kx);
    wire [7:0]  kernel_addr = ky * K_reg + kx;

    //==========================================================================
    // Debug signals
    //==========================================================================
    assign current_state = state;
    assign busy = (state != S_IDLE) && (state != S_DONE);
    assign sa_active = (state == S_COMPUTE);
    assign loading_data = (state == S_LOAD_INPUT) || (state == S_LOAD_WEIGHT); // Turnaround is not loading
    assign draining_results = (state == S_DRAIN);
    
    //==========================================================================
    // State Machine
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end else begin
            state <= next_state;
            if (state != next_state) begin
                $display("[RTL DEBUG] Time=%0t State Transition: %0d -> %0d", $time, state, next_state);
                $display("[RTL DEBUG] Counters: Load=%0d/%0d, Weight=%0d/%0d", 
                         load_counter, input_count, weight_counter, kernel_count);
            end
        end
    end
    
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE:
                if (start && rx_valid)
                    next_state = S_LOAD_INPUT;
            
            S_LOAD_INPUT:
                if (load_counter >= input_count)
                    next_state = S_TURN_AROUND; // Go to turnaround instead of direct to weights
            
            S_TURN_AROUND:
                next_state = S_LOAD_WEIGHT;
            
            S_LOAD_WEIGHT:
                if (weight_counter >= kernel_count)
                    next_state = S_COMPUTE;
            
            S_COMPUTE:
                if (compute_done)
                    next_state = S_DRAIN;
            
            S_DRAIN:
                if (drain_counter >= output_count)
                    next_state = S_DONE;
            
            S_DONE:
                next_state = S_IDLE;
            
            default: next_state = S_IDLE;
        endcase
    end
    
    //==========================================================================
    // Ready Signal Generation (Combinational)
    //==========================================================================
    always @(*) begin
        rx_ready = 0;
        case (state)
            S_IDLE:        rx_ready = 1;
            S_LOAD_INPUT:  rx_ready = (load_counter < input_count);
            S_LOAD_WEIGHT: rx_ready = (weight_counter < kernel_count);
            default:       rx_ready = 0;
        endcase
    end

    //==========================================================================
    // Main Logic
    //==========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            N_reg <= 0;
            K_reg <= 0;
            input_count <= 0;
            kernel_count <= 0;
            output_count <= 0;
            out_size <= 0;
            load_counter <= 0;
            weight_counter <= 0;
            drain_counter <= 0;
            out_x <= 0;
            out_y <= 0;
            kx <= 0;
            ky <= 0;
            // Reset all 8 accumulators
            acc[0] <= 0; acc[1] <= 0; acc[2] <= 0; acc[3] <= 0;
            acc[4] <= 0; acc[5] <= 0; acc[6] <= 0; acc[7] <= 0;
            compute_done <= 0;
            done <= 0;
            // rx_ready removed (combinational)
            tx_data <= 0;
            tx_valid <= 0;
        end else begin
            // rx_ready removed (combinational)
            tx_valid <= 0;
            done <= 0;
            
            case (state)
                //--------------------------------------------------------------
                S_IDLE: begin
                    compute_done <= 0;
                    if (start && rx_valid) begin
                        N_reg <= cfg_N;
                        K_reg <= cfg_K;
                        // Use explicit width extension to avoid overflow (64*64=4096 needs 12 bits)
                        input_count <= {5'b0, cfg_N} * {5'b0, cfg_N};
                        kernel_count <= cfg_K * cfg_K;  // Max 16*16=256, fits in 8 bits
                        out_size <= cfg_N - cfg_K + 1;
                        output_count <= ({5'b0, cfg_N} - {8'b0, cfg_K} + 1) * ({5'b0, cfg_N} - {8'b0, cfg_K} + 1);
                        load_counter <= 0;
                        weight_counter <= 0;
                        drain_counter <= 0;
                        out_x <= 0;
                        out_y <= 0;
                        kx <= 0;
                        ky <= 0;
                        // Reset all 8 accumulators
                        for (p = 0; p < 8; p = p + 1)
                            acc[p] <= 0;
                    end
                end
                
                //--------------------------------------------------------------
                S_LOAD_INPUT: begin
                    if (rx_valid && load_counter < input_count) begin
                        input_mem[load_counter] <= rx_data;
                        load_counter <= load_counter + 1;
                    end
                end

                //--------------------------------------------------------------
                S_TURN_AROUND: begin
                    // No action, rx_ready is 0 by combinational default
                end
                
                //--------------------------------------------------------------
                S_LOAD_WEIGHT: begin
                    if (rx_valid && weight_counter < kernel_count) begin
                        kernel_mem[weight_counter] <= rx_data;
                        //$display("DEBUG LOAD_WEIGHT[%0d] = %0d", weight_counter, rx_data);
                        weight_counter <= weight_counter + 1;
                    end
                end
                
                //--------------------------------------------------------------
                S_COMPUTE: begin
                    if (!compute_done) begin
                        // Perform 8 MACs in parallel (one per PE)
                        for (p = 0; p < 8; p = p + 1) begin
                            if (out_x + p < out_size_12) begin
                                // Calculate addresses for PE p
                                acc[p] <= acc[p] + 
                                    input_mem[(out_y + ky) * N_reg_12 + (out_x + p + kx)] * 
                                    kernel_mem[ky * K_reg + kx];
                            end
                        end
                        

                        if (kx == 0 && ky == 0 && (out_x % 8 == 0))
                             $display("[RTL DEBUG] S_COMPUTE Progress: out_x=%0d, out_y=%0d", out_x, out_y);
                             
                        // Check if this cycle completes K×K MACs for current 8 pixels
                        if (kx == K_reg - 1 && ky == K_reg - 1) begin
                            // Store 8 results with saturation
                            for (p = 0; p < 8; p = p + 1) begin
                                if (out_x + p < out_size_12) begin
                                    // Compute final value with last MAC
                                    if (acc[p] + input_mem[(out_y + ky) * N_reg_12 + (out_x + p + kx)] * kernel_mem[ky * K_reg + kx] > 255)
                                        output_mem[out_y * out_size_12 + out_x + p] <= 8'hFF;
                                    else
                                        output_mem[out_y * out_size_12 + out_x + p] <= 
                                            acc[p] + input_mem[(out_y + ky) * N_reg_12 + (out_x + p + kx)] * kernel_mem[ky * K_reg + kx];
                                end
                                acc[p] <= 0;  // Reset accumulator for next batch
                            end
                            
                            // Reset kernel position
                            kx <= 0;
                            ky <= 0;
                            
                            // Advance output position by 8 (row-parallel)
                            if (out_x + 8 < out_size_12) begin
                                out_x <= out_x + 8;
                            end else begin
                                out_x <= 0;
                                if (out_y < out_size_12 - 1) begin
                                    out_y <= out_y + 1;
                                end else begin
                                    compute_done <= 1;
                                end
                            end
                        end else begin
                            // Advance kernel position
                            if (kx < K_reg - 1) begin
                                kx <= kx + 1;
                            end else begin
                                kx <= 0;
                                ky <= ky + 1;
                            end
                        end
                    end
                end
                
                //--------------------------------------------------------------
                S_DRAIN: begin
                    if (tx_ready && drain_counter < output_count) begin
                        tx_data <= output_mem[drain_counter];
                        tx_valid <= 1;
                        drain_counter <= drain_counter + 1;
                    end
                end
                
                //--------------------------------------------------------------
                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule
