`timescale 1ns / 1ps

// Internally implements flattening

module fc1_mem#(
    parameter int NUM_LANES = 16
)(
    input logic clk,
    input logic rst_n,

    input logic [7:0] pool_result [0:15],
    input logic [7:0] pool_res_addr,
    input logic pool_res_v,

    input logic [3:0] block_addr_ip,
    input logic [7:0] idx_addr_ip,
    input logic [13:0] weight_addr_ip,
    input logic rd_v,

    output logic [7:0] rd_data,
    output logic signed [7:0] rd_weight [0:NUM_LANES-1],
    output logic data_v
);

    localparam int NUM_CHANNELS = 16;
    localparam int SPATIAL = 144;
    localparam int NUM_NEURONS = 64;
    localparam int NEURONS_PER_LANE = NUM_NEURONS / NUM_LANES;
    localparam int PER_LANE = NEURONS_PER_LANE * NUM_CHANNELS * SPATIAL;

    (* ram_style = "block" *)
    logic [7:0] data_mem [0:NUM_CHANNELS-1][0:SPATIAL-1];

    for(genvar c = 0; c < NUM_CHANNELS; c = c + 1) begin : gen_fc1_bank
        always_ff @ (posedge clk) begin
            if(pool_res_v) begin
                data_mem[c][pool_res_addr] <= pool_result[c];
            end
        end
    end : gen_fc1_bank

    for(genvar l = 0; l < NUM_LANES; l = l + 1) begin : gen_weight_lane
        (* ram_style = "block" *)
        logic signed [7:0] weight_mem [0:PER_LANE-1];

        initial begin
            $readmemh($sformatf("fc1_w_%0d.mem", l), weight_mem);
        end

        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                rd_weight[l] <= 0;
            end else begin
                rd_weight[l] <= weight_mem[weight_addr_ip];
            end
        end
    end : gen_weight_lane

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            rd_data <= 0;
        end else begin
            rd_data <= data_mem[block_addr_ip][idx_addr_ip];
        end
    end

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            data_v <= 0;
        end else begin
            data_v <= rd_v;
        end
    end
endmodule
