`timescale 1ns / 1ps

module conv_layer(
    input logic clk,
    input logic rst_n,
    input logic en,

    // Image load port -> conv_mem's img_mem (UART/top-level fills this in
    // before en is pulsed)
    input logic img_wr_en,
    input logic [9:0] img_wr_addr,
    input logic [7:0] img_wr_data,

    // Outputs to be determined later
    output logic calc_v,
    output logic [31:0] final_res,
    output logic [9:0] res_addr,
    output logic [3:0] filter_addr,
    output logic done
);

    typedef enum logic [1:0] {
        CONV_IDLE,      // Doing nothing; essentially reset as well
        CONV_LOAD,      // Load weights of {filter_idx} from mem into MAC array
        CONV_FILTER,    // Parses whole image w/ 5x5 area into MAC array for whichever filter
        CONV_DONE
    } conv_state;

    conv_state state;

    // CONV_LOAD logics
    localparam NUM_FILTERS = 16;

    logic wt_load_sent;                 // pulse for this filter already issued
    logic wt_load_en;                   // FSM -> cm  : request weights for filter_idx_ip
    logic [4:0] filter_idx;             // next filter to load; == NUM_FILTERS once all are swept
    logic [3:0] filter_idx_ip;          // filter currently in flight

    logic signed [7:0] lane_weights [0:24];
    logic lane_weights_v;               // cm  -> cdp : lane_weights valid
    logic wt_load_done;                 // cdp -> FSM : MAC array latched the weights

    // CONV_FILTER logics
    localparam IDX_MIN = 2;  // First valid 5x5 center (28x28 image)
    localparam IDX_MAX = 25; // Last valid 5x5 center

    logic [5:0] idx_x, idx_x_reg; // Image indexes for center of 5x5 convolutional area
    logic [5:0] idx_y, idx_y_reg;

    logic [9:0] img_addrs [0:24];
    logic [7:0] area_pixel [0:24];

    logic [9:0] send_ctr, recv_ctr;

    logic sweep_en;                     // FSM -> cac : run the window sweep
    logic img_addrs_v;                  // cac -> cm  : img_addrs valid
    logic area_pixel_v;                 // cm  -> cdp : area_pixel valid

    logic [9:0] out_addr;               // cac -> cm  : output-map dest for this window
    logic [9:0] out_addr_d1;            // cm  -> cdp : out_addr realigned to area_pixel

    conv_addr_calc cac(
        .clk(clk),
        .rst_n(rst_n),
        .sweep_en(sweep_en),

        .idx_x(idx_x),
        .idx_y(idx_y),

        .img_rd_addr(img_addrs),
        .img_addrs_v(img_addrs_v),
        .out_addr(out_addr)
    );

    conv_mem cm(
        .clk(clk),
        .rst_n(rst_n),
        .filter_idx(filter_idx_ip),
        .filter_idx_v(wt_load_en),

        .img_wr_en(img_wr_en),
        .img_wr_addr(img_wr_addr),
        .img_wr_data(img_wr_data),

        .img_rd_addr(img_addrs),
        .img_addrs_v(img_addrs_v),
        .out_addr(out_addr),

        .area_pixel(area_pixel),
        .area_pixel_v(area_pixel_v),
        .out_addr_d1(out_addr_d1),
        .lane_weights(lane_weights),
        .lane_weights_v(lane_weights_v)
    );

    conv_dp cdp(
        .clk(clk),
        .rst_n(rst_n),

        .area_pixel(area_pixel),
        .area_pixel_v(area_pixel_v),

        .lane_weights_v(lane_weights_v),
        .lane_weights(lane_weights),
        .filter_idx(filter_idx_ip), // Might need to give its own valid check b/c of timing

        .out_addr(out_addr_d1),

        .wt_load_done(wt_load_done),
        .calc_v(calc_v),
        .final_res(final_res),
        .res_addr(res_addr),
        .filter_addr(filter_addr)
    );

    assign sweep_en = (state == CONV_FILTER) && (send_ctr < 576);

    always_ff @ (posedge clk) begin
        if(!rst_n) begin
            state <= CONV_IDLE;

            idx_x <= IDX_MIN;
            idx_y <= IDX_MIN;
            idx_x_reg <= IDX_MIN;
            idx_y_reg <= IDX_MIN;

            filter_idx <= 0;
            filter_idx_ip <= 0;
            wt_load_sent <= 0;
            wt_load_en <= 0;
            done <= 0;

            send_ctr <= 0;
            recv_ctr <= 0;
        end else begin
            unique case(state)
                CONV_IDLE : begin
                    idx_x <= IDX_MIN;
                    idx_y <= IDX_MIN;
                    idx_x_reg <= IDX_MIN;
                    idx_y_reg <= IDX_MIN;

                    filter_idx <= 0;
                    wt_load_sent <= 0;
                    wt_load_en <= 0;
                    done <= 0;

                    send_ctr <= 0;
                    recv_ctr <= 0;

                    if(en) begin
                        state <= CONV_LOAD;
                        wt_load_sent <= 0;
                    end
                end

                CONV_LOAD : begin
                    send_ctr <= 0;
                    recv_ctr <= 0;

                    idx_x <= IDX_MIN;
                    idx_y <= IDX_MIN;
                    idx_x_reg <= IDX_MIN;
                    idx_y_reg <= IDX_MIN;

                    if(!wt_load_sent) begin
                        if(filter_idx == NUM_FILTERS) begin
                            wt_load_en <= 0;
                            state <= CONV_DONE;
                        end else begin
                            wt_load_en <= 1;
                            filter_idx_ip <= filter_idx[3:0];
                            filter_idx <= filter_idx + 1;
                            wt_load_sent <= 1;
                        end
                    end else begin
                        wt_load_en <= 0;
                        if(wt_load_done) begin
                            state <= CONV_FILTER;
                        end
                    end
                end

                /*   
                    ! Make cdp have an output for every valid entry it's put into conv_layer output
                    ! Make the condition to go back to load be a counter that uses this new cdb output to increment
                    ! W/o this, we'll accidentally put in the last few pixel areas through the next set of weights

                    ? Maybe put in a send_ctr and a recv_ctr
                    * send_ctr would count up to 24*24 then sweep_en <= 0
                    * recv_ctr would also count up to 24*24 to signal when we're good to switch to the loading state
                */
                CONV_FILTER : begin
                    wt_load_sent <= 0;
                    wt_load_en <= 0;

                    idx_x_reg <= idx_x;
                    idx_y_reg <= idx_y;

                    if(send_ctr < 576) begin
                        send_ctr <= send_ctr + 1;
                    end

                    if(calc_v) begin
                        recv_ctr <= recv_ctr + 1;
                    end

                    if(recv_ctr >= 576) begin
                        state <= CONV_LOAD;
                    end

                    // Incrementing & looping indexes
                    if(idx_x == IDX_MAX) begin
                        idx_x <= IDX_MIN;
                        idx_y <= (idx_y == IDX_MAX) ? IDX_MIN : idx_y + 1;
                    end else begin
                        idx_x <= idx_x + 1;
                    end
                end

                CONV_DONE : begin
                    wt_load_en <= 0;
                    done <= 1;
                    state <= CONV_IDLE;
                end
            endcase
        end
    end
endmodule
