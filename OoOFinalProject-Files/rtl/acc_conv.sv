// Convolution engine, shared by conv1 and conv2.  *** STUB: TODO ***
//
// Computes, for every output (h, w) and output channel o (K = 5, OC = 3):
//
//   acc       = bias[o] + sum_{r,s,c} x[((h+r)*IN_HW + (w+s))*IN_C + c]
//                                    * wgt[wgt_base + ((o*5 + r)*5 + s)*IN_C + c]
//   y[(h*OUT_HW + w)*3 + o] = requant(acc, shift)     (acc_internal_pkg)
//
//   conv1: IN_HW = 28, IN_C = 1, src = IMG at img_base, wgt_base = 0x000
//   conv2: IN_HW = 12, IN_C = 3, src = ACT_B at 0,      wgt_base = 0x080
//   OUT_HW = IN_HW - 4; the destination is always ACT_A.
//
// Activations are uint8 (act_t), weights int8 (wgt_t): sign-extend the
// weight and zero-extend the activation before multiplying.
//
// Proposed microarchitecture (see docs/cdr-plan.md):
//   1. Preload the layer's 25*IN_C*3 weights from WGT into a local register
//      file (75 or 225 bytes), one byte per cycle. WGT has one read port,
//      but each PE needs a different weight every cycle.
//   2. NUM_PE = 3 PEs, one per output channel. Each cycle, read one input
//      byte and broadcast it to all three PEs; PE o multiplies it by its own
//      weight for the same (r, s, c) and accumulates.
//   3. After 25*IN_C products, requantize the 3 accumulators and write the 3
//      output bytes (3 cycles on the single ACT_A write port, or overlap the
//      writes with the next pixel's accumulation).
//
// Port timing: every read port has one cycle of latency. The address you
// drive in cycle t returns data in cycle t+1 -- pipeline a valid bit and the
// (r, s, c) indices alongside the address so the MAC uses matching operands.
//
// Handshake: start_i is a one-cycle pulse; configuration is stable from start
// until done. Pulse done_o for one cycle after the last output byte is
// written. Reset may arrive mid-layer.

module acc_conv
    import accelerator_cnn_pkg::*;
    import acc_internal_pkg::*;
(
    input  logic                   clk_i,
    input  logic                   rst_ni,

    input  logic                   start_i,
    output logic                   done_o,

    // Layer configuration
    input  logic [4:0]             cfg_in_hw_i,      // 28 or 12
    input  logic [1:0]             cfg_in_c_i,       // 1 or 3
    input  logic [BYTE_ADDR_W-1:0] cfg_src_base_i,   // image offset for conv1
    input  logic [WGT_ADDR_W-1:0]  cfg_wgt_base_i,
    input  logic [4:0]             cfg_shift_i,
    input  acc_t                   cfg_bias_i [NUM_PE],

    // Input activations (IMG or ACT_B)
    output logic [BYTE_ADDR_W-1:0] src_addr_o,
    input  act_t                   src_rdata_i,

    // Weights (WGT)
    output logic [WGT_ADDR_W-1:0]  wgt_addr_o,
    input  wgt_t                   wgt_rdata_i,

    // Output activations (ACT_A)
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
    assign wgt_addr_o  = '0;
    assign dst_we_o    = 1'b0;
    assign dst_addr_o  = '0;
    assign dst_wdata_o = '0;

    // verilator lint_off UNUSEDSIGNAL
    logic unused;
    assign unused = ^{cfg_in_hw_i, cfg_in_c_i, cfg_src_base_i, cfg_wgt_base_i,
                      cfg_shift_i, cfg_bias_i[0], cfg_bias_i[1], cfg_bias_i[2],
                      src_rdata_i, wgt_rdata_i};
    // verilator lint_on UNUSEDSIGNAL

endmodule
