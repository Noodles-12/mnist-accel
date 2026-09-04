`timescale 1ns / 1ps

module conv_dp#(
    parameter int NUM_LANES = 25
)(
    input logic clk,
    input logic rst_n,

    // Pixel input array for the MAC array
    input logic calc_en,
    input logic [7:0] area_pixel [0:24],

    // Weight input array for the MAC array
    input logic valid_weights,
    input logic signed [7:0] lane_weights [0:24],

    // Signal to tell conv_layer FSM to move to CONV_FILTER
    output logic weights_loaded
);
    // Offest -> MAC Array
    logic signed [7:0] corrected_actv [0:24];

    

    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_offset_array
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                corrected_actv[p] <= 0;
            end else begin
                corrected_actv[p] <= $signed({1'b0, area_pixel[p]}) - 8'sd128;
            end
        end
    end : gen_offset_array

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            weights_loaded <= 0;
        end else begin
            weights_loaded <= valid_weights;
        end
    end

    // MAC Array -> Adder Tree
    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_mac_array
        mac_unit mac_u(
            .clk(clk),
            .rst_n(rst_n),

            .load_weight(valid_weights),
            .weight(lane_weights[p]),

            .activation(corrected_actv[p]),
            
            .op()
        );
    end : gen_mac_array


endmodule
