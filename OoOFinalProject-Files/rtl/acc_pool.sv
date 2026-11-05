// One max-pool lane, fused with conv: a pooling register and a comparator.
// acc_conv has one lane per output channel (3 in total).
//
// The four conv outputs of a 2x2 window arrive one after another on d_i (the
// PE's requantized, ReLU'd result). write_i folds d_i into the register;
// max_o = max(value_o, d_i) goes to the output activations buffer when d_i is
// the window's fourth value. clear_i starts a new window and wins over
// write_i, so the conv engine pulses clear_i together with the fourth write.
// Activations are unsigned, so clearing to 0 is the same as loading the first
// value of the window.
module acc_pool
    import accelerator_cnn_pkg::*;
(
    input  logic clk_i,
    input  logic rst_ni,
    input  logic clear_i,
    input  logic write_i,
    input  act_t d_i,       // relu_o of this channel's PE
    output act_t value_o,   // pooling register
    output act_t max_o      // comparator output
);

    assign max_o = (d_i > value_o) ? d_i : value_o;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)      value_o <= '0;
        else if (clear_i) value_o <= '0;
        else if (write_i) value_o <= max_o;
    end

endmodule
