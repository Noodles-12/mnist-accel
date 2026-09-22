`timescale 1ns / 1ps

module conv_dp#(
    parameter int NUM_LANES = 25,
    parameter int NUM_FILTERS = 16,
    parameter int REQUANT_M0 = 77,
    parameter int REQUANT_SHIFT = 16,
    parameter int REQUANT_ZERO_POINT = 128
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
    output logic [7:0] final_res,
    output logic [9:0] res_addr,
    output logic [3:0] filter_addr
);
    (* ram_style = "distributed" *)
    logic signed [31:0] bias_mem [0:NUM_FILTERS-1];

    initial begin
        $readmemh("conv1_bias.mem", bias_mem);
    end

    logic signed [31:0] bias_reg;

    logic signed [7:0] corrected_actv [0:24];   // Offest -> MAC Array
    logic signed [15:0] mac_arr_op [0:24];
    logic signed [16:0] adder1_op [0:15];
    logic signed [17:0] adder2_op [0:7];
    logic signed [18:0] adder3_op [0:3];
    logic signed [19:0] adder4_op [0:1];
    logic signed [20:0] adder_fin;
    logic signed [31:0] biased_res;
    logic signed [31:0] relu_res;

    // Cycles from the area_pixel_v / out_addr inputs through to final_res:
    // 1 corrected_actv + 2 mac_unit + 5 adder tree + 1 bias + 1 relu + 2 requantize
    localparam int DP_LATENCY = 12;

    logic calc_v_pipe [0:DP_LATENCY-1];             // area_pixel_v walked alongside the data
    logic [9:0] res_addr_pipe [0:DP_LATENCY-1];     // out_addr walked alongside the data

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            wt_load_done <= 0;
            filter_addr <= 0;
            bias_reg <= 0;
        end else begin
            wt_load_done <= lane_weights_v;
            
            if(lane_weights_v) begin
                filter_addr <= filter_idx;
                bias_reg <= bias_mem[filter_idx];
            end
        end
    end

    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_offset_array
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                corrected_actv[p] <= 0;
            end else begin
                corrected_actv[p] <= $signed({1'b0, area_pixel[p]}) - 9'sd128;
            end
        end
    end : gen_offset_array

    // MAC Array -> Adder Tree
    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_mac_array
        mac_unit mac_u(
            .clk(clk),
            .rst_n(rst_n),

            .load_weight(lane_weights_v),
            .weight(lane_weights[p]),

            .activation(corrected_actv[p]),

            .op(mac_arr_op[p])
        );
    end : gen_mac_array

    // Pad the 25 MAC lanes out to 32 so the tree halves cleanly at every stage
    for(genvar p = 0; p < 31; p = p + 2) begin : gen_adder1
        logic signed [15:0] a_pad, b_pad;

        // generate-if, not a ternary: mac_arr_op[25..31] must never be elaborated
        if(p < NUM_LANES)     
            assign a_pad = mac_arr_op[p];
        else                  
            assign a_pad = '0;

        if(p + 1 < NUM_LANES)
            assign b_pad = mac_arr_op[p+1];
        else                  
            assign b_pad = '0;

        adder a_u1(
            .clk(clk),
            .rst_n(rst_n),
            .a_ip(a_pad),
            .b_ip(b_pad),
            .op(adder1_op[p/2])
        );
    end : gen_adder1

    for(genvar p = 0; p < 15; p = p + 2) begin : gen_adder2
        adder #(
            .INPUT_LENGTH(17)
        ) a_u2(
            .clk(clk),
            .rst_n(rst_n),
            .a_ip(adder1_op[p]),
            .b_ip(adder1_op[p + 1]),
            .op(adder2_op[p/2])
        );
    end : gen_adder2

    for(genvar p = 0; p < 7; p = p + 2) begin : gen_adder3
        adder #(
            .INPUT_LENGTH(18)
        ) a_u3(
            .clk(clk),
            .rst_n(rst_n),
            .a_ip(adder2_op[p]),
            .b_ip(adder2_op[p + 1]),
            .op(adder3_op[p/2])
        );
    end : gen_adder3

    for(genvar p = 0; p < 3; p = p + 2) begin : gen_adder4
        adder #(
            .INPUT_LENGTH(19)
        ) a_u3(
            .clk(clk),
            .rst_n(rst_n),
            .a_ip(adder3_op[p]),
            .b_ip(adder3_op[p + 1]),
            .op(adder4_op[p/2])
        );
    end : gen_adder4

    adder #(
        .INPUT_LENGTH(20)
    ) a_final(
        .clk(clk),
        .rst_n(rst_n),
        .a_ip(adder4_op[0]),
        .b_ip(adder4_op[1]),
        .op(adder_fin)
    );

    // Bias
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            biased_res <= '0;
        end else begin
            biased_res <= adder_fin + bias_reg;
        end
    end

    // ReLu
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            relu_res <= '0;
        end else begin
            if(biased_res > 0)
                relu_res <= biased_res;
            else
                relu_res <= '0;
        end
    end

    // Requantize
    logic signed [63:0] requant_prod;
    logic signed [31:0] requant_shifted;
    logic signed [31:0] requant_shifted_reg;
    logic signed [31:0] requant_offset;
    logic [7:0] requant_clamped;

    localparam logic signed [63:0] REQUANT_ROUND_BIAS =
        (REQUANT_SHIFT > 0) ? (64'sd1 <<< (REQUANT_SHIFT - 1)) : 64'sd0;

    always_comb begin
        requant_prod    = relu_res * REQUANT_M0 + REQUANT_ROUND_BIAS;
        requant_shifted = requant_prod >>> REQUANT_SHIFT;
    end

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            requant_shifted_reg <= '0;
        end else begin
            requant_shifted_reg <= requant_shifted;
        end
    end

    always_comb begin
        requant_offset = requant_shifted_reg + REQUANT_ZERO_POINT;

        if(requant_offset > 255)
            requant_clamped = 8'd255;
        else if(requant_offset < 0)
            requant_clamped = 8'd0;
        else
            requant_clamped = requant_offset[7:0];
    end

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            final_res <= '0;
        end else begin
            final_res <= requant_clamped;
        end
    end

    // calc_v / res_addr ride the same number of stages as the data, so they
    // come out describing the final_res presented on the same cycle
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            for(int i = 0; i < DP_LATENCY; i++) begin
                calc_v_pipe[i] <= 0;
                res_addr_pipe[i] <= 0;
            end
        end else begin
            calc_v_pipe[0] <= area_pixel_v;
            res_addr_pipe[0] <= out_addr;

            for(int i = 1; i < DP_LATENCY; i++) begin
                calc_v_pipe[i] <= calc_v_pipe[i-1];
                res_addr_pipe[i] <= res_addr_pipe[i-1];
            end
        end
    end

    assign calc_v   = calc_v_pipe[DP_LATENCY-1];
    assign res_addr = res_addr_pipe[DP_LATENCY-1];

endmodule
