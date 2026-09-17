`timescale 1ns / 1ps

module flatten_layer(
    input logic clk,
    input logic rst_n,

    input logic [31:0] pool_result [0:15],
    input logic [7:0] pool_res_addr,
    input logic pool_res_v,

    input logic [3:0] rd_block_addr,
    input logic [7:0] rd_idx_addr,
    output logic [31:0] rd_data,

    output logic done
);

    localparam int NUM_CHANNELS = 16;
    localparam int SPATIAL = 144;

    (* ram_style = "block" *)
    logic [31:0] flat_mem [0:NUM_CHANNELS-1][0:SPATIAL-1];

    logic [31:0] bank_rd [0:NUM_CHANNELS-1];
    logic [3:0] rd_block_addr_reg;

    logic [7:0] wr_count;

    for(genvar c = 0; c < NUM_CHANNELS; c = c + 1) begin : gen_flat_bank
        always_ff @ (posedge clk) begin
            if(pool_res_v) begin
                flat_mem[c][pool_res_addr] <= pool_result[c];
            end

            if(!rst_n) begin
                bank_rd[c] <= '0;
            end else begin
                bank_rd[c] <= flat_mem[c][rd_idx_addr];
            end
        end
    end : gen_flat_bank

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            rd_block_addr_reg <= 0;
        end else begin
            rd_block_addr_reg <= rd_block_addr;
        end
    end

    assign rd_data = bank_rd[rd_block_addr_reg];

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            wr_count <= 0;
            done <= 0;
        end else begin
            if(pool_res_v) begin
                if(pool_res_addr == 0) begin
                    wr_count <= 1;
                    done <= 0;
                end else if(wr_count < SPATIAL) begin
                    wr_count <= wr_count + 1;
                end
            end

            if(wr_count == SPATIAL)
                done <= 1;
        end
    end

endmodule
