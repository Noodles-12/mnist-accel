`timescale 1ns / 1ps

module fc1_layer(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic [31:0] pool_result [0:15],
    input logic [7:0] pool_res_addr,
    input logic pool_res_v
);
endmodule
