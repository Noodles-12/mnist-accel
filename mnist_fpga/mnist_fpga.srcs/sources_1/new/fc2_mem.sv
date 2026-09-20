`timescale 1ns/1ps

module fc2_mem(
    input logic clk,
    input logic rst_n,

    input logic [7:0] wr_data [0:15],
    input logic [7:0] wr_addr [0:15],
    input logic wr_v,

    input logic [5:0] rd_addr,
    input logic rd_v,

    output logic signed [7:0] rd_weights [0:9],
    output logic [7:0] rd_data
);

    // Trying to not inference BRAM with this (LUTRAM or whatever has parallel writes)
    (* ram_style = "registers" *)
    logic [7:0] memory [0:63];

    (* rom_style = "distributed" *)
    logic signed [7:0] weights [0:9][0:63];

    initial begin
        $readmemh("fc2_weights.mem", weights);
    end

    for(genvar p = 0; p < 16; p = p + 1) begin
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                memory[wr_addr[p]] <= '0;
            end else begin
                if(wr_v)
                    memory[wr_addr[p]] <= wr_data[p];
            end
        end
    end

    for(genvar p = 0; p < 10; p = p + 1) begin
        always_ff @ (posedge clk) begin
            if(!rst_n) begin
                rd_weight[p] <= 0;
            end else begin
                rd_weight[p] <= weights[p][rd_addr];
            end
        end
    end
endmodule