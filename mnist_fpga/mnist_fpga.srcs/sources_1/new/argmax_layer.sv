`timescale 1ns / 1ps

module argmax_layer(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic signed [15:0] data_in [0:9],
    input logic data_v,

    output logic done_v,
    output logic wr_v,

    output logic [3:0] res,
    output logic res_v
);

    logic signed [15:0] data [0:9];

    // Receiving data from fc2_layer
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            wr_v <= '0;
            data <= '0;
        end else begin
            if(data_v) begin
                data <= data_in;
                wr_v <= 1'b1;
            end else begin
                wr_v <= 1'b0;
            end
        end
    end

    // Argmax calculation
    // Doing a full comparision in one cycle
    // If timing fails, do a comparision reduction tree
    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            res <= '0;
            res_v <= '0;
            done_v <= '0;
        end else begin
            if(wr_v) begin
                res <= 0;
                for(int i = 1; i < 10; i++) begin
                    if(data[i] > data[res]) begin
                        res <= i;
                    end
                end
                res_v <= 1'b1;
                done_v <= 1'b1;
            end else begin
                res_v <= 1'b0;
                done_v <= 1'b0;
            end
        end
    end

endmodule
