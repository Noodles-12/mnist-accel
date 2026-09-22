`timescale 1ns / 1ps

module accel_top(
    input logic clk,
    input logic rst_n,
    input logic start,

    input logic img_wr_en,
    input logic [9:0] img_wr_addr,
    input logic [7:0] img_wr_data,

    output logic [3:0] digit,
    output logic done
);

    typedef enum logic [3:0] {
        TOP_IDLE,
        TOP_CONV_GO,      // pulse conv_layer.en for exactly one cycle
        TOP_CONV_WAIT,    // wait for conv_layer.done
        TOP_POOL_GO,      // pulse max_pool.en for exactly one cycle
        TOP_POOL_WAIT,    // wait for max_pool.done
        TOP_FC1_GO,       // pulse fc1_layer.en for exactly one cycle
        TOP_FC1_WAIT,     // wait for fc1_layer.done
        TOP_FC2_GO,       // pulse fc2_layer.en for exactly one cycle
        TOP_FC2_WAIT      // wait for argmax to assert digit_v
    } top_state;

    top_state state;

    logic conv_en;
    logic conv_calc_v;
    logic [7:0] conv_final_res;
    logic [9:0] conv_res_addr;
    logic [3:0] conv_filter_addr;
    logic conv_done;

    logic pool_en;
    logic pool_done;
    logic [7:0] pool_result [0:15];
    logic [7:0] pool_res_addr;
    logic pool_res_v;

    logic fc1_en;
    logic fc1_done;
    logic [7:0] fc1_res [0:15];
    logic [7:0] fc1_res_addr [0:15];
    logic fc1_res_v;

    logic fc2_en;
    logic fc2_done;
    logic signed [31:0] fc2_res [0:9];
    logic fc2_res_v;

    logic argmax_recv_v;
    logic argmax_done_v;
    logic digit_v;

    conv_layer conv(
        .clk(clk),
        .rst_n(rst_n),
        .en(conv_en),

        .img_wr_en(img_wr_en),
        .img_wr_addr(img_wr_addr),
        .img_wr_data(img_wr_data),

        .calc_v(conv_calc_v),
        .final_res(conv_final_res),
        .res_addr(conv_res_addr),
        .filter_addr(conv_filter_addr),
        .done(conv_done)
    );

    max_pool pool(
        .clk(clk),
        .rst_n(rst_n),
        .en(pool_en),

        .wr_en(conv_calc_v),
        .wr_data(conv_final_res),
        .wr_mem_addr(conv_res_addr),
        .wr_filter_addr(conv_filter_addr),

        .result(pool_result),
        .res_addr(pool_res_addr),
        .res_v(pool_res_v),
        .done(pool_done)
    );

    fc1_layer fc1(
        .clk(clk),
        .rst_n(rst_n),
        .en(fc1_en),

        .pool_result(pool_result),
        .pool_res_addr(pool_res_addr),
        .pool_res_v(pool_res_v),

        .res(fc1_res),
        .res_addr(fc1_res_addr),
        .res_v(fc1_res_v),
        .done(fc1_done)
    );

    fc2_layer fc2(
        .clk(clk),
        .rst_n(rst_n),
        .en(fc2_en),

        .wr_data(fc1_res),
        .wr_addr(fc1_res_addr),
        .wr_v(fc1_res_v),

        .recv_v(argmax_recv_v),

        .res(fc2_res),
        .res_v(fc2_res_v),
        .done(fc2_done)
    );

    argmax_layer am(
        .clk(clk),
        .rst_n(rst_n),
        .en(1'b1),

        .data_in(fc2_res),
        .data_v(fc2_res_v),

        .done_v(argmax_done_v),
        .wr_v(argmax_recv_v),

        .res(digit),
        .res_v(digit_v)
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= TOP_IDLE;
            conv_en <= 0;
            pool_en <= 0;
            fc1_en <= 0;
            fc2_en <= 0;
            done <= 0;
        end else begin
            conv_en <= 0;   // single-cycle pulses; deassert unless a GO state below sets them
            pool_en <= 0;
            fc1_en <= 0;
            fc2_en <= 0;

            unique case(state)
                TOP_IDLE : begin
                    done <= 0;
                    if(start)
                        state <= TOP_CONV_GO;
                end

                TOP_CONV_GO : begin
                    conv_en <= 1;
                    state   <= TOP_CONV_WAIT;
                end

                TOP_CONV_WAIT : begin
                    if(conv_done)
                        state <= TOP_POOL_GO;
                end

                TOP_POOL_GO : begin
                    pool_en <= 1;
                    state   <= TOP_POOL_WAIT;
                end

                TOP_POOL_WAIT : begin
                    if(pool_done)
                        state <= TOP_FC1_GO;
                end

                TOP_FC1_GO : begin
                    fc1_en <= 1;
                    state  <= TOP_FC1_WAIT;
                end

                TOP_FC1_WAIT : begin
                    if(fc1_done)
                        state <= TOP_FC2_GO;
                end

                TOP_FC2_GO : begin
                    fc2_en <= 1;
                    state  <= TOP_FC2_WAIT;
                end

                TOP_FC2_WAIT : begin
                    if(digit_v) begin
                        done  <= 1;
                        state <= TOP_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
