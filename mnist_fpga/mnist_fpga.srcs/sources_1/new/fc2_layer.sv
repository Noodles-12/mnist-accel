`timescale 1ns / 1ps

module fc2_layer(
    input logic clk,
    input logic rst_n,
    input logic en,

    input logic [7:0] wr_data [0:15],
    input logic [7:0] wr_addr [0:15],
    input logic wr_v,

    input logic recv_v,

    output logic signed [15:0] res [0:9],
    output logic res_v,
    output logic done
);

    typedef enum logic [1:0] {
        FC2_IDLE,
        FC2_CALC,
        FC2_DISP,
        FC2_DONE
    } fc2_state;

    fc2_state state;

    // Might not need an addr_calc module
    logic [5:0] idx_addr;
    logic calc_en;

    logic signed [7:0] rd_weight [0:9];
    logic [7:0] rd_data;
    logic data_v;
    logic done_v;

    fc2_mem fc2m(
        .clk(clk),
        .rst_n(rst_n),

        .wr_data(wr_data),
        .wr_addr(wr_addr),
        .wr_v(wr_v),

        .rd_addr(idx_addr),
        .rd_v(calc_en),

        .rd_weights(rd_weight),
        .rd_data(rd_data),
        .rd_v(data_v)
    );

    fc2_dp fc2d(
        .clk(clk),
        .rst_n(rst_n),
        .data_v(data_v),
        .done_v(done_v),

        .data(rd_data),
        .weights(rd_weight),

        .res(res),
        .res_v(res_v)
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= FC2_IDLE;
            idx_addr <= '0;
            calc_en <= '0;
            done_v <= '0;
        end else begin
            unique case(state)
                FC2_IDLE: begin
                    idx_addr <= '0;
                    calc_en <= '0;
                    done_v <= '0;

                    if(en) begin
                        state <= FC2_CALC;
                        calc_en <= '1;
                    end
                end

                FC2_CALC: begin
                    if(idx_addr == 6'd63) begin
                        state <= FC2_DONE;
                        calc_en <= '0;
                    end else begin
                        idx_addr <= idx_addr + 1;
                    end
                end

                FC2_DISP: begin
                    idx_addr <= '0;
                    calc_en <= '0;
                    done_v <= '1;
                    
                    if(resc_v) begin
                        state <= FC2_DONE;
                    end
                end

                FC2_DONE: begin
                    idx_addr <= '0;
                    calc_en <= '0;
                    done_v <= '0;
                    state <= FC2_IDLE;
                end
            endcase
        end
    end
endmodule
