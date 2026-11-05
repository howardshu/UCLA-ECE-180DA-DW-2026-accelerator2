module accumulator #(
    parameter int unsigned ACC_W = 32
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic                    clear_i,  // force the total to 0
    input  logic                    en_i,     // load d_i this cycle
    input  logic signed [ACC_W-1:0] d_i,
    output logic signed [ACC_W-1:0] q_o
);
    always_ff @(posedge clk_i) begin
        if (!rst_ni || clear_i) begin
            q_o <= 0;
        end
        else if (en_i) begin
            q_o <= d_i;
        end
    end
endmodule