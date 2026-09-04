`timescale 1ns / 1ps

module conv_addr_calc#(
    parameter int NUM_LANES  = 25,
    parameter int IMG_WIDTH  = 28,
    parameter int IMG_HEIGHT = 28,
    parameter int KERNEL     = 5
)(
    input logic clk,
    input logic rst_n,
    input logic sweep_en,               // conv_layer FSM -> here : run the window sweep

    input logic [3:0] filter_idx,
    input logic [5:0] idx_x,
    input logic [5:0] idx_y,

    (* use_dsp = "yes" *)
    output logic [9:0] img_rd_addr [0:24],
    output logic img_addrs_v,           // here -> conv_mem : img_rd_addr valid
    output logic [9:0] out_addr         // here -> output mem : dest for this window's result
);

    localparam int signed OFFSETS[0:4] = '{-2, -1, 0, 1, 2};

    localparam int IDX_MIN = KERNEL / 2;                 // 2  : first valid window center
    localparam int OUT_WIDTH = IMG_WIDTH  - KERNEL + 1;    // 24 : output feature map width
    localparam int OUT_HEIGHT = IMG_HEIGHT - KERNEL + 1;    // 24 : output feature map height

    logic [5:0] row [0:24];
    logic [5:0] col [0:24];

    logic [4:0] out_x, out_y;           // window center rebased to 0,0 of the output map

    logic sweep_en_d1;                  // stage-1 delay of sweep_en (matches row/col)

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            sweep_en_d1 <= 0;
            img_addrs_v <= 0;
        end else begin
            sweep_en_d1 <= sweep_en;
            img_addrs_v <= sweep_en_d1;
        end
    end

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            out_x <= 0;
            out_y <= 0;
            out_addr <= 0;
        end else begin
            out_x <= idx_x - IDX_MIN;
            out_y <= idx_y - IDX_MIN;

            out_addr <= out_y * OUT_WIDTH + out_x;
        end
    end

    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_conv_addrs
        localparam int DY_IDX = p / 5;
        localparam int DX_IDX = p % 5;

        always_ff @ (posedge clk) begin
             if(!rst_n) begin
                row[p] <= 0;
                col[p] <= 0;
             end else begin
                row[p] <= OFFSETS[DY_IDX] + idx_y;
                col[p] <= OFFSETS[DX_IDX] + idx_x;
             end
        end

        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                img_rd_addr[p] <= 0;
            end else begin
                img_rd_addr[p] <= IMG_WIDTH * row[p] + col[p];

            end
        end
    end : gen_conv_addrs

endmodule
