`timescale 1ns / 1ps

module accel_top(
    input logic clk,
    input logic rst_n
);

    typedef enum {
        TOP_IDLE,
        TOP_IMAGE,
        TOP_CONV,
        TOP_POOL,
        TOP_DONE
    } top_state;

    top_state state;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= TOP_IDLE;
        end else begin

        end
    end
endmodule
