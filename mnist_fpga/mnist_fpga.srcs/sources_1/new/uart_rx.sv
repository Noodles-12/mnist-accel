`timescale 1ns / 1ps

module uart_rx#(
    parameter int CLKS_PER_BIT = 868
)(
    input logic clk,
    input logic rst_n,

    input logic rx,

    output logic [7:0] rx_data,
    output logic rx_v
);

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state;

    rx_state state;

    logic rx_meta, rx_sync;
    logic [$clog2(CLKS_PER_BIT)-1:0] clk_cnt;
    logic [2:0] bit_idx;
    logic [7:0] shreg;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= RX_IDLE;
            clk_cnt <= '0;
            bit_idx <= '0;
            shreg <= '0;
            rx_data <= '0;
            rx_v <= 1'b0;
        end else begin
            rx_v <= 1'b0;

            unique case(state)
                RX_IDLE: begin
                    clk_cnt <= '0;
                    bit_idx <= '0;
                    if(!rx_sync)
                        state <= RX_START;
                end

                RX_START: begin
                    if(clk_cnt == (CLKS_PER_BIT-1)/2) begin
                        clk_cnt <= '0;
                        state <= rx_sync ? RX_IDLE : RX_DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                RX_DATA: begin
                    if(clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        shreg <= {rx_sync, shreg[7:1]};
                        if(bit_idx == 3'd7)
                            state <= RX_STOP;
                        else
                            bit_idx <= bit_idx + 1;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                RX_STOP: begin
                    if(clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= '0;
                        rx_data <= shreg;
                        rx_v <= 1'b1;
                        state <= RX_IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end
            endcase
        end
    end
endmodule
