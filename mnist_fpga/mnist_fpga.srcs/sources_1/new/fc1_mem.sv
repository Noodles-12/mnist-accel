`timescale 1ns / 1ps

module fc1_mem(
    input logic clk,
    input logic rst_n,

    input logic [31:0] pool_result [0:15],
    input logic [7:0] pool_res_addr,
    input logic pool_res_v,

    input logic [3:0] rd_block_addr,
    input logic [7:0] rd_idx_addr,
    
    output logic [31:0] rd_data
    );
endmodule
