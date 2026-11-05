// Running signed sum. Reset/clear discard pending input; disabled cycles hold.
module accumulator #(
    parameter int unsigned ACC_W = 32
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic                    clear_i,
    input  logic                    en_i,
    input  logic signed [ACC_W-1:0] d_i,
    output logic signed [ACC_W-1:0] q_o
);
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)       q_o <= '0;
        else if (clear_i)  q_o <= '0;
        else if (en_i)     q_o <= d_i;
    end
endmodule
