`timescale 1ns / 1ps

module conv_layer_tb();

    logic clk;
    logic rst_n;
    logic en;

    conv_layer dut(
        .clk(clk),
        .rst_n(rst_n),
        .en(en)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Reset sequence, then pulse en for exactly one cycle
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

    initial begin
        repeat(20) @(posedge clk);
        $finish;
    end

endmodule
