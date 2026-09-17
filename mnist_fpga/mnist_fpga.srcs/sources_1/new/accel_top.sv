`timescale 1ns / 1ps

module accel_top(
    input logic clk,
    input logic rst_n,
    input logic start,

    input logic img_wr_en,
    input logic [9:0] img_wr_addr,
    input logic [7:0] img_wr_data,

    output logic [31:0] pool_result [0:15],
    output logic [7:0] pool_res_addr,
    output logic pool_res_v,

    input  logic [3:0]  flat_rd_block_addr,
    input  logic [7:0]  flat_rd_idx_addr,
    output logic [31:0] flat_rd_data,

    output logic done
);

    typedef enum logic [2:0] {
        TOP_IDLE,
        TOP_CONV_GO,      // pulse conv_layer.en for exactly one cycle
        TOP_CONV_WAIT,    // wait for conv_layer.done
        TOP_POOL_GO,      // pulse max_pool.en for exactly one cycle
        TOP_POOL_WAIT,    // wait for max_pool.done
        TOP_FLATTEN_WAIT, // wait for flatten_layer.done
        TOP_DONE
    } top_state;

    top_state state;

    logic conv_en;
    logic conv_calc_v;
    logic [31:0] conv_final_res;
    logic [9:0]  conv_res_addr;
    logic [3:0]  conv_filter_addr;
    logic conv_done;

    logic pool_en;
    logic pool_done;

    logic flatten_done;

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

    flatten_layer flatten(
        .clk(clk),
        .rst_n(rst_n),

        .pool_result(pool_result),
        .pool_res_addr(pool_res_addr),
        .pool_res_v(pool_res_v),

        .rd_block_addr(flat_rd_block_addr),
        .rd_idx_addr(flat_rd_idx_addr),
        .rd_data(flat_rd_data),

        .done(flatten_done)
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= TOP_IDLE;
            conv_en <= 0;
            pool_en <= 0;
            done <= 0;
        end else begin
            conv_en <= 0;   // single-cycle pulses; deassert unless a GO state below sets them
            pool_en <= 0;

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
                        state <= TOP_FLATTEN_WAIT;
                end

                TOP_FLATTEN_WAIT : begin
                    if(flatten_done)
                        state <= TOP_DONE;
                end

                TOP_DONE : begin
                    done  <= 1;
                    state <= TOP_IDLE;
                end
            endcase
        end
    end
endmodule
