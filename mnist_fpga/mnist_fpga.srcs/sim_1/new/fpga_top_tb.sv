`timescale 1ns / 1ps

module fpga_top_tb();

    localparam int CLKS_PER_BIT = 8;      // small for sim speed; real build uses clk/baud
    localparam int BIT_TIME = CLKS_PER_BIT * 10;

    logic clk = 0;
    logic btn_rst;
    logic uart_rx_line;
    logic [3:0] digit;
    logic result_ready;

    wire rst_n = ~btn_rst;

    fpga_top#(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut(
        .clk(clk),
        .btn_rst(btn_rst),
        .uart_rx_line(uart_rx_line),
        .digit(digit),
        .result_ready(result_ready)
    );

    always #5 clk = ~clk;

    logic [7:0] image [0:783];
    logic [3:0] digit_golden [0:0];

    initial $readmemh("test_image.mem", image);
    initial $readmemh("test_image_golden_digit.mem", digit_golden);

    task automatic send_byte(input logic [7:0] b);
        uart_rx_line = 1'b0;                       // start bit
        repeat(CLKS_PER_BIT) @(posedge clk);
        for(int i = 0; i < 8; i++) begin           // LSB first
            uart_rx_line = b[i];
            repeat(CLKS_PER_BIT) @(posedge clk);
        end
        uart_rx_line = 1'b1;                       // stop bit
        repeat(CLKS_PER_BIT) @(posedge clk);
    endtask

    int img_writes = 0;
    always @ (posedge clk)
        if (rst_n && dut.img_wr_en) img_writes++;

    initial begin
        uart_rx_line = 1'b1;
        btn_rst = 1;
        repeat(10) @(posedge clk);
        btn_rst = 0;
        repeat(10) @(posedge clk);

        $display("sending 784 image pixels over UART...");
        for(int a = 0; a < 784; a++) begin
            send_byte({2'b01, 4'b0000, a[9:8]});   // IMG header + addr hi
            send_byte(a[7:0]);                     // addr lo
            send_byte(image[a]);                   // pixel
        end
        $display("  %0d pixel writes reached accel_top", img_writes);

        $display("sending START...");
        send_byte({2'b10, 6'b000000});

        wait (result_ready == 1'b1);
        repeat(5) @(posedge clk);

        $display("");
        $display("image writes : %0d/784", img_writes);
        $display("digit        : %0d (golden %0d)", digit, digit_golden[0]);
        $display("result_ready : %0b (latched, drives an LED/pin)", result_ready);

        if (img_writes == 784 && digit == digit_golden[0] && result_ready)
            $display("\nPASS: UART -> inference -> digit = %0d", digit);
        else
            $display("\nFAIL");

        $finish;
    end

    initial begin
        #50000000;
        $display("\nFAIL: timeout");
        $finish;
    end

endmodule
