`timescale 1ns / 1ps

module fpga_top#(
    parameter int CLKS_PER_BIT = 1085
)(
    input logic clk,
    input logic btn_rst,

    input logic uart_rx_line,

    output logic [3:0] digit,
    output logic result_ready
);

    logic btn_meta = 1'b0;
    logic btn_sync = 1'b0;
    logic [3:0] por_cnt = 4'd0;
    logic rst_n;

    always_ff @ (posedge clk) begin
        btn_meta <= btn_rst;
        btn_sync <= btn_meta;

        if(btn_sync)
            por_cnt <= 4'd0;
        else if(!por_cnt[3])
            por_cnt <= por_cnt + 4'd1;
    end

    assign rst_n = por_cnt[3];

    logic [7:0] rx_data;
    logic rx_v;

    logic img_wr_en;
    logic [9:0] img_wr_addr;
    logic [7:0] img_wr_data;
    logic start;
    logic done;

    uart_rx#(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) urx(
        .clk(clk),
        .rst_n(rst_n),
        .rx(uart_rx_line),
        .rx_data(rx_data),
        .rx_v(rx_v)
    );

    uart_cmd ucmd(
        .clk(clk),
        .rst_n(rst_n),
        .rx_data(rx_data),
        .rx_v(rx_v),
        .img_wr_en(img_wr_en),
        .img_wr_addr(img_wr_addr),
        .img_wr_data(img_wr_data),
        .start(start)
    );

    accel_top at(
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .img_wr_en(img_wr_en),
        .img_wr_addr(img_wr_addr),
        .img_wr_data(img_wr_data),
        .digit(digit),
        .done(done)
    );

    always_ff @ (posedge clk) begin
        if(!rst_n)
            result_ready <= 1'b0;
        else if(start)
            result_ready <= 1'b0;
        else if(done)
            result_ready <= 1'b1;
    end
endmodule
