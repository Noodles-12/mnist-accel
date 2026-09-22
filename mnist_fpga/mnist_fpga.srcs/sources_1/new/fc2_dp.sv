`timescale 1ns / 1ps

module fc2_dp#(
    parameter int NUM_LANES = 10
)(
    input logic clk,
    input logic rst_n,
    input logic data_v,
    input logic done_v,

    input logic [7:0] data,
    input logic signed [7:0] weights [0:NUM_LANES-1],

    output logic signed [31:0] res [0:NUM_LANES-1],
    output logic res_v
);

    (* rom_style = "distributed" *)
    logic signed [31:0] bias_mem [0:NUM_LANES-1];

    initial begin
        $readmemh("fc2_bias.mem", bias_mem);
    end

    logic signed [8:0] corrected_data;
    assign corrected_data = $signed({1'b0, data}) - 9'sd128;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            res_v <= 1'b0;
        end else begin
            res_v <= done_v;
        end
    end

    for(genvar p = 0; p < NUM_LANES; p = p + 1) begin : gen_lane
        logic signed [31:0] acc;

        (* use_dsp = "yes" *)
        logic signed [16:0] mac_prod;
        logic mac_prod_v;

        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                mac_prod <= '0;
                mac_prod_v <= 1'b0;
            end else begin
                mac_prod <= weights[p] * corrected_data;
                mac_prod_v <= data_v;
            end
        end

        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                acc <= '0;
                res[p] <= '0;
            end else if(done_v) begin
                res[p] <= acc + bias_mem[p];
                acc <= '0;
            end else if(mac_prod_v) begin
                acc <= acc + mac_prod;
            end
        end
    end : gen_lane
endmodule
