`timescale 1ns / 1ps

module argmax_layer#(
    parameter int NUM_LANES = 10
)(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic signed [31:0] data_in [0:NUM_LANES-1],
    input logic data_v,

    output logic done_v,
    output logic wr_v,

    output logic [3:0] res,
    output logic res_v
);

    logic signed [31:0] data [0:NUM_LANES-1];

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            wr_v <= '0;
            for(int i = 0; i < NUM_LANES; i++)
                data[i] <= '0;
        end else begin
            if(data_v) begin
                data <= data_in;
                wr_v <= 1'b1;
            end else begin
                wr_v <= 1'b0;
            end
        end
    end

    logic signed [31:0] s0_val [0:4];
    logic [3:0] s0_idx [0:4];
    logic s0_v;

    logic signed [31:0] s1_val [0:2];
    logic [3:0] s1_idx [0:2];
    logic s1_v;

    logic signed [31:0] s2_val [0:1];
    logic [3:0] s2_idx [0:1];
    logic s2_v;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            s0_v <= '0;
            for(int i = 0; i < 5; i++) begin
                s0_val[i] <= '0;
                s0_idx[i] <= '0;
            end
        end else begin
            s0_v <= wr_v;
            for(int i = 0; i < 5; i++) begin
                if(data[2*i] >= data[2*i+1]) begin
                    s0_val[i] <= data[2*i];
                    s0_idx[i] <= i*2;
                end else begin
                    s0_val[i] <= data[2*i+1];
                    s0_idx[i] <= i*2+1;
                end
            end
        end
    end

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            s1_v <= '0;
            for(int i = 0; i < 3; i++) begin
                s1_val[i] <= '0;
                s1_idx[i] <= '0;
            end
        end else begin
            s1_v <= s0_v;
            if(s0_val[0] >= s0_val[1]) begin
                s1_val[0] <= s0_val[0];
                s1_idx[0] <= s0_idx[0];
            end else begin
                s1_val[0] <= s0_val[1];
                s1_idx[0] <= s0_idx[1];
            end
            if(s0_val[2] >= s0_val[3]) begin
                s1_val[1] <= s0_val[2];
                s1_idx[1] <= s0_idx[2];
            end else begin
                s1_val[1] <= s0_val[3];
                s1_idx[1] <= s0_idx[3];
            end
            s1_val[2] <= s0_val[4];
            s1_idx[2] <= s0_idx[4];
        end
    end

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            s2_v <= '0;
            s2_val[0] <= '0;
            s2_val[1] <= '0;
            s2_idx[0] <= '0;
            s2_idx[1] <= '0;
        end else begin
            s2_v <= s1_v;
            if(s1_val[0] >= s1_val[1]) begin
                s2_val[0] <= s1_val[0];
                s2_idx[0] <= s1_idx[0];
            end else begin
                s2_val[0] <= s1_val[1];
                s2_idx[0] <= s1_idx[1];
            end
            s2_val[1] <= s1_val[2];
            s2_idx[1] <= s1_idx[2];
        end
    end

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            res <= '0;
            res_v <= '0;
            done_v <= '0;
        end else begin
            res_v <= s2_v;
            done_v <= s2_v;
            if(s2_val[0] >= s2_val[1])
                res <= s2_idx[0];
            else
                res <= s2_idx[1];
        end
    end

endmodule
