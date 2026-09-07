`timescale 1ns / 1ps

module max_pool(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic wr_en,
    input logic [31:0] wr_data,
    input logic [9:0] wr_mem_addr,
    input logic [3:0] wr_filter_addr
);

    typedef enum logic[1:0] {
        POOL_IDLE,
        POOL_EXEC,
        POOL_DONE
    } pool_state;

    pool_state state;

    logic [5:0] idx_x, idx_x_reg;
    logic [5:0] idx_y, idx_y_reg;

    pool_addr_calc pac(
        .clk(clk),
        .rst_n(rst_n),
        .comp_en(),

        .idx_x(idx_x_reg),
        .idx_y(idx_y_reg),

        .addr_op(),
        .addrs_v()
    );

    pool_mem pm(
        .clk(clk),
        .rst_n(rst_n),

        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_mem_addr(wr_mem_addr),
        .wr_filter_addr(wr_filter_addr),

        .rd_en(),
        .rd_addr(),

        .rd_data()
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= POOL_IDLE;
            idx_x <= 0;
            idx_y <= 0;

            idx_x_reg <= 0;
            idx_y_reg <= 0;
        end else begin
            unique case(state) 
                POOL_IDLE : begin
                    idx_x <= 0;
                    idx_y <= 0;

                    idx_x_reg <= 0;
                    idx_y_reg <= 0;
                end

                POOL_EXEC : begin

                end
            endcase
        end
    end
endmodule
