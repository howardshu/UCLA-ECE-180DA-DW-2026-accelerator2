module mac_unit #(
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W  = 32
) (
    input  logic signed [DATA_W-1:0] act_i,    // activation
    input  logic signed [DATA_W-1:0] wgt_i,    // weight
    input  logic signed [ACC_W-1:0] acc_i,
    output logic signed [ACC_W-1:0] result_o
);
    assign result_o = act_i * wgt_i + acc_i;
endmodule