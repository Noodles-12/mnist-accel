`timescale 1ns / 1ps

module conv_addr_calc#(
    parameter int NUM_LANES  = 25,
    parameter int IMG_WIDTH  = 28,
    parameter int IMG_HEIGHT = 28
)(
    input logic clk,
    input logic rst_n,
    input logic calc_en,

    input logic [3:0] filter_idx,
    input logic [5:0] idx_x,
    input logic [5:0] idx_y,

    (* use_dsp = "yes" *)
    output logic [9:0] img_rd_addr [0:24],
    output logic op_v,
    output logic [3:0] filter_idx_out

    // Add output that represents final address of 5x5 conv operation o/p in conv_layer output memory
);

    localparam int signed OFFSETS[0:4] = '{-2, -1, 0, 1, 2};

    logic [5:0] row [0:24];
    logic [5:0] col [0:24];

    logic rd_en_ff1;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            rd_en_ff1 <= 0;
            op_v <= 0;
        end else begin
            rd_en_ff1 <= calc_en;
            op_v <= rd_en_ff1;
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
                row[p] <= OFFSETS[DX_IDX] + idx_x;
                col[p] <= OFFSETS[DY_IDX] + idx_y;
             end
        end

        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                img_rd_addr[p] <= 0;
            end else begin
                img_rd_addr[p] <= IMG_WIDTH * col[p] + row[p];

            end
        end
    end : gen_conv_addrs

endmodule
