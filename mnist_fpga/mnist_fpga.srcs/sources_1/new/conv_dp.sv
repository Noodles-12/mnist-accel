`timescale 1ns / 1ps

module conv_dp#(
    parameter int NUM_LANES = 25
)(
    input logic clk,
    input logic rst_n,

    // Pixel input array for the MAC array
    input logic area_pixel_v,                       // conv_mem -> here : area_pixel valid
    input logic [7:0] area_pixel [0:24],

    // Weight input array for the MAC array
    input logic lane_weights_v,                     // conv_mem -> here : lane_weights valid
    input logic signed [7:0] lane_weights [0:24],
    input logic [3:0] filter_idx,

    input logic [9:0] out_addr,

    // Signal to tell conv_layer FSM to move to CONV_FILTER
    output logic wt_load_done,                      // here -> conv_layer FSM : MACs latched weights
    output logic calc_v,
    output logic [9:0] res_addr
);
    // Offest -> MAC Array
    logic signed [7:0] corrected_actv [0:24];
    logic [3:0] filter_idx_reg;


    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_offset_array
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                corrected_actv[p] <= 0;
                filter_idx_reg <= 0;
            end else begin
                corrected_actv[p] <= $signed({1'b0, area_pixel[p]}) - 9'sd128;
                
                if(lane_weights_v) begin
                    filter_idx_reg <= filter_idx;
                end
            end
        end
    end : gen_offset_array

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            wt_load_done <= 0;
            calc_v <= 0;
        end else begin
            wt_load_done <= lane_weights_v;
        end
    end

    // MAC Array -> Adder Tree
    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_mac_array
        mac_unit mac_u(
            .clk(clk),
            .rst_n(rst_n),

            .load_weight(lane_weights_v),
            .weight(lane_weights[p]),

            .activation(corrected_actv[p]),

            .op()
        );
    end : gen_mac_array


endmodule
