// ============================================================================
// pe_top.sv -- Processing Element for a CNN accelerator
//
// THIS IS THE ONLY FILE YOU ARE GIVEN. You will write the three submodules
// it needs, then wire them up down at the bottom.
//
// ---------------------------------------------------------------------------
// WHAT THIS THING IS FOR
//
// A convolution layer computes, for every output pixel:
//
//     out = ReLU( sum over i of  activation[i] * weight[i] )
//
// For a 3x3 filter that is 9 multiplies and 8 adds. For a real layer it is
// millions of them. But notice the shape of the work: it is the SAME tiny
// operation -- multiply, then add to a running total -- repeated forever.
//
// So an accelerator does not build a huge adder tree. It builds one small
// multiply-accumulate unit, called a PROCESSING ELEMENT (PE), and streams
// data through it one pair per cycle:
//
//     cycle 0:  acc = 0 + a0*w0
//     cycle 1:  acc = acc + a1*w1
//     cycle 2:  acc = acc + a2*w2
//     cycle 3:  acc = acc + a3*w3     <- after this, acc is the dot product
//     then:     out = ReLU(acc)
//
// That is all a PE is. A real accelerator tiles hundreds of these into a
// grid (a "systolic array") and streams activations across and weights down.
// You are building one cell of that grid.
//
// ---------------------------------------------------------------------------
// THE BLOCK DIAGRAM -- draw this before you write any code
//
//                    +-------------------------------------+
//    act_i  ---------|                                     |
//    wgt_i  ---------|            mac_unit                 |
//              +-----| (combinational: acc_i + act*wgt)    |
//              |     +-------------------+-----------------+
//              |                         | mac_result
//              |                         v
//              |     +-------------------------------------+
//              |     |           accumulator               |
//              |     | (REGISTER: holds the running total) |
//              |     +-------------------+-----------------+
//              |                         | acc_q
//              +-------------------------+          <-- feedback loop!
//                                        |
//                                        +---------> sum_o
//                                        |
//                    +-------------------v-----------------+
//                    |            relu_unit                |
//                    |     (combinational: max(x, 0))      |
//                    +-------------------+-----------------+
//                                        |
//                                        +---------> relu_o
//
// One cloud (mac_unit), one box (accumulator), one cloud (relu_unit), and a
// feedback path from the register's output back to the MAC's input.
//
// That feedback loop is the lab's "combinational read, sequential write"
// pattern: we read the current total straight out of the register with no
// extra flop, add to it, and write the result back on the next clock edge.
//
// ---------------------------------------------------------------------------
// NUMBER FORMATS -- read this, it is where most of the bugs will come from
//
// CNN activations and weights are SIGNED. A weight of -3 is completely
// normal, and ReLU would be pointless if nothing were ever negative. So
// every data signal here is `logic signed`.
//
// If you drop the `signed` keyword anywhere in the chain, the arithmetic
// silently becomes unsigned: -1 stops being -1 and becomes 255, your
// products come out enormous, and ReLU never fires because nothing is ever
// negative. Nothing warns you. If your testbench shows wildly too-large
// positive numbers, this is the first thing to check.
//
// Widths:
//     act_i, wgt_i   DATA_W = 8 bits signed   (range -128 .. +127)
//     product        16 bits signed           (8x8 needs 16)
//     accumulator    ACC_W = 32 bits signed   (room for many adds)
//
// The accumulator is deliberately much wider than the product. Adding 1000
// products of up to ~16K each needs headroom; this is why accelerators carry
// a wide accumulator and only narrow back down at the very end.
// ============================================================================
module pe_top #(
    parameter int unsigned DATA_W = 8,
    parameter int unsigned ACC_W  = 32
) (
    input  logic                     clk_i,
    input  logic                     rst_ni,   // active-low reset

    input  logic                     clear_i,  // start a new output pixel:
                                               // zero the accumulator
    input  logic                     valid_i,  // this cycle carries a real
                                               // (activation, weight) pair
    input  logic signed [DATA_W-1:0] act_i,    // activation
    input  logic signed [DATA_W-1:0] wgt_i,    // weight

    output logic signed [ACC_W-1:0]  sum_o,    // running total, pre-ReLU
    output logic signed [ACC_W-1:0]  relu_o    // after ReLU
);

  // ==========================================================================
  // STEP 1 -- Write these three modules, each in its own file in rtl/.
  //           Build them in this order. Each is genuinely small: the body of
  //           each one is between one and five lines.
  // ==========================================================================

  // --------------------------------------------------------------------------
  // MODULE 1 of 3:  rtl/mac_unit.sv
  //
  //   The multiply-accumulate. Purely COMBINATIONAL -- no clock, no reset.
  //   It does one thing:   result_o = acc_i + (act_i * wgt_i)
  //
  //   module mac_unit #(
  //       parameter int unsigned DATA_W = 8,
  //       parameter int unsigned ACC_W  = 32
  //   ) (
  //       input  logic signed [DATA_W-1:0] act_i,
  //       input  logic signed [DATA_W-1:0] wgt_i,
  //       input  logic signed [ACC_W-1:0]  acc_i,     // total so far
  //       output logic signed [ACC_W-1:0]  result_o   // total + new product
  //   );
  //
  //   Hints:
  //     - One `assign` is enough.
  //     - Declare an intermediate `logic signed [2*DATA_W-1:0] product;` if it
  //       helps you read it. Both styles are fine.
  //     - No `always_ff` in this file. If you typed `posedge`, stop and
  //       re-read the block diagram: this is a cloud, not a box.
  // --------------------------------------------------------------------------

  // --------------------------------------------------------------------------
  // MODULE 2 of 3:  rtl/accumulator.sv
  //
  //   The register that remembers the running total. This is the only
  //   SEQUENTIAL module in the design.
  //
  //   module accumulator #(
  //       parameter int unsigned ACC_W = 32
  //   ) (
  //       input  logic                    clk_i,
  //       input  logic                    rst_ni,
  //       input  logic                    clear_i,  // force the total to 0
  //       input  logic                    en_i,     // load d_i this cycle
  //       input  logic signed [ACC_W-1:0] d_i,
  //       output logic signed [ACC_W-1:0] q_o
  //   );
  //
  //   Behaviour, in priority order:
  //       !rst_ni  -> q <= 0
  //       clear_i  -> q <= 0        (starting a new output pixel)
  //       en_i     -> q <= d_i
  //       else     -> hold
  //
  //   Hints:
  //     - always_ff @(posedge clk_i), nonblocking `<=`.
  //     - "else hold" means writing nothing. In a clocked block that is
  //       correct and is NOT a latch -- it is just a flop with an enable.
  //     - q_o is the register's output, so `assign q_o = q;` at the end
  //       (or declare q_o as the register directly -- your choice).
  // --------------------------------------------------------------------------

  // --------------------------------------------------------------------------
  // MODULE 3 of 3:  rtl/relu_unit.sv
  //
  //   ReLU, the activation function: y = max(x, 0). Negative in, zero out;
  //   positive in, unchanged. Combinational.
  //
  //   module relu_unit #(
  //       parameter int unsigned ACC_W = 32
  //   ) (
  //       input  logic signed [ACC_W-1:0] x_i,
  //       output logic signed [ACC_W-1:0] y_o
  //   );
  //
  //   Hints:
  //     - In hardware this is a mux controlled by the sign bit, which is why
  //       ReLU won over smooth activation functions for accelerators: it
  //       costs almost nothing. One mux versus an exponential.
  //     - `assign y_o = (x_i < 0) ? '0 : x_i;` works IF x_i is signed. If you
  //       forgot `signed`, `x_i < 0` is never true and this silently becomes
  //       a wire.
  //     - You could also test the sign bit x_i[ACC_W-1] directly. Same gate.
  // --------------------------------------------------------------------------


  // ==========================================================================
  // STEP 2 -- Wire them together here.
  //
  // You need two internal signals to connect the three blocks:
  //
  //     acc_q       the accumulator's output (the running total)
  //     mac_result  the MAC's output (total + new product)
  //
  // Then three instantiations:
  //
  //     mac_unit    reads act_i, wgt_i, acc_q   -> drives mac_result
  //     accumulator reads mac_result            -> drives acc_q
  //     relu_unit   reads acc_q                 -> drives relu_o
  //
  // And sum_o is just acc_q.
  //
  // --- HOW TO INSTANTIATE A MODULE ------------------------------------------
  //
  //     mac_unit #(                   // 1. the module's name
  //         .DATA_W (DATA_W),         // 2. parameters, in #( )
  //         .ACC_W  (ACC_W)
  //     ) u_mac (                     // 3. YOUR name for this copy
  //         .act_i    (act_i),        // 4. ports: .their_name (your_signal)
  //         .wgt_i    (wgt_i),
  //         .acc_i    (acc_q),
  //         .result_o (mac_result)
  //     );
  //
  //   Read line 4 as: "the submodule's port `act_i` connects to my signal
  //   `act_i`". The two names are unrelated -- they are the same here only
  //   because it reads nicely. On the `.acc_i (acc_q)` line they differ.
  //
  //   Always connect ports BY NAME like this. Verilog also allows connecting
  //   them by position, which works perfectly until the day someone adds a
  //   port in the middle and every design downstream silently miswires.
  //
  //   The `u_` prefix on instance names is a common convention ("unit").
  //
  // --- THE ONE THING THAT WILL LOOK WRONG -----------------------------------
  //
  //   mac_unit reads acc_q and accumulator produces acc_q from mac_result.
  //   That is a loop. Drawn as code it looks illegal; it is not, because the
  //   register breaks it: the MAC sees the value the register settled on at
  //   the LAST clock edge, and its output is captured at the NEXT one. The
  //   loop goes through a flop, so there is no combinational cycle.
  //
  //   This is the normal shape of every accumulator in every accelerator.
  //
  // --- TIMING, so your testbench expectations are right ---------------------
  //
  //   The accumulator updates ON the clock edge. So a pair presented during
  //   cycle N shows up in sum_o during cycle N+1. After the last of four
  //   valid pairs, you wait one more edge before reading the answer.
  // ==========================================================================

  // <-- declare acc_q and mac_result here

  // <-- instantiate mac_unit, accumulator, relu_unit here

  // <-- drive sum_o and relu_o here

endmodule
