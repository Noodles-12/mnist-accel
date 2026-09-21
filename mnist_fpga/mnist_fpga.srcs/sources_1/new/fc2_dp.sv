`timescale 1ns / 1ps

module fc2_dp(
    input logic clk,
    input logic rst_n,
    input logic data_v,
    input logic done_v,

    input logic [7:0] data,
    input logic signed [7:0] weights [0:9],

    output logic signed [15:0] res [0:9],
    output logic res_v
);

    logic signed [15:0] acc [0:9];

    for(genvar p = 0; p < 10; p = p + 1) begin
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                acc[p] <= '0;
                res[p] <= '0;
                res_v <= 1'b0;
            end else begin
                if(data_v)
                    acc[p] <= acc[p] + (data * weights[p]);

                if(done_v) begin
                    res[p] <= acc[p];
                    acc[p] <= '0;
                    res_v <= 1'b1;
                end else begin
                    res_v <= 1'b0;
                end
            end
        end
    end
endmodule
