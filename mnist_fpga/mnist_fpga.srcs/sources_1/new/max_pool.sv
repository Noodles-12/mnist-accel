`timescale 1ns / 1ps

module max_pool(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic wr_en,
    input logic [31:0] wr_data,
    input logic [9:0] wr_mem_addr,
    input logic [3:0] wr_filter_addr,

    output logic [31:0] result [0:15],
    output logic [7:0] res_addr,
    output logic res_v,
    output logic done
);

    typedef enum logic[1:0] {
        POOL_IDLE,
        POOL_EXEC,
        POOL_DONE
    } pool_state;

    pool_state state;

    logic [5:0] idx_x, idx_x_reg;
    logic [5:0] idx_y, idx_y_reg;
    logic comp_en;

    logic addrs_v;
    logic [9:0] addrs [3:0];
    logic [7:0] res_addr_a;

    logic [9:0] pool_data [0:15][0:3];
    logic [7:0] res_addr_b;
    logic data_v;

    logic [7:0] send_ctr, recv_ctr;

    pool_addr_calc pac(
        .clk(clk),
        .rst_n(rst_n),
        .comp_en(comp_en),

        .idx_x(idx_x_reg),
        .idx_y(idx_y_reg),

        .addr_op(addrs),
        .res_addr(res_addr_a),
        .addrs_v(addrs_v)
    );

    pool_mem pm(
        .clk(clk),
        .rst_n(rst_n),

        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_mem_addr(wr_mem_addr),
        .wr_filter_addr(wr_filter_addr),

        .res_addr_ip(res_addr_a),
        .rd_en(addrs_v),
        .rd_addr(addrs),

        .rd_data(pool_data),
        .res_addr_op(res_addr_b),
        .data_v(data_v)
    );

    pool_dp pdb(
        .clk(clk),
        .rst_n(rst_n),

        .data_ip(pool_data),
        .res_addr(res_addr_b),
        .data_v(data_v),

        .res(result),
        .res_addr(res_addr),
        .res_v(res_v)
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= POOL_IDLE;
            idx_x <= 0;
            idx_y <= 0;

            idx_x_reg <= 0;
            idx_y_reg <= 0;

            send_ctr <= '0;
            recv_ctr <= '0;

            comp_en <= 0;
            done <= 0;
        end else begin
            unique case(state) 
                POOL_IDLE : begin
                    idx_x <= 0;
                    idx_y <= 0;

                    idx_x_reg <= 0;
                    idx_y_reg <= 0;

                    send_ctr <= '0;
                    recv_ctr <= '0;

                    comp_en <= 0;
                    done <= 0;

                    if(en)
                        state <= POOL_EXEC;
                end

                POOL_EXEC : begin
                    idx_x_reg <= idx_x;
                    idx_y_reg <= idx_y;

                    if(send_ctr < 144) begin
                        send_ctr <= send_ctr + 1;
                        comp_en <= 1;
                    end else begin
                        comp_en <= 0;
                    end

                    if(res_v)
                        recv_ctr <= recv_ctr + 1;

                    if(recv_ctr >= 144)
                        state <= POOL_DONE;

                    if(idx_x == 11) begin
                        idx_x <= 0;
                        idx_y <= (idx_y == 11) ? 0 : idx_y + 1;
                    end else begin
                        idx_x <= idx_x + 1;
                    end
                end

                POOL_DONE : begin
                    done <= 1;
                    state <= POOL_IDLE;
                end
            endcase
        end
    end
endmodule
