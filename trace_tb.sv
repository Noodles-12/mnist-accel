`timescale 1ns / 1ps

module conv_layer_tb();

    localparam int NUM_FILTERS = 16;
    localparam int GRID        = 24;   // conv1 output is 24x24 per filter

    logic clk;
    logic rst_n;
    logic en;

    logic        calc_v;
    logic [31:0] final_res;
    logic [9:0]  res_addr;
    logic [3:0]  filter_addr;
    logic        done;

    conv_layer dut(
        .clk(clk),
        .rst_n(rst_n),
        .en(en),

        // Image load port left tied off -- the image is preloaded straight
        // into conv_mem's memory below instead of exercised through here
        .img_wr_en(1'b0),
        .img_wr_addr(10'b0),
        .img_wr_data(8'b0),

        .calc_v(calc_v),
        .final_res(final_res),
        .res_addr(res_addr),
        .filter_addr(filter_addr),
        .done(done)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Preload the test image straight into conv_mem's img_mem, bypassing
    // the img_wr_* port entirely. img_mem is replicated once per lane (25
    // copies, one per 5x5 window tap) so every copy needs the same full
    // 784-pixel image -- same trick weight_mem already uses per-lane, just
    // driven from the TB instead of from RTL.
    for (genvar p = 0; p < 25; p = p + 1) begin : gen_img_preload
        initial $readmemh("test_image.mem", dut.cm.gen_image_buffer[p].img_mem);
    end

    // Reset sequence, then pulse en for exactly one cycle to start the sweep
    initial begin
        rst_n = 0;
        en = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;

        @(posedge clk);
        en = 1;
        @(posedge clk);
        en = 0;
    end

    // Check that weight_mem was loaded correctly from conv_w_<lane>.mem at time 0
    initial begin
        #1;
        if (dut.cm.gen_weight_lane[0].weight_mem[0] !== 8'h08)
            $error("lane 0, filter 0 = %h, expected 08", dut.cm.gen_weight_lane[0].weight_mem[0]);

        if (dut.cm.gen_weight_lane[0].weight_mem[1] !== 8'h1c)
            $error("lane 0, filter 1 = %h, expected 1c", dut.cm.gen_weight_lane[0].weight_mem[1]);

        if (dut.cm.gen_weight_lane[1].weight_mem[0] !== 8'h1e)
            $error("lane 1, filter 0 = %h, expected 1e", dut.cm.gen_weight_lane[1].weight_mem[0]);

        if (dut.cm.gen_weight_lane[1].weight_mem[1] !== 8'h4f)
            $error("lane 1, filter 1 = %h, expected 4f", dut.cm.gen_weight_lane[1].weight_mem[1]);

        $display("weight_mem load check done");
    end

    // Check that bias_mem was loaded correctly from conv1_bias.mem at time 0
    initial begin
        #1;
        if (dut.cdp.bias_mem[0] !== 32'sd4164)
            $error("bias filter 0 = %0d, expected 4164", dut.cdp.bias_mem[0]);

        if (dut.cdp.bias_mem[6] !== 32'sd9332)
            $error("bias filter 6 = %0d, expected 9332", dut.cdp.bias_mem[6]);

        if (dut.cdp.bias_mem[15] !== -32'sd959)
            $error("bias filter 15 = %0d, expected -959", dut.cdp.bias_mem[15]);

        $display("bias_mem load check done");
    end

    // Capture every valid conv1 output into a full [filter][row][col] grid,
    // and also feed a row queue that prints one 24-wide row the moment it
    // fills -- results come out of conv_layer in strict row-major order
    // within a filter, so a 24-deep queue always empties exactly on a row
    // boundary with nothing left over.
    int unsigned results [0:NUM_FILTERS-1][0:GRID-1][0:GRID-1];
    int unsigned row_q [$];
    int total_results = 0;
    int per_filter_count [0:NUM_FILTERS-1];

    always @ (posedge clk) begin
        if (rst_n && calc_v) begin
            automatic int row = res_addr / GRID;
            automatic int col = res_addr % GRID;

            results[filter_addr][row][col] = final_res;
            total_results++;
            per_filter_count[filter_addr]++;

            if (row == 0 && col == 0)
                $display("\n=== Filter %0d ===", filter_addr);

            row_q.push_back(final_res);
            if (row_q.size() == GRID) begin
                $write("  row %2d:", row);
                foreach (row_q[i]) $write(" %7d", row_q[i]);
                $write("\n");
                row_q.delete();
            end
        end
    end

    initial begin
        wait (done == 1'b1);
        repeat(5) @(posedge clk);
        $display("\nconv1 sweep complete: %0d/%0d results captured",
                  total_results, NUM_FILTERS * GRID * GRID);
        for (int f = 0; f < NUM_FILTERS; f++)
            $display("  filter %2d: %0d/%0d", f, per_filter_count[f], GRID * GRID);
        $finish;
    end

endmodule
