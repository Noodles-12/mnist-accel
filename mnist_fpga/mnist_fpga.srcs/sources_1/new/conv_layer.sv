`timescale 1ns / 1ps

module conv_layer(
    input logic clk,
    input logic rst_n,
    input logic en

    // Outputs to be determined later
);

    typedef enum logic [1:0] {
        CONV_IDLE,      // Doing nothing; essentially reset as well
        CONV_LOAD,      // Load weights of {filter_idx} from mem into MAC array
        CONV_FILTER     // Parses whole image w/ 5x5 area into MAC array for whichever filter
    } conv_state;

    conv_state state;

    // CONV_LOAD logics
    logic filter_alr_load, filter_load_en;
    logic [3:0] filter_idx, filter_idx_ip;

    logic signed [7:0] lane_weights [0:24];
    logic valid_weights, weights_loaded;

    // CONV_FILTER logics
    localparam IDX_MIN = 2;  // First valid 5x5 center (28x28 image)
    localparam IDX_MAX = 25; // Last valid 5x5 center

    logic [7:0] idx_x, idx_x_reg; // Image indexes for center of 5x5 convolutional area
    logic [7:0] idx_y, idx_y_reg;

    logic [9:0] img_addrs [0:24];

    conv_addr_calc cac(
        .clk(clk),
        .rst_n(rst_n),
        .rd_en(),
        .idx_x(idx_x),
        .idx_y(idx_y),

        .img_rd_addr(img_addrs),
        .op_v()
    );

    conv_mem cm(
        .clk(clk),
        .rst_n(rst_n),
        .filter_idx(filter_idx_ip),
        .filter_idx_v(filter_load_en),

        .img_wr_en(),
        .img_wr_addr(),
        .img_wr_data(),
        .img_rd_addr(),

        .area_pixel(a),
        .lane_weights(lane_weights),
        .valid_weights(valid_weights)
    );

    conv_dp cdp(
        .clk(clk),
        .rst_n(rst_n),
        .lane_weights(lane_weights),
        .valid_weights(valid_weights),

        .weights_loaded(weights_loaded)
    );

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            idx_x <= IDX_MIN;
            idx_y <= IDX_MIN;
            idx_x_reg <= IDX_MIN;
            idx_y_reg <= IDX_MIN;

            filter_idx <= 0;
            filter_idx_ip <= 0;
            filter_alr_load <= 0;
            filter_load_en <= 0;

            state <= CONV_IDLE;
        end else begin
            unique case(state)
                CONV_IDLE : begin
                    idx_x <= IDX_MIN;
                    idx_y <= IDX_MIN;
                    idx_x_reg <= IDX_MIN;
                    idx_y_reg <= IDX_MIN;

                    filter_idx <= 0;
                    filter_alr_load <= 0;
                    filter_load_en <= 0;

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

                    if(weights_loaded) begin
                        state <= CONV_FILTER;
                    end
                end

                CONV_FILTER : begin
                    filter_alr_load <= 0;
                    filter_load_en <= 0;

                    idx_x_reg <= idx_x;
                    idx_y_reg <= idx_y;

                    if(idx_x == IDX_MAX) begin
                        idx_x <= IDX_MIN;
                        idx_y <= (idx_y == IDX_MAX) ? IDX_MIN : idx_y + 1;

                        // Whole image swept for this filter; go load the next filter
                        if(idx_y == IDX_MAX) begin
                            state <= CONV_LOAD;
                        end
                    end else begin
                        idx_x <= idx_x + 1;
                    end
                end
            endcase
        end
    end
endmodule
