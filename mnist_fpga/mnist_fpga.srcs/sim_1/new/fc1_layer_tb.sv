`timescale 1ns / 1ps

module fc1_layer_tb();

    localparam int NUM_CHANNELS = 16;
    localparam int SPATIAL = 144;
    localparam int NUM_NEURONS = 64;

    logic clk;
    logic rst_n;
    logic en;

    logic [7:0] pool_result [0:15];
    logic [7:0] pool_res_addr;
    logic pool_res_v;

    logic [7:0] res [0:15];
    logic [7:0] res_addr [0:15];
    logic res_v;
    logic done;

    fc1_layer dut(
        .clk(clk),
        .rst_n(rst_n),
        .en(en),

        .pool_result(pool_result),
        .pool_res_addr(pool_res_addr),
        .pool_res_v(pool_res_v),

        .res(res),
        .res_addr(res_addr),
        .res_v(res_v),
        .done(done)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    int unsigned pool_golden [0:NUM_CHANNELS*SPATIAL-1];
    int unsigned fc1_golden [0:NUM_NEURONS-1];

    initial $readmemh("test_image_golden_pool.mem", pool_golden);
    initial $readmemh("test_image_golden_fc1.mem", fc1_golden);

    int unsigned captured [0:NUM_NEURONS-1];
    logic seen [0:NUM_NEURONS-1];
    int res_count = 0;
    int errors = 0;

    always @ (posedge clk) begin
        if (rst_n && res_v) begin
            for (int l = 0; l < 16; l++) begin
                if (res_addr[l] >= NUM_NEURONS) begin
                    $error("FC1 res_addr out of range: lane=%0d addr=%0d", l, res_addr[l]);
                    errors++;
                end else begin
                    if (seen[res_addr[l]]) begin
                        $error("FC1 neuron %0d produced twice (lane %0d)", res_addr[l], l);
                        errors++;
                    end
                    captured[res_addr[l]] = res[l];
                    seen[res_addr[l]] = 1;
                    res_count++;

                    if (res[l] != fc1_golden[res_addr[l]]) begin
                        errors++;
                        if (errors <= 10)
                            $error("FC1 mismatch lane=%0d neuron=%0d rtl=%0d golden=%0d",
                                   l, res_addr[l], res[l], fc1_golden[res_addr[l]]);
                    end
                end
            end
        end
    end

    initial begin
        rst_n = 0;
        en = 0;
        pool_res_v = 0;
        pool_res_addr = 0;
        for (int c = 0; c < NUM_CHANNELS; c++) pool_result[c] = 0;
        for (int n = 0; n < NUM_NEURONS; n++) seen[n] = 0;

        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Stream the pooled activations in exactly as max_pool would:
        // all 16 channels in parallel, one spatial address per cycle
        for (int a = 0; a < SPATIAL; a++) begin
            for (int c = 0; c < NUM_CHANNELS; c++)
                pool_result[c] = pool_golden[c*SPATIAL + a];
            pool_res_addr = a;
            pool_res_v = 1;
            @(posedge clk);
        end
        pool_res_v = 0;
        @(posedge clk);

        en = 1;
        @(posedge clk);
        en = 0;

        wait (done == 1'b1);
        repeat(5) @(posedge clk);

        $display("\n=== fc1 stage ===");
        $display("fc1: %0d/%0d results captured, %0d mismatches",
                  res_count, NUM_NEURONS, errors);

        for (int n = 0; n < NUM_NEURONS; n++)
            if (!seen[n]) begin
                $display("  [warn] neuron %0d never produced a result", n);
                errors++;
            end

        $write("  rtl   :");
        for (int n = 0; n < 16; n++) $write(" %3d", captured[n]);
        $write("\n  golden:");
        for (int n = 0; n < 16; n++) $write(" %3d", fc1_golden[n]);
        $write("\n");

        if (errors == 0 && res_count == NUM_NEURONS)
            $display("\nPASS: fc1 matches golden exactly");
        else
            $display("\nFAIL: see mismatches/warnings above");

        $finish;
    end

    initial begin
        #3000000;
        $display("\nFAIL: timeout waiting for done");
        $finish;
    end

endmodule
