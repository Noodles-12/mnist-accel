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

    input logic img_wr_en,
    input logic [9:0] img_wr_addr,
    input logic [7:0] img_wr_data,

    input logic [9:0] img_rd_addr [0:24],

    output logic signed [7:0] area_pixel [0:24],
    output logic signed [7:0] lane_weights [0:24]
);

    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_weight_lane

        (* ram_style = "block" *) 
        logic signed [7:0] weight_mem [0:NUM_FILTERS-1];

        initial begin
            $readmemh();
        end

        always_ff @ (posedge clk) begin
            if(!rst_n) begin
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
