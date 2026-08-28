`timescale 1ns / 1ps

module conv_layer(
    input logic clk,
    input logic rst_n,
    input logic en
);

    typedef enum logic [1:0] {
        CONV_IDLE,      // Doing nothing; essentially reset as well
        CONV_LOAD,      // Load weights of {filter_idx} from mem into MAC array
        CONV_FILTER     // Parses whole image w/ 5x5 area into MAC array for whichever filter
    } conv_state;

    // Image indexes for center of 5x5 convolutional area
    logic [7:0] idx_x, idx_y;
    logic [3:0] filter_idx;
    conv_state state;

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            idx_x <= 2;
            idx_y <= 2;
            filter_idx <= 0;
            conv_state <= CONV_IDLE;
        end else begin
            unique case(state)
                CONV_IDLE : begin
                    idx_x <= 2;
                    idx_y <= 2;
                    filter_idx <= 0;
                end
            endcase
        end
    end
endmodule
