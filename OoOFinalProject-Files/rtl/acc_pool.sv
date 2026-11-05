// 2x2 stride-2 max-pool engine, shared by pool1 and pool2.  *** STUB: TODO ***
//
//   y[(h*OUT_HW + w)*3 + c] = max over a,b in {0,1} of
//                             x[((2h+a)*IN_HW + (2w+b))*3 + c]
//
//   pool1: IN_HW = 24 (ACT_A -> ACT_B, 432 outputs)
//   pool2: IN_HW =  8 (ACT_A -> ACT_B,  48 outputs)
//   OUT_HW = IN_HW / 2. Values are uint8, so max is an unsigned compare.
//
// Simplest schedule: 4 reads then 1 write per output (one read port on
// ACT_A, one write port on ACT_B, which can overlap). The reads have one
// cycle of latency: data for the address driven in cycle t arrives in t+1.
//
// Handshake: start_i is a one-cycle pulse; pulse done_o for one cycle after
// the last output byte is written.

module acc_pool
    import accelerator_cnn_pkg::*;
    import acc_internal_pkg::*;
(
    input  logic                   clk_i,
    input  logic                   rst_ni,

    input  logic                   start_i,
    output logic                   done_o,

    input  logic [4:0]             cfg_in_hw_i,      // 24 or 8

    // Input activations (ACT_A)
    output logic [BYTE_ADDR_W-1:0] src_addr_o,
    input  act_t                   src_rdata_i,

    // Output activations (ACT_B)
    output logic                   dst_we_o,
    output logic [BYTE_ADDR_W-1:0] dst_addr_o,
    output act_t                   dst_wdata_o
);

    // TODO: replace this stub. It finishes immediately and writes nothing.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) done_o <= 1'b0;
        else         done_o <= start_i;
    end

    assign src_addr_o  = '0;
    assign dst_we_o    = 1'b0;
    assign dst_addr_o  = '0;
    assign dst_wdata_o = '0;

    // verilator lint_off UNUSEDSIGNAL
    logic unused;
    assign unused = ^{cfg_in_hw_i, src_rdata_i};
    // verilator lint_on UNUSEDSIGNAL

endmodule
