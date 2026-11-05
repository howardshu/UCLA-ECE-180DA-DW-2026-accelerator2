// Internal memory: one read/write port for the datapath, one read-only port
// for debug. Both reads are synchronous (data valid the cycle after the
// address), so this infers a block RAM. Contents are not reset.

module acc_ram #(
    parameter int unsigned WIDTH = 8,
    parameter int unsigned DEPTH = 2048,
    localparam int unsigned AW   = $clog2(DEPTH)
) (
    input  logic             clk_i,

    // Datapath port - read every cycle, write when we is high
    input  logic             a_we_i,
    input  logic [AW-1:0]    a_addr_i,
    input  logic [WIDTH-1:0] a_wdata_i,
    output logic [WIDTH-1:0] a_rdata_o,

    // Debug read port
    input  logic [AW-1:0]    b_addr_i,
    output logic [WIDTH-1:0] b_rdata_o
);

    logic [WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk_i) begin
        if (a_we_i) begin
            mem[a_addr_i] <= a_wdata_i;
        end
        a_rdata_o <= mem[a_addr_i];
        b_rdata_o <= mem[b_addr_i];
    end

endmodule
