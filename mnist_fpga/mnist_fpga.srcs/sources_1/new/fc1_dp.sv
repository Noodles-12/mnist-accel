`timescale 1ns / 1ps

module fc1_dp#(
    parameter int NUM_LANES = 16,
    parameter int NUM_NEURONS = 64,
    parameter int REQUANT_M0 = 45,
    parameter int REQUANT_SHIFT = 16,
    parameter int REQUANT_ZERO_POINT = 128
)(
    input logic clk,
    input logic rst_n,
    input logic data_v,

    input logic [7:0] data,
    input logic signed [7:0] weight [0:NUM_LANES-1],

    input logic [1:0] phase_idx,
    input logic res_en,

    output logic [7:0] res [0:NUM_LANES-1],
    output logic [7:0] res_addr [0:NUM_LANES-1],
    output logic res_v
);

    localparam int NEURONS_PER_LANE = NUM_NEURONS / NUM_LANES;

    localparam logic signed [63:0] REQUANT_ROUND_BIAS =
        (REQUANT_SHIFT > 0) ? (64'sd1 <<< (REQUANT_SHIFT - 1)) : 64'sd0;

    (* ram_style = "distributed" *)
    logic signed [31:0] bias_mem [0:NUM_NEURONS-1];

    initial begin
        $readmemh("fc1_bias.mem", bias_mem);
    end

    logic signed [8:0] corrected_data;
    assign corrected_data = $signed({1'b0, data}) - 9'sd128;

    logic [1:0] phase_d1, phase_d2;
    logic res_en_d1, res_en_d2;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            phase_d1 <= '0;
            phase_d2 <= '0;
            res_en_d1 <= 0;
            res_en_d2 <= 0;
            res_v <= 0;
        end else begin
            phase_d1 <= phase_idx;
            phase_d2 <= phase_d1;
            res_en_d1 <= res_en;
            res_en_d2 <= res_en_d1;
            res_v <= res_en_d2;
        end
    end

    for(genvar l = 0; l < NUM_LANES; l = l + 1) begin : gen_mac_lane
        localparam int NEURON_BASE = l * NEURONS_PER_LANE;

        logic signed [31:0] calc;
        logic signed [31:0] biased_res;
        logic signed [31:0] relu_res;

        // MAC
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                calc <= '0;
            end else if(res_en) begin
                calc <= '0;
            end else if(data_v) begin
                calc <= calc + weight[l] * corrected_data;
            end
        end

        // Bias
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                biased_res <= '0;
            end else begin
                biased_res <= calc + bias_mem[NEURON_BASE + phase_idx];
            end
        end

        // ReLu
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                relu_res <= '0;
            end else begin
                relu_res <= (biased_res > 0) ? biased_res : '0;
            end
        end

        // Requantize
        logic signed [63:0] requant_prod;
        logic signed [31:0] requant_shifted;
        logic signed [31:0] requant_offset;
        logic [7:0] requant_clamped;

        always_comb begin
            requant_prod    = relu_res * REQUANT_M0 + REQUANT_ROUND_BIAS;
            requant_shifted = requant_prod >>> REQUANT_SHIFT;
            requant_offset  = requant_shifted + REQUANT_ZERO_POINT;

            if(requant_offset > 255)
                requant_clamped = 8'd255;
            else if(requant_offset < 0)
                requant_clamped = 8'd0;
            else
                requant_clamped = requant_offset[7:0];
        end

        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                res[l] <= '0;
                res_addr[l] <= '0;
            end else begin
                res[l] <= requant_clamped;
                res_addr[l] <= NEURON_BASE + phase_d2;
            end
        end
    end : gen_mac_lane
endmodule
