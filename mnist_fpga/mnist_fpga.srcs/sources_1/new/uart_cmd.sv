`timescale 1ns / 1ps

module uart_cmd(
    input logic clk,
    input logic rst_n,

    input logic [7:0] rx_data,
    input logic rx_v,

    output logic img_wr_en,
    output logic [9:0] img_wr_addr,
    output logic [7:0] img_wr_data,
    output logic start
);

    localparam logic [1:0] OP_NOP   = 2'b00;
    localparam logic [1:0] OP_IMG   = 2'b01;
    localparam logic [1:0] OP_START = 2'b10;

    typedef enum logic [1:0] {
        CMD_HDR,
        CMD_ADDR_LO,
        CMD_DATA
    } cmd_state;

    cmd_state state;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= CMD_HDR;
            img_wr_en <= 1'b0;
            img_wr_addr <= '0;
            img_wr_data <= '0;
            start <= 1'b0;
        end else begin
            img_wr_en <= 1'b0;
            start <= 1'b0;

            if(rx_v) begin
                unique case(state)
                    CMD_HDR: begin
                        unique case(rx_data[7:6])
                            OP_IMG: begin
                                img_wr_addr[9:8] <= rx_data[1:0];
                                state <= CMD_ADDR_LO;
                            end
                            OP_START: begin
                                start <= 1'b1;
                            end
                            default: ;
                        endcase
                    end

                    CMD_ADDR_LO: begin
                        img_wr_addr[7:0] <= rx_data;
                        state <= CMD_DATA;
                    end

                    CMD_DATA: begin
                        img_wr_data <= rx_data;
                        img_wr_en <= 1'b1;
                        state <= CMD_HDR;
                    end
                endcase
            end
        end
    end
endmodule
