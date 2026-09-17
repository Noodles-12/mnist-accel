`timescale 1ns / 1ps

module top_tb();

    localparam int NUM_FILTERS = 16;
    localparam int CONV_GRID   = 24;   // conv1 output is 24x24 per filter
    localparam int POOL_GRID   = 12;   // pooled output is 12x12 per filter

    logic clk;
    logic rst_n;
    logic start;

    logic img_wr_en;
    logic [9:0] img_wr_addr;
    logic [7:0] img_wr_data;

    logic [31:0] pool_result [0:15];
    logic [7:0] pool_res_addr;
    logic pool_res_v;

    logic [3:0] flat_rd_block_addr;
    logic [7:0] flat_rd_idx_addr;
    logic [31:0] flat_rd_data;

    logic done;

    accel_top dut(
        .clk(clk),
        .rst_n(rst_n),
        .start(start),

        .img_wr_en(1'b0),
        .img_wr_addr(10'b0),
        .img_wr_data(8'b0),

        .pool_result(pool_result),
        .pool_res_addr(pool_res_addr),
        .pool_res_v(pool_res_v),

        .flat_rd_block_addr(flat_rd_block_addr),
        .flat_rd_idx_addr(flat_rd_idx_addr),
        .flat_rd_data(flat_rd_data),

        .done(done)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    for (genvar p = 0; p < 25; p = p + 1) begin : gen_img_preload
        initial $readmemh("test_image.mem", dut.conv.cm.gen_image_buffer[p].img_mem);
    end

    initial begin
        rst_n = 0;
        start = 0;
        flat_rd_block_addr = 0;
        flat_rd_idx_addr = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
    end

    int unsigned conv_golden [0:NUM_FILTERS*CONV_GRID*CONV_GRID-1];
    initial $readmemh("test_image_golden_conv1.mem", conv_golden);

    int unsigned conv_results [0:NUM_FILTERS-1][0:CONV_GRID-1][0:CONV_GRID-1];
    int unsigned conv_row_q [$];
    int conv_total = 0;
    int conv_errors = 0;
    int conv_per_filter [0:NUM_FILTERS-1];

    always @ (posedge clk) begin
        if (rst_n && dut.conv_calc_v) begin
            automatic int row = dut.conv_res_addr / CONV_GRID;
            automatic int col = dut.conv_res_addr % CONV_GRID;
            automatic int f   = dut.conv_filter_addr;
            automatic int unsigned golden_v = conv_golden[f*CONV_GRID*CONV_GRID + row*CONV_GRID + col];

            conv_results[f][row][col] = dut.conv_final_res;
            conv_total++;
            conv_per_filter[f]++;

            if (dut.conv_final_res != golden_v) begin
                conv_errors++;
                if (conv_errors <= 10)
                    $error("CONV1 mismatch f=%0d row=%0d col=%0d rtl=%0d golden=%0d",
                           f, row, col, dut.conv_final_res, golden_v);
            end

            if (row == 0 && col == 0)
                $display("\n=== conv1 Filter %0d ===", f);

            conv_row_q.push_back(dut.conv_final_res);
            if (conv_row_q.size() == CONV_GRID) begin
                $write("  row %2d:", row);
                foreach (conv_row_q[i]) $write(" %7d", conv_row_q[i]);
                $write("\n");
                conv_row_q.delete();
            end
        end
    end

    int unsigned pool_golden [0:NUM_FILTERS*POOL_GRID*POOL_GRID-1];
    initial $readmemh("test_image_golden_pool.mem", pool_golden);

    int unsigned pool_results [0:NUM_FILTERS-1][0:POOL_GRID-1][0:POOL_GRID-1];
    int pool_total = 0;
    int pool_errors = 0;
    int pool_per_addr_count = 0;

    always @ (posedge clk) begin
        if (rst_n && pool_res_v) begin
            automatic int row = pool_res_addr / POOL_GRID;
            automatic int col = pool_res_addr % POOL_GRID;

            $write("  pool row %2d col %2d:", row, col);
            for (int f = 0; f < NUM_FILTERS; f++) begin
                automatic int unsigned golden_v = pool_golden[f*POOL_GRID*POOL_GRID + row*POOL_GRID + col];
                pool_results[f][row][col] = pool_result[f];
                pool_total++;

                if (pool_result[f] != golden_v) begin
                    pool_errors++;
                    if (pool_errors <= 10)
                        $error("POOL mismatch f=%0d row=%0d col=%0d rtl=%0d golden=%0d",
                               f, row, col, pool_result[f], golden_v);
                end
                $write(" %7d", pool_result[f]);
            end
            $write("\n");
            pool_per_addr_count++;
        end
    end

    int flat_total = 0;
    int flat_errors = 0;

    initial begin
        wait (done == 1'b1);
        repeat(5) @(posedge clk);

        for (int a = 0; a < POOL_GRID*POOL_GRID; a++) begin
            for (int c = 0; c < NUM_FILTERS; c++) begin
                automatic int unsigned golden_v;
                flat_rd_block_addr = c;
                flat_rd_idx_addr = a;
                @(posedge clk); #1;
                golden_v = pool_golden[c*POOL_GRID*POOL_GRID + a];
                if (flat_rd_data != golden_v) begin
                    flat_errors++;
                    if (flat_errors <= 10)
                        $error("FLATTEN mismatch addr=%0d c=%0d rtl=%0d golden=%0d",
                               a, c, flat_rd_data, golden_v);
                end
                flat_total++;
            end
        end

        $display("\n=== conv1 stage ===");
        $display("conv1: %0d/%0d results captured, %0d mismatches",
                  conv_total, NUM_FILTERS * CONV_GRID * CONV_GRID, conv_errors);
        for (int f = 0; f < NUM_FILTERS; f++)
            if (conv_per_filter[f] != CONV_GRID * CONV_GRID)
                $display("  [warn] conv1 filter %2d: %0d/%0d results", f, conv_per_filter[f], CONV_GRID*CONV_GRID);

        $display("\n=== pool stage ===");
        $display("pool: %0d/%0d results captured (%0d addresses x 16 filters), %0d mismatches",
                  pool_total, NUM_FILTERS * POOL_GRID * POOL_GRID, pool_per_addr_count, pool_errors);
        if (pool_per_addr_count != POOL_GRID * POOL_GRID)
            $display("  [warn] only %0d/%0d pool addresses seen", pool_per_addr_count, POOL_GRID*POOL_GRID);

        $display("\n=== flatten stage ===");
        $display("flatten: %0d/%0d reads checked, %0d mismatches",
                  flat_total, POOL_GRID*POOL_GRID*NUM_FILTERS, flat_errors);

        if (conv_errors == 0 && pool_errors == 0 && flat_errors == 0
            && conv_total == NUM_FILTERS*CONV_GRID*CONV_GRID
            && pool_total == NUM_FILTERS*POOL_GRID*POOL_GRID
            && flat_total == POOL_GRID*POOL_GRID*NUM_FILTERS)
            $display("\nPASS: all three stages match golden exactly");
        else
            $display("\nFAIL: see mismatches/warnings above");

        $finish;
    end

endmodule
