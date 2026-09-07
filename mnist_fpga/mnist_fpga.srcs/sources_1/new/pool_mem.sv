`timescale 1ns / 1ps

module pool_mem(
    input logic clk,
    input logic rst_n,

    input logic wr_en,
    input logic [31:0] wr_data,
    input logic [9:0] wr_mem_addr,
    input logic [3:0] wr_filter_addr,

    input logic rd_en,
    input logic [9:0] rd_addr [0:3],

    output logic [9:0] rd_data [0:15][0:3];
);

    for(genvar p = 0; p < 16; p = p + 1) begin : gen_pool_mem
        for(genvar q = 0; q < 4; q = q + 1) begin : gen_clone
            (* ram_style = "block" *)
            logic [31:0] pool_mem [0:575];

            always_ff @ (posedge clk) begin
                if(wr_en && wr_filter_adr == p) begin
                    pool_mem[wr_filter_addr] <= wr_data;
                end

                if(!rst_n) begin
                    rd_data[p][q] <= '0;
                end else begin
                    rd_data[p][q] <= pool_mem[rd_addr[q]];
                end
            end
        end : gen_clone
    end : gen_pool_mem
endmodule
