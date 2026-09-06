`timescale 1ns / 1ps

module pool_mem(
    input logic clk,
    input logic rst_n,

    input logic wr_en,
    input logic [31:0] wr_data,
    input logic [9:0] wr_mem_addr,
    input logic [3:0] wr_filter_addr
);

    for(genvar p = 0; p < 16; p = p + 1) begin : gen_pool_mem
        (* ram_style = "block" *)
        logic [31:0] pool_mem [0:575];

        always_ff @ (posedge clk) begin
            if(!rst_n) begin

            end else begin
                if(wr_en) begin
                    if(wr_filter_addr == p) begin
                        pool_mem[wr_filter_addr] <= wr_data;
                    end
                end
            end
        end
    end : gen_pool_mem
endmodule
