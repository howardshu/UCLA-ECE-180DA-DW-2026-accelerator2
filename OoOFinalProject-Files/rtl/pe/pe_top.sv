// One output-channel PE: unsigned activation * signed weight + signed bias.
// One MAC is accepted on each rising edge with valid_i=1. first_mac_i selects
// bias_i instead of the previous sum, including the first product on that edge.
// Priority: active-low asynchronous reset, synchronous clear, valid, hold.
// clear_i discards a simultaneous MAC. first_mac_i has no effect while stalled.
module pe_top #(
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W  = 32
) (
    input  logic                     clk_i,
    input  logic                     rst_ni,
    input  logic                     clear_i,
    input  logic                     valid_i,
    input  logic                     first_mac_i,
    input  logic [DATA_W-1:0]        act_i,
    input  logic signed [DATA_W-1:0] wgt_i,
    input  logic signed [ACC_W-1:0]  bias_i,
    input  logic [$clog2(ACC_W)-1:0] shift_i,
    output logic signed [ACC_W-1:0]  sum_o,
    output logic [DATA_W-1:0]        requant_o
);
    logic signed [ACC_W-1:0] acc_q, acc_d, mac_base, shifted;
    localparam logic signed [ACC_W-1:0] MAX_ACT =
        {{(ACC_W-DATA_W){1'b0}}, {DATA_W{1'b1}}};

    // bias is selected once per dot product, not added on every MAC
    assign mac_base = first_mac_i ? bias_i : acc_q;
    mac_unit #(.DATA_W(DATA_W), .ACC_W(ACC_W)) u_mac (
        .act_i(act_i), .wgt_i(wgt_i), .acc_i(mac_base), .result_o(acc_d)
    );
    accumulator #(.ACC_W(ACC_W)) u_accumulator (
        .clk_i(clk_i), .rst_ni(rst_ni), .clear_i(clear_i),
        .en_i(valid_i), .d_i(acc_d), .q_o(acc_q)
    );
    assign sum_o = acc_q;

    // conv output: arithmetic shift with no rounding, then ReLU and unsigned saturation
    // FC uses sum_o directly (no ReLU, shift, or saturation).
    assign shifted = acc_q >>> shift_i;
    assign requant_o = shifted < 0 ? '0 :
                       shifted > MAX_ACT ? {DATA_W{1'b1}} : shifted[DATA_W-1:0];
endmodule
