// Combinational MAC. Zero-extend the unsigned activation BEFORE converting to
// signed; otherwise pixels 128..255 would be interpreted as negative int8.
module mac_unit #(
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W  = 32
) (
    input  logic [DATA_W-1:0]        act_i,
    input  logic signed [DATA_W-1:0] wgt_i,
    input  logic signed [ACC_W-1:0]  acc_i,
    output logic signed [ACC_W-1:0]  result_o
);
    logic signed [2*DATA_W:0] product;
    assign product = $signed({1'b0, act_i}) * wgt_i;
    // ACC_W must be at least 2*DATA_W+1. Addition wraps at ACC_W bits.
    assign result_o = acc_i + {{(ACC_W-2*DATA_W-1){product[2*DATA_W]}}, product};
endmodule
