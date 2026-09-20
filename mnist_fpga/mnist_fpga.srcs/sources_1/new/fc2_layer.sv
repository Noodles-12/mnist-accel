`timescale 1ns / 1ps

module fc2_layer(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic [7:0] wr_data [0:15],
    input logic [7:0] wr_addr [0:15],
    input logic wr_v
);

    typedef enum logic [1:0] {
        FC2_IDLE,
        FC2_CALC
    } fc2_state;

    fc2_state state;

    // Might not need an addr_calc module
    logic [5:0] idx_addr;
    logic calc_en;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= FC2_IDLE;
            idx_addr <= '0;
            calc_en <= '0;
        end else begin
            unique case(state)
                FC2_IDLE: begin
                    
                end
            endcase
        end
    end

endmodule
