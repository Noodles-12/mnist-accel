`timescale 1ns / 1ps

module pool_dp(
    input logic clk,
    input logic rst_n,

    input logic [31:0] data_ip [0:15][0:3],
    input logic [7:0] res_addr,
    input logic data_v,

    output logic [31:0] res [0:15],
    output logic [7:0] res_addr_op,
    output logic res_v
);

    logic [31:0] comp_a [0:15];
    logic [31:0] comp_b [0:15];

    logic [7:0] res_addr_reg;
    logic data_v_reg;

    for(genvar p = 0; p < 16; p = p + 1) begin
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                comp_a[p] <= '0;
                comp_b[p] <= '0;

                res[p] <= '0;
            end else begin
                comp_a[p] <= (data_ip[p][0] > data_ip[p][1]) ? data_ip[p][0] : data_ip[p][1];
                comp_b[p] <= (data_ip[p][2] > data_ip[p][3]) ? data_ip[p][2] : data_ip[p][3];

                res[p] <= (comp_a[p] > comp_b[p]) ? comp_a[p] : comp_b[p];
            end
        end
    end

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            res_addr_reg <= '0;
            res_addr_op <= '0;

            data_v_reg <= 0;
            res_v <= 0;
        end else begin
            res_addr_reg <= res_addr;
            res_addr_op <= res_addr_reg;

            data_v_reg <= data_v;
            res_v <= data_v_reg;
        end
    end
endmodule
