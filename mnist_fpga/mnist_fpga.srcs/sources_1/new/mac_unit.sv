module mac_unit (
    input  logic               clk,
    input  logic               rst_n,
    input  logic signed [7:0]  weight,
    input  logic signed [7:0]  activation,
    
    output logic signed [15:0] op
);

    logic signed [7:0]  weight_reg;
    logic signed [7:0]  activation_reg;

    // 2. Product Register (For internal DSP multiplier pipeline)
    // Attribute explicitly forces Vivado to use a DSP slice
    (* use_dsp = "yes" *) logic signed [15:0] prod_reg;

    // Synchronous pipelining (DSP slices do not support async resets internally)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            weight_reg     <= '0;
            activation_reg <= '0;
            prod_reg       <= '0;
        end else begin
            weight_reg     <= weight;
            activation_reg <= activation;
            prod_reg       <= weight_reg * activation_reg;
        end
    end

    // Output assignment (adds a total of 2 clock cycles of latency)
    assign op = prod_reg;

endmodule