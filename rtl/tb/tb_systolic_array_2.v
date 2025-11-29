`timescale 1ns/1ps

module tb_systolic_array_2;

// ======================================================
// Parameters
// ======================================================
parameter ROWS        = 8;
parameter COLS        = 8;
parameter DATA_WIDTH  = 8;
parameter PSUM_WIDTH  = 32;

// ======================================================
// DUT signals
// ======================================================
reg clk;
reg rst_n;

reg enable;
reg load_weight;
reg clear_acc;

reg  [ROWS*DATA_WIDTH-1:0] pixel_in_bus;
reg  [COLS*PSUM_WIDTH-1:0] psum_in_bus;

wire [ROWS*DATA_WIDTH-1:0] pixel_out_bus;
wire [COLS*PSUM_WIDTH-1:0] psum_out_bus;

// ======================================================
// Global integers (NO declarations inside blocks!)
// ======================================================
integer fd;
integer r, c, t;
integer img_fd, ker_fd;
integer scan_ret;
integer N, K;
integer idx;
integer tile_y, tile_x;
integer out_h, out_w;
integer yy, xx;
integer pixval;
integer T;

// memory
reg [31:0] image_mem  [0:4095];
reg [31:0] kernel_mem [0:1023];

// ======================================================
// Clock
// ======================================================
initial clk = 0;
always #5 clk = ~clk;

// ======================================================
// DUT instantiation
// ======================================================
systolic_array #(
    .ROWS(ROWS),
    .COLS(COLS),
    .DATA_WIDTH(DATA_WIDTH),
    .PSUM_WIDTH(PSUM_WIDTH)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .enable(enable),
    .load_weight(load_weight),
    .clear_acc(clear_acc),
    .pixel_in_bus(pixel_in_bus),
    .psum_in_bus(psum_in_bus),
    .pixel_out_bus(pixel_out_bus),
    .psum_out_bus(psum_out_bus)
);

// ======================================================
// Read files (must have NO declarations inside)
// ======================================================
task read_files;
    begin
        img_fd = $fopen("data/inputs/input_matrix.txt", "r");
        if (img_fd == 0) begin
            $display("ERROR: cannot open input_matrix.txt");
            $finish;
        end

        scan_ret = $fscanf(img_fd, "# N %d\n", N);
        if (scan_ret != 1) begin
            $display("ERROR: invalid header in input_matrix.txt");
            $finish;
        end

        idx = 0;
        for (r = 0; r < N; r = r + 1)
        for (c = 0; c < N; c = c + 1) begin
            scan_ret = $fscanf(img_fd, "%d", pixval);
            if (scan_ret != 1) begin
                $display("ERROR: reading image value %d", idx);
                $finish;
            end
            image_mem[idx] = pixval;
            idx = idx + 1;
        end
        $fclose(img_fd);

        ker_fd = $fopen("data/inputs/kernel.txt", "r");
        if (ker_fd == 0) begin
            $display("ERROR: cannot open kernel.txt");
            $finish;
        end

        scan_ret = $fscanf(ker_fd, "# K %d\n", K);
        if (scan_ret != 1) begin
            $display("ERROR: invalid header in kernel.txt");
            $finish;
        end

        idx = 0;
        for (r = 0; r < K; r = r + 1)
        for (c = 0; c < K; c = c + 1) begin
            scan_ret = $fscanf(ker_fd, "%d", pixval);
            if (scan_ret != 1) begin
                $display("ERROR: reading kernel value %d", idx);
                $finish;
            end
            kernel_mem[idx] = pixval;
            idx = idx + 1;
        end
        $fclose(ker_fd);
    end
endtask

// ======================================================
// Log psums to output file
// ======================================================
initial begin
    fd = $fopen("data/results/results_hw.txt", "w");
end

always @(posedge clk) begin
    if (rst_n && enable) begin
        for (c = 0; c < COLS; c = c + 1)
            $fwrite(fd, "%0d ", psum_out_bus[c*PSUM_WIDTH +: PSUM_WIDTH]);
        $fwrite(fd, "\n");
    end
end

// ======================================================
// MAIN TESTBENCH
// ======================================================
initial begin
    // default
    clk = 0;
    rst_n = 0;
    enable = 0;
    load_weight = 0;
    clear_acc = 0;
    pixel_in_bus = 0;
    psum_in_bus  = 0;

    // Read files
    read_files();

    // Reset
    #50 rst_n = 1;

    // --------------------------------------------------
    // LOAD WEIGHTS (column-wise)
    // --------------------------------------------------
    for (c = 0; c < K; c = c + 1) begin
        pixel_in_bus = 0;
        for (r = 0; r < ROWS; r = r + 1) begin
            if (r < K)
                pixel_in_bus[r*DATA_WIDTH +: DATA_WIDTH] = kernel_mem[r*K + c];
            else
                pixel_in_bus[r*DATA_WIDTH +: DATA_WIDTH] = 0;
        end
        load_weight = 1;
        @(posedge clk);
        load_weight = 0;
        @(posedge clk);
    end

    // --------------------------------------------------
    // CLEAR ACCUMULATORS AFTER WEIGHT LOAD
    // --------------------------------------------------
    @(posedge clk);
    clear_acc = 1;
    @(posedge clk);
    clear_acc = 0;

    // Enable compute for streaming phase only
    enable = 1;

    // --------------------------------------------------
    // STREAM SLIDING WINDOW
    // --------------------------------------------------
    out_h = N - K + 1;
    out_w = N - K + 1;
    T = K + ROWS - 1;

    for (tile_y = 0; tile_y <= out_h-1; tile_y = tile_y + ROWS)
    for (tile_x = 0; tile_x <= out_w-1; tile_x = tile_x + COLS) begin

        for (t = 0; t < T; t = t + 1) begin
            pixel_in_bus = 0;

            for (r = 0; r < ROWS; r = r + 1) begin
                yy = tile_y + r;
                xx = tile_x + t;

                if ((yy >= 0) && (yy < N) && (xx >= 0) && (xx < N))
                    pixval = image_mem[yy*N + xx];
                else
                    pixval = 0;

                pixel_in_bus[r*DATA_WIDTH +: DATA_WIDTH] = pixval;
            end

            @(posedge clk);
        end

        // drain cycles
        repeat (12) @(posedge clk);
    end

    repeat (20) @(posedge clk);
    $finish;
end

endmodule
