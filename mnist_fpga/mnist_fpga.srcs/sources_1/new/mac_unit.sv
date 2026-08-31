`timescale 1ns / 1ps

module mac_unit (
    input logic clk,
    input logic rst_n,
    input logic load_weight,
    input logic signed [7:0] weight,
    input logic signed [7:0] activation,
    
    output logic signed [15:0] op
);

    logic signed [7:0]  weight_reg;
    logic signed [7:0]  activation_reg;

    (* use_dsp = "yes" *) 
    logic signed [15:0] prod_reg;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            weight_reg <= 0;
        end else if(load_weight) begin
            weight_reg <= weight;
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            activation_reg <= '0;
            prod_reg <= '0;
        end else begin
            activation_reg <= activation;
            prod_reg <= weight_reg * activation_reg;
        end
    end

    assign op = prod_reg;

endmodule