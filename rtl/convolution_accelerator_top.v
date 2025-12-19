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
    input  wire [3:0]               cfg_K,
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
    reg [3:0]  K_reg;
    reg [11:0] input_count;
    reg [7:0]  kernel_count;
    reg [11:0] output_count;
    reg [6:0]  out_size;
    
    //==========================================================================
    // Counters - Use 12-bit for wider range
    //==========================================================================
    reg [11:0] load_counter;
    reg [7:0]  weight_counter;
    reg [11:0] drain_counter;
    reg [11:0] out_x, out_y;     // 12-bit to prevent overflow in address calc
    reg [4:0]  kx, ky;
    reg [PSUM_WIDTH-1:0] acc;
    reg        compute_done;
    
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
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
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
            acc <= 0;
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
                        input_count <= cfg_N * cfg_N;
                        kernel_count <= cfg_K * cfg_K;
                        out_size <= cfg_N - cfg_K + 1;
                        output_count <= (cfg_N - cfg_K + 1) * (cfg_N - cfg_K + 1);
                        load_counter <= 0;
                        weight_counter <= 0;
                        drain_counter <= 0;
                        out_x <= 0;
                        out_y <= 0;
                        kx <= 0;
                        ky <= 0;
                        acc <= 0;
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
                        // One MAC per cycle - use pre-computed addresses to avoid overflow
                        acc <= acc + input_mem[input_addr] * kernel_mem[kernel_addr];
                        
                        // Check if this completes current pixel
                        if (kx == K_reg - 1 && ky == K_reg - 1) begin
                            // Store result (saturate to 8-bit)
                            if (acc + input_mem[input_addr] * kernel_mem[kernel_addr] > 255)
                                output_mem[output_addr] <= 8'hFF;
                            else
                                output_mem[output_addr] <= (acc + input_mem[input_addr] * kernel_mem[kernel_addr]);
                            
                            // Reset for next pixel
                            kx <= 0;
                            ky <= 0;
                            acc <= 0;
                            
                            // Advance output position
                            if (out_x < out_size_12 - 1) begin
                                out_x <= out_x + 1;
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
