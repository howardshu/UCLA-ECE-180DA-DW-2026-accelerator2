// Fully connected layer + argmax.  *** STUB: TODO ***
//
//   logit[o] = bias[o] + sum_{i<48} p2[i] * wgt[0x180 + o*48 + i]   (int32)
//   RES[o]   = logit[o]                 for o = 0..9
//   RES[10]  = index of the largest logit (first maximum wins -- the tie
//              rule is unconfirmed; ask on Campuswire)
//
// p2 is in ACT_B[0..47] (uint8, flattened HWC, which is exactly the fc input
// order). No shift and no ReLU on the logits. Do NOT write RES[11]; the
// controller writes MAGIC after done_o.
//
// FC is only 480 MACs, so WGT bandwidth (one byte per cycle) dominates:
// one MAC per cycle is about 480 cycles. Keep a running max while writing
// logits so argmax costs no extra pass. Reads have one cycle of latency.
//
// Handshake: start_i is a one-cycle pulse; pulse done_o for one cycle after
// RES[10] is written.

module acc_fc
    import accelerator_cnn_pkg::*;
    import acc_internal_pkg::*;
(
    input  logic                   clk_i,
    input  logic                   rst_ni,

    input  logic                   start_i,
    output logic                   done_o,

    input  acc_t                   cfg_bias_i [FC_O],

    // Flattened p2 (ACT_B)
    output logic [BYTE_ADDR_W-1:0] src_addr_o,
    input  act_t                   src_rdata_i,

    // Weights (WGT)
    output logic [WGT_ADDR_W-1:0]  wgt_addr_o,
    input  wgt_t                   wgt_rdata_i,

    // Results (RES words 0..10)
    output logic                   res_we_o,
    output logic [RES_ADDR_W-1:0]  res_addr_o,
    output logic [31:0]            res_wdata_o
);

    // TODO: replace this stub. It finishes immediately and writes nothing.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) done_o <= 1'b0;
        else         done_o <= start_i;
    end

    assign src_addr_o  = '0;
    assign wgt_addr_o  = '0;
    assign res_we_o    = 1'b0;
    assign res_addr_o  = '0;
    assign res_wdata_o = '0;

    // verilator lint_off UNUSEDSIGNAL
    logic unused;
    assign unused = ^{cfg_bias_i[0], src_rdata_i, wgt_rdata_i};
    // verilator lint_on UNUSEDSIGNAL

endmodule
