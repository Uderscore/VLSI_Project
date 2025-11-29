`timescale 1ns/1ps

// Stage-1 focused testbench for the systolic_array compute core.
// - Uses an 8x1 array (ROWS=8, COLS=1) to simplify analysis.
// - Loads distinct weights into each PE (weight_stationary).
// - Streams a constant pixel value on all rows.
// - After the pipeline fills, the bottom psum should equal
//   sum_i (w_i * pixel) for i=0..ROWS-1.
// This verifies:
//   * Weight loading into each PE row.
//   * West->East pixel forwarding (trivial for COLS=1).
//   * North->South psum accumulation across all 8 rows.

module tb_systolic_array_stage1;

    // Parameters (reuse core defaults where possible)
    localparam ROWS       = 8;
    localparam COLS       = 1;   // single column for simpler vertical check
    localparam DATA_WIDTH = 8;
    localparam PSUM_WIDTH = 32;

    // DUT signals
    reg  clk;
    reg  rst_n;

    reg  enable;
    reg  load_weight;
    reg  clear_acc;

    reg  [ROWS*DATA_WIDTH-1:0] pixel_in_bus;
    reg  [COLS*PSUM_WIDTH-1:0] psum_in_bus;

    wire [ROWS*DATA_WIDTH-1:0] pixel_out_bus;
    wire [COLS*PSUM_WIDTH-1:0] psum_out_bus;

    // For convenience, name the single column bottom psum
    wire [PSUM_WIDTH-1:0] bottom_psum;
    assign bottom_psum = psum_out_bus[PSUM_WIDTH-1:0]; // Col 0

    // Instantiate DUT (systolic array built from processing_element PEs)
    systolic_array #(
        .ROWS(ROWS),
        .COLS(COLS),
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .load_weight (load_weight),
        .clear_acc   (clear_acc),
        .pixel_in_bus(pixel_in_bus),
        .psum_in_bus (psum_in_bus),
        .pixel_out_bus(pixel_out_bus),
        .psum_out_bus(psum_out_bus)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    integer r;
    integer cycle;
    integer sum_w;
    integer expected_sum;
    reg [7:0] pixel_val;

    // Main stimulus
    initial begin
        // Initial defaults
        rst_n       = 0;
        enable      = 0;
        load_weight = 0;
        clear_acc   = 0;
        pixel_in_bus = {ROWS*DATA_WIDTH{1'b0}};
        psum_in_bus  = {COLS*PSUM_WIDTH{1'b0}};

        // Hold reset for a few cycles
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        //------------------------------
        // 1) Load weights into each row (weight-stationary)
        //------------------------------
        // Choose simple pattern: w_r = r+1 for r=0..7
        for (r = 0; r < ROWS; r = r + 1) begin
            pixel_in_bus[r*DATA_WIDTH +: DATA_WIDTH] = r + 1;
        end

        // Pulse load_weight for one cycle so each PE latches its row weight
        load_weight = 1;
        @(posedge clk);
        load_weight = 0;
        @(posedge clk);

        //------------------------------
        // 2) Clear accumulators after weight load
        //------------------------------
        clear_acc = 1;
        @(posedge clk);
        clear_acc = 0;
        @(posedge clk);

        //------------------------------
        // 3) Stream constant pixels and enable compute
        //------------------------------
        pixel_val = 8'd3;  // arbitrary test value

        // Drive same pixel on all rows
        for (r = 0; r < ROWS; r = r + 1) begin
            pixel_in_bus[r*DATA_WIDTH +: DATA_WIDTH] = pixel_val;
        end
        psum_in_bus = {COLS*PSUM_WIDTH{1'b0}}; // no incoming psum from North

        enable = 1;

        // Run for ROWS+4 cycles to allow pipeline to fully settle
        for (cycle = 0; cycle < ROWS + 4; cycle = cycle + 1) begin
            @(posedge clk);
        end

        enable = 0;
        @(posedge clk);

        //------------------------------
        // 4) Compute expected result and check
        //------------------------------
        sum_w = 0;
        for (r = 0; r < ROWS; r = r + 1) begin
            sum_w = sum_w + (r + 1); // sum 1..8 = 36
        end
        expected_sum = sum_w * pixel_val; // 36 * 3 = 108

        $display("[STAGE1] Expected bottom_psum = %0d (sum_w=%0d, pixel=%0d)",
                 expected_sum, sum_w, pixel_val);
        $display("[STAGE1] Observed bottom_psum = %0d", bottom_psum);

        if (bottom_psum !== expected_sum) begin
            $display("[STAGE1] ✗ FAIL: systolic array bottom psum mismatch");
        end else begin
            $display("[STAGE1] ✓ PASS: systolic array bottom psum matches expected");
        end

        $finish;
    end

endmodule
