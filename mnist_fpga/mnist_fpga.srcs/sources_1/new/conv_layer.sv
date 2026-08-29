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
    logic [3:0] filter_idx, filter_idx_ip;
    logic filter_idx_v, filter_alr_load, filter_load_en;
    conv_state state;

    conv_addr_calc cac(
        .clk(clk),
        .rst_n(rst_n),
        .idx_x(idx_x),
        .idx_y(idx_y),
        .img_rd_addr()
    );

    conv_mem cm(
        .clk(clk),
        .rst_n(rst_n),
        .filter_idx(filter_idx_ip),
        .filter_idx_v(filter_idx_v),

        .lane_weights()
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            idx_x <= 2;
            idx_y <= 2;
            filter_idx <= 0;
            filter_idx_v <= 0;
            filter_alr_load <= 0;
            state <= CONV_IDLE;
        end else begin
            unique case(state)
                CONV_IDLE : begin
                    idx_x <= 2;
                    idx_y <= 2;
                    filter_idx <= 0;
                    filter_idx_v <= 0;
                    filter_alr_load <= 0;

                    if(en) begin
                        state <= CONV_LOAD;
                        filter_alr_load <= 0;
                    end
                end

                CONV_LOAD : begin
                    if(!filter_alr_load) begin
                        filter_load_en <= 1;
                        filter_idx_ip <= filter_idx;
                        filter_idx <= filter_idx + 1;
                        filter_alr_load <= 1;
                    end else begin
                        filter_load_en <= 0;
                    end
                end

                CONV_FILTER : begin

                end
            endcase
        end
    end
endmodule
