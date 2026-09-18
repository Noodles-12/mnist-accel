`timescale 1ns / 1ps

module fc1_addr_calc(
    input logic clk,
    input logic rst_n,

    input logic [3:0] block_addr,
    input logic [7:0] idx_addr,

    input logic [11:0] wt_ip_addr,
    input logic [7:0] neuron_idx,

    output logic [17:0] weight_addr_op,
    output logic [3:0] block_addr_op,
    output logic [7:0] idx_addr_op
);

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            weight_addr_op <= '0;
            block_addr_op <= '0;
            idx_addr_op <= '0;
        end else begin
            weight_addr_op <= 2304 * neuron_idx + wt_ip_addr;
            block_addr_op <= block_addr;
            idx_addr_op <= idx_addr;
        end
    end
endmodule
