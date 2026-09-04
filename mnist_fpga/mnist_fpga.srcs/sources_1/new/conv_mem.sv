`timescale 1ns / 1ps

module conv_mem#(
    parameter int NUM_LANES = 25,
    parameter int NUM_FILTERS = 16,
    parameter int IMG_SIZE = 784
)(
    input logic clk,
    input logic rst_n,

    // The index of the weights the current state of the convolution datapath needs
    input logic [3:0] filter_idx,
    input logic filter_idx_v,                       // conv_layer FSM -> here : filter_idx valid

    // Filling in the image with the UART communication
    input logic img_wr_en,
    input logic [9:0] img_wr_addr,
    input logic [7:0] img_wr_data,

    input logic [9:0] img_rd_addr [0:24],
    input logic img_addrs_v,                        // conv_addr_calc -> here : img_rd_addr valid
    input logic [9:0] out_addr,

    output logic [7:0] area_pixel [0:24],
    output logic area_pixel_v,                      // here -> conv_dp : area_pixel valid
    output logic [9:0] out_addr_d1,
    output logic signed [7:0] lane_weights [0:24],
    output logic lane_weights_v                     // here -> conv_dp : lane_weights valid
);
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            lane_weights_v <= 0;
            area_pixel_v <= 0;
            out_addr_d1 <= 0;
        end else begin
            lane_weights_v <= filter_idx_v;
            area_pixel_v <= img_addrs_v;
            out_addr_d1 <= out_addr;
        end
    end

    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_weight_lane

        (* ram_style = "block" *)
        logic signed [7:0] weight_mem [0:NUM_FILTERS-1];

        initial begin
            $readmemh($sformatf("conv_w_%0d.mem", p), weight_mem);
        end

        always_ff @ (posedge clk) begin
            if(!rst_n || !filter_idx_v) begin // filter_idx_v possibly not needed (might even be worse) but makes simulation cleaner
                lane_weights[p] <= 0;
            end else begin
                lane_weights[p] <= weight_mem[filter_idx];
            end
        end
    end : gen_weight_lane

    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_image_buffer

        (* ram_style = "block" *)
        logic [7:0] img_mem [0:IMG_SIZE-1];

        always_ff @(posedge clk) begin
            if (img_wr_en) begin
                img_mem[img_wr_addr] <= img_wr_data;
            end

            if(!rst_n) begin
                area_pixel[p] <= 0;
            end else begin
                area_pixel[p] <= img_mem[img_rd_addr[p]];
            end
        end
    end : gen_image_buffer


endmodule
