`timescale 1ns / 1ps

module fc1_layer#(
    parameter int NUM_LANES = 16
)(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic [7:0] pool_result [0:15],
    input logic [7:0] pool_res_addr,
    input logic pool_res_v,

    output logic [7:0] res [0:NUM_LANES-1],
    output logic [7:0] res_addr [0:NUM_LANES-1],
    output logic res_v,
    output logic done
);

    localparam int NUM_CHANNELS = 16;
    localparam int SPATIAL = 144;
    localparam int NUM_NEURONS = 64;
    localparam int WEIGHTS_PER_NEURON = NUM_CHANNELS * SPATIAL;
    localparam int NUM_PHASES = NUM_NEURONS / NUM_LANES;

    typedef enum logic [1:0] {
        FC1_IDLE,
        FC1_CALC,
        FC1_INCR,
        FC1_DONE
    } fc1_state;

    fc1_state state;

    logic [3:0] block_addr_ip;
    logic [7:0] rd_idx_ip;
    logic [11:0] wt_addr_ip;
    logic [1:0] phase_idx_ip;

    logic calc_en;
    logic calc_en_d1;
    logic res_en;
    logic [2:0] drain_ctr;

    logic [13:0] weight_addr;
    logic [3:0] block_addr;
    logic [7:0] idx_addr;

    logic [7:0] rd_data;
    logic signed [7:0] rd_weight [0:NUM_LANES-1];
    logic data_v;

    fc1_addr_calc fc1ac(
        .clk(clk),
        .rst_n(rst_n),

        .block_addr(block_addr_ip),
        .idx_addr(rd_idx_ip),
        .wt_ip_addr(wt_addr_ip),
        .phase_idx(phase_idx_ip),

        .weight_addr_op(weight_addr),
        .block_addr_op(block_addr),
        .idx_addr_op(idx_addr)
    );

    fc1_mem#(
        .NUM_LANES(NUM_LANES)
    ) fc1mem(
        .clk(clk),
        .rst_n(rst_n),

        .pool_result(pool_result),
        .pool_res_addr(pool_res_addr),
        .pool_res_v(pool_res_v),

        .block_addr_ip(block_addr),
        .idx_addr_ip(idx_addr),
        .weight_addr_ip(weight_addr),
        .rd_v(calc_en_d1),

        .rd_data(rd_data),
        .rd_weight(rd_weight),
        .data_v(data_v)
    );

    fc1_dp#(
        .NUM_LANES(NUM_LANES),
        .NUM_NEURONS(NUM_NEURONS)
    ) fc1dp(
        .clk(clk),
        .rst_n(rst_n),
        .data_v(data_v),

        .data(rd_data),
        .weight(rd_weight),

        .phase_idx(phase_idx_ip),
        .res_en(res_en),

        .res(res),
        .res_addr(res_addr),
        .res_v(res_v)
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= FC1_IDLE;

            block_addr_ip <= '0;
            rd_idx_ip <= '0;
            wt_addr_ip <= '0;
            phase_idx_ip <= '0;

            calc_en <= 0;
            calc_en_d1 <= 0;
            res_en <= 0;
            drain_ctr <= '0;
            done <= 0;
        end else begin
            calc_en_d1 <= calc_en;
            res_en <= 0;

            case(state)
                FC1_IDLE: begin
                    block_addr_ip <= '0;
                    rd_idx_ip <= '0;
                    wt_addr_ip <= '0;
                    phase_idx_ip <= '0;

                    calc_en <= 0;
                    drain_ctr <= '0;
                    done <= 0;

                    if(en) begin
                        state <= FC1_CALC;
                        calc_en <= 1;
                    end
                end

                FC1_CALC: begin
                    if(wt_addr_ip == WEIGHTS_PER_NEURON - 1) begin
                        calc_en <= 0;
                        drain_ctr <= '0;
                        state <= FC1_INCR;
                    end else begin
                        wt_addr_ip <= wt_addr_ip + 1;

                        if(rd_idx_ip == SPATIAL - 1) begin
                            rd_idx_ip <= '0;
                            block_addr_ip <= block_addr_ip + 1;
                        end else begin
                            rd_idx_ip <= rd_idx_ip + 1;
                        end
                    end
                end

                FC1_INCR: begin
                    drain_ctr <= drain_ctr + 1;

                    if(drain_ctr == 3'd2) begin
                        res_en <= 1;
                    end

                    if(drain_ctr == 3'd3) begin
                        block_addr_ip <= '0;
                        rd_idx_ip <= '0;
                        wt_addr_ip <= '0;
                        drain_ctr <= '0;

                        if(phase_idx_ip == NUM_PHASES - 1) begin
                            state <= FC1_DONE;
                        end else begin
                            phase_idx_ip <= phase_idx_ip + 1;
                            calc_en <= 1;
                            state <= FC1_CALC;
                        end
                    end
                end

                FC1_DONE: begin
                    drain_ctr <= drain_ctr + 1;

                    if(drain_ctr == 3'd3) begin
                        done <= 1;
                        state <= FC1_IDLE;
                    end
                end
            endcase
        end
    end
endmodule
