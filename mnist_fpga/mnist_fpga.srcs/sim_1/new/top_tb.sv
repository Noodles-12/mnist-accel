`timescale 1ns / 1ps

module top_tb();

    localparam int NUM_FILTERS = 16;
    localparam int CONV_GRID   = 24;   // conv1 output is 24x24 per filter
    localparam int POOL_GRID   = 12;   // pooled output is 12x12 per filter
    localparam int NUM_NEURONS = 64;
    localparam int NUM_CLASSES = 10;

    logic clk;
    logic rst_n;
    logic start;

    logic [3:0] digit;
    logic done;

    accel_top dut(
        .clk(clk),
        .rst_n(rst_n),
        .start(start),

        .img_wr_en(1'b0),
        .img_wr_addr(10'b0),
        .img_wr_data(8'b0),

        .digit(digit),
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
        repeat(3) @(posedge clk);
        rst_n = 1;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;
    end

    // ---------------- conv1 ----------------
    int unsigned conv_golden [0:NUM_FILTERS*CONV_GRID*CONV_GRID-1];
    initial $readmemh("test_image_golden_conv1.mem", conv_golden);

    int conv_total = 0;
    int conv_errors = 0;

    always @ (posedge clk) begin
        if (rst_n && dut.conv_calc_v) begin
            automatic int row = dut.conv_res_addr / CONV_GRID;
            automatic int col = dut.conv_res_addr % CONV_GRID;
            automatic int f   = dut.conv_filter_addr;
            automatic int unsigned g = conv_golden[f*CONV_GRID*CONV_GRID + row*CONV_GRID + col];

            conv_total++;
            if (dut.conv_final_res != g) begin
                conv_errors++;
                if (conv_errors <= 10)
                    $error("CONV1 mismatch f=%0d row=%0d col=%0d rtl=%0d golden=%0d",
                           f, row, col, dut.conv_final_res, g);
            end
        end
    end

    // ---------------- pool ----------------
    int unsigned pool_golden [0:NUM_FILTERS*POOL_GRID*POOL_GRID-1];
    initial $readmemh("test_image_golden_pool.mem", pool_golden);

    int pool_total = 0;
    int pool_errors = 0;

    always @ (posedge clk) begin
        if (rst_n && dut.pool_res_v) begin
            automatic int a = dut.pool_res_addr;
            for (int f = 0; f < NUM_FILTERS; f++) begin
                automatic int unsigned g = pool_golden[f*POOL_GRID*POOL_GRID + a];
                pool_total++;
                if (dut.pool_result[f] != g) begin
                    pool_errors++;
                    if (pool_errors <= 10)
                        $error("POOL mismatch f=%0d addr=%0d rtl=%0d golden=%0d",
                               f, a, dut.pool_result[f], g);
                end
            end
        end
    end

    // ---------------- fc1 ----------------
    int unsigned fc1_golden [0:NUM_NEURONS-1];
    initial $readmemh("test_image_golden_fc1.mem", fc1_golden);

    logic fc1_seen [0:NUM_NEURONS-1];
    int fc1_total = 0;
    int fc1_errors = 0;

    initial
        for (int n = 0; n < NUM_NEURONS; n++) fc1_seen[n] = 0;

    always @ (posedge clk) begin
        if (rst_n && dut.fc1_res_v) begin
            for (int l = 0; l < NUM_FILTERS; l++) begin
                automatic int a = dut.fc1_res_addr[l];
                if (a >= NUM_NEURONS) begin
                    $error("FC1 res_addr out of range: lane=%0d addr=%0d", l, a);
                    fc1_errors++;
                end else begin
                    if (fc1_seen[a]) begin
                        $error("FC1 neuron %0d produced twice (lane %0d)", a, l);
                        fc1_errors++;
                    end
                    fc1_seen[a] = 1;
                    fc1_total++;
                    if (dut.fc1_res[l] != fc1_golden[a]) begin
                        fc1_errors++;
                        if (fc1_errors <= 10)
                            $error("FC1 mismatch lane=%0d neuron=%0d rtl=%0d golden=%0d",
                                   l, a, dut.fc1_res[l], fc1_golden[a]);
                    end
                end
            end
        end
    end

    // ---------------- fc2 ----------------
    logic signed [31:0] fc2_golden [0:NUM_CLASSES-1];
    initial $readmemh("test_image_golden_fc2.mem", fc2_golden);

    int fc2_total = 0;
    int fc2_errors = 0;

    always @ (posedge clk) begin
        if (rst_n && dut.fc2_res_v) begin
            for (int c = 0; c < NUM_CLASSES; c++) begin
                fc2_total++;
                if (dut.fc2_res[c] !== fc2_golden[c]) begin
                    fc2_errors++;
                    if (fc2_errors <= 10)
                        $error("FC2 mismatch class=%0d rtl=%0d golden=%0d",
                               c, dut.fc2_res[c], fc2_golden[c]);
                end
            end
        end
    end

    // ---------------- argmax / digit ----------------
    logic [3:0] digit_golden [0:0];
    initial $readmemh("test_image_golden_digit.mem", digit_golden);

    int digit_seen = 0;
    int digit_errors = 0;

    always @ (posedge clk) begin
        if (rst_n && dut.digit_v) begin
            digit_seen++;
            if (digit != digit_golden[0]) begin
                digit_errors++;
                $error("DIGIT mismatch rtl=%0d golden=%0d", digit, digit_golden[0]);
            end
        end
    end

    initial begin
        wait (done == 1'b1);
        repeat(5) @(posedge clk);

        $display("\n=== conv1 ===  %0d/%0d captured, %0d mismatches",
                  conv_total, NUM_FILTERS*CONV_GRID*CONV_GRID, conv_errors);
        $display("=== pool  ===  %0d/%0d captured, %0d mismatches",
                  pool_total, NUM_FILTERS*POOL_GRID*POOL_GRID, pool_errors);
        $display("=== fc1   ===  %0d/%0d captured, %0d mismatches",
                  fc1_total, NUM_NEURONS, fc1_errors);
        $display("=== fc2   ===  %0d/%0d captured, %0d mismatches",
                  fc2_total, NUM_CLASSES, fc2_errors);

        $write("  fc2 accumulators:");
        for (int c = 0; c < NUM_CLASSES; c++) $write(" %0d", dut.fc2_res[c]);
        $write("\n");

        $display("=== digit ===  predicted %0d (golden %0d), %0d valid pulses, %0d mismatches",
                  digit, digit_golden[0], digit_seen, digit_errors);

        if (conv_errors == 0 && pool_errors == 0 && fc1_errors == 0
            && fc2_errors == 0 && digit_errors == 0
            && conv_total == NUM_FILTERS*CONV_GRID*CONV_GRID
            && pool_total == NUM_FILTERS*POOL_GRID*POOL_GRID
            && fc1_total == NUM_NEURONS
            && fc2_total == NUM_CLASSES
            && digit_seen == 1)
            $display("\nPASS: full pipeline matches golden, digit = %0d", digit);
        else
            $display("\nFAIL: see mismatches/warnings above");

        $finish;
    end

    initial begin
        #5000000;
        $display("\nFAIL: timeout waiting for done");
        $finish;
    end

endmodule
