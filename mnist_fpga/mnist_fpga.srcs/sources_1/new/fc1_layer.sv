`timescale 1ns / 1ps

module fc1_layer(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic [31:0] pool_result [0:15],
    input logic [7:0] pool_res_addr,
    input logic pool_res_v
);

    typedef enum logic [1:0] {
        FC1_IDLE,
        FC1_CALC,
        FC1_DONE
    } fc1_state;

    fc1_state state;

    logic [3:0] rd_block_addr;
    logic [7:0] rd_idx_addr;
    logic [31:0] rd_data;

    logic [11:0] wt_ip_addr; // weight address to get
    logic [7:0] neuron_idx; // neuron address to get
    logic calc_en;

    fc1_addr_calc fc1ac(
        .clk(clk),
        .rst_n(rst_n),

        .block_addr(rd_block_addr),
        .idx_addr(rd_idx_addr),
        .wt_ip_addr(wt_ip_addr),
        .neuron_idx(neuron_idx),

        .weight_addr_op(),
        .block_addr_op(),
        .idx_addr_op()
    );

    fc1_mem fc1mem(
        .clk(clk),
        .rst_n(rst_n),

        .pool_result(pool_result),
        .pool_res_addr(pool_res_addr),
        .pool_res_v(pool_res_v),

        .rd_block_addr(rd_block_addr),
        .rd_idx_addr(rd_idx_addr),
        .rd_v(calc_en),

        .rd_data(rd_data)
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= FC1_IDLE;

            rd_block_addr <= 0;
            rd_idx_addr <= 0;
            rd_data <= 0;
            calc_en <= 0;
            wt_addr <= 0;
        end else begin
            case(state)
                FC1_IDLE: begin
                    rd_block_addr <= 0;
                    rd_idx_addr <= 0;
                    rd_data <= 0;
                    calc_en <= 0;
                    wt_addr <= 0;

                    if(en) begin
                        state <= FC1_CALC;
                    end
                end

                FC1_CALC: begin
                    
                end
            endcase
        end
    end

endmodule
