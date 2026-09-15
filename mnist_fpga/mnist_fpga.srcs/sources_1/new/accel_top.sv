`timescale 1ns / 1ps

module accel_top(
    input logic clk,
    input logic rst_n
);

    typedef enum {
        TOP_IDLE,
        TOP_IMAGE,
        TOP_CONV,
        TOP_POOL,
        TOP_DONE
    } top_state;

    top_state state;

    logic conv_en, pool_en;

    // UART Protocol will go here

    conv_layer conv(
        .clk(clk),
        .rst_n(rst_n),
        .en(),

        .img_wr_en(),
        .img_wr_addr(),
        .img_wr_data(),

        .calc_v(),
        .final_res(),
        .res_addr(),
        .filter_addr(),
        .done()
    );

    max_pool pool(
        .clk(clk),
        .rst_n(rst_n),
        .en(),

        .wr_en(),
        .wr_data(),
        .wr_mem_addr(),
        .wr_filter_addr(),

        .result(),
        .res_addr(),
        .res_v(),
        .done()
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= TOP_IDLE;
        end else begin

        end
    end
endmodule
