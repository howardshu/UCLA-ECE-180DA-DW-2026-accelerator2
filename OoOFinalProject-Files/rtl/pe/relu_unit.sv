module relu_unit #(
    parameter int unsigned ACC_W = 32
) (
    input  logic signed [ACC_W-1:0] x_i,
    output logic signed [ACC_W-1:0] y_o
);
    assign y_o = (x_i > 0) ? x_i : 0;
endmodule