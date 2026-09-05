`timescale 1ns / 1ps

module adder #(
    parameter int INPUT_LENGTH = 16
)(
    input  logic clk,
    input  logic rst_n,
    input  logic signed [INPUT_LENGTH-1:0]   a_ip,
    input  logic signed [INPUT_LENGTH-1:0]   b_ip,

    output logic signed [INPUT_LENGTH:0]     op
);
    always_ff @ (posedge clk) begin
        if (!rst_n) begin
            op <= '0;
        end else begin
            op <= a_ip + b_ip;
        end
    end
endmodule