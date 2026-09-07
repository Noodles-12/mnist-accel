`timescale 1ns / 1ps

module pool_addr_calc(
    input logic clk,
    input logic rst_n,
    input logic comp_en,

    input logic [5:0] idx_x,
    input logic [5:0] idx_y,

    output logic [9:0] addr_op [0:3],
    output logic addrs_v
);

    logic [5:0] idx_xs [0:3];
    logic [5:0] idx_ys [0:3];

    logic comp_en_reg;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            comp_en_reg <= 0;
            addrs_v <= 0;
        end else begin
            comp_en_reg <= comp_en;
            addrs_v <= comp_en_reg;
        end
    end

    for(genvar i = 0; i < 4; i = i + 1) begin : gen_pool_idx
        localparam int DX = i % 2;
        localparam int DY = i / 2;
 
        always_ff @ (posedge clk) begin
            if (!rst_n) begin
                idx_xs[i] <= 0;
                idx_ys[i] <= 0;
            end else begin
                idx_xs[i] <= idx_x + DX;
                idx_ys[i] <= idx_y + DY;
            end
        end
    end : gen_pool_idx

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            for(int i = 0; i < 3; i++)
                addr_op[i] <= 0;
        end else begin
            for(int i = 0; i < 3; i++)
                addr_op[i] <= 24 * idx_ys[i] + idx_xs[i];
        end
    end
endmodule
