`timescale 1ns / 1ps

// Internally implements flattening

module fc1_mem(
    input logic clk,
    input logic rst_n,

    input logic [31:0] pool_result [0:15],
    input logic [7:0] pool_res_addr,
    input logic pool_res_v,

    input logic [3:0] rd_block_addr,
    input logic [7:0] rd_idx_addr,
    input logic rd_v,
    
    output logic [31:0] rd_data
);

    localparam int NUM_CHANNELS = 16;
    localparam int SPATIAL = 144;
    localparam int NUM_NEURONS = 64;

    (* ram_style = "block" *)
    logic [31:0] dat_mem [0:NUM_CHANNELS-1][0:SPATIAL-1];

    (* ram_style = "block" *) // Might be too big?
    logic [7:0] weight_mem [0:(NUM_CHANNELS*SPATIAL*NUM_NEURONS)-1];

    for(genvar c = 0; c < NUM_CHANNELS; c = c + 1) begin : gen_fc1_bank
        always_ff @ (posedge clk) begin
            if(pool_res_v) begin
                dat_mem[c][pool_res_addr] <= pool_result[c];
            end
        end
    end : gen_fc1_bank

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            rd_data <= 0;
        end else begin
            rd_data <= dat_mem[rd_block_addr][rd_idx_addr];
        end
    end
endmodule
