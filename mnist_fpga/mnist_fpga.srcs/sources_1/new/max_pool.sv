`timescale 1ns / 1ps

module max_pool(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic wr_en,
    input logic [31:0] wr_data,
    input logic [9:0] wr_mem_addr,
    input logic [3:0] wr_filter_addr
);

    typedef enum logic[1:0] {
        POOL_IDLE,
        POOL_EXEC,
        POOL_DONE
    } pool_state;

    pool_state state;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= POOL_IDLE;
        end else begin

        end
    end
endmodule
