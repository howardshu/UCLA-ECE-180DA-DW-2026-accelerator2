# Single processing element

Implements the bias/feedback mux in slide 3 ("One PE") of the supplied deck.
The PDF specifies uint8 input, int8 weights and int32 biases/logits. Shift and
saturation follow `acc_internal_pkg::requant` and the course golden vectors.
The existing operand names `act_i` / `wgt_i` correspond to the diagram's
`value_i` / `weight_i`.

## Interface and timing

Default widths: unsigned 8-bit `act_i`, signed 8-bit `wgt_i`, signed 32-bit
`bias_i` and `sum_o`. `shift_i` is 5 bits at the default width.

On each rising edge, in priority order:

1. Active-low `rst_ni` resets the sum to zero (also asynchronously).
2. `clear_i` clears the sum to zero, even when `valid_i` is high.
3. With `valid_i`, update to `(first_mac_i ? bias_i : sum_o) + act_i*wgt_i`.
4. Otherwise hold the sum. A stalled `first_mac_i` does not load the bias.

Assert `first_mac_i` alongside the **first valid operand pair** for each output.
It replaces any previous sum, so consecutive dot products need no clear cycle.
Keep it asserted until that first pair is actually valid if memory stalls.
Bias only needs to be stable for the first accepted pair.

- `sum_o`: raw signed sum; use this for FC logits.
- `requant_o`: unsigned DATA_W-bit `clamp(sum_o >>> shift_i, 0, 2**DATA_W-1)`;
  use this for convolution/pooling. No rounding.

Outputs reflect the updated register immediately after the accepting edge
(and combinational propagation). There is no extra output register, done flag,
or operand ready signal. The caller counts 25 accepted pairs for conv1, 75 for
conv2, or 48 for FC, then captures the corresponding output before overwriting
it. Hold `shift_i` stable until that convolution output has been consumed.

Example: first pair `act=255, wgt=-2, bias=100, first_mac=1, valid=1`
produces `sum=-410`. Next pair `act=128, wgt=4, first_mac=0, valid=1`
produces `sum=102`. At shift 1, `requant_o=51`.
The clamp includes ReLU; there is no separate ReLU module or output.

Parameters propagate to every submodule. Supported widths require DATA_W >= 1,
ACC_W >= 2*DATA_W+1. The shift port has $clog2(ACC_W) bits.
Accumulator arithmetic wraps at ACC_W bits; only `requant_o` saturates.
A sufficiently extreme bias can overflow even when the products alone fit.

## Verification and integration

Run `make lint-pe` and `make sim-pe` from the repository root. The testbench
checks every cycle against integer arithmetic, directed reset/clear/stall/bias
and overflow cases, randomized controls, and a second DATA_W=4 / ACC_W=16 PE.
For every supplied vector it streams all conv1 and conv2 dot products and all
10 FC logits through the PE, comparing final outputs to golden files. Conv2
and FC use golden pooled inputs to isolate PE arithmetic from layer engines.

The PE is independently buildable and has no package dependencies.
`rtl/acc_conv.sv` instantiates three PEs, one per output channel, broadcasts the
activation, and supplies separate weights and biases. It preloads 75/225 bytes
of weights into three banks, pipelines operand addresses for the one-cycle
read latency, and serializes the three result bytes onto ACT_A.

`rtl/acc_pool.sv` implements unsigned 2x2 stride-2 max pooling from ACT_A to
ACT_B with one comparator and a running maximum register. It reads the four
samples of each output sequentially. Convolution and pooling remain separate
passes through the existing controller/memory interfaces (not fused).

Run `make sim BRINGUP=4` and `make sim-sync BRINGUP=4` for the complete
conv1 -> pool1 -> conv2 -> pool2 datapath in both external memory modes.
The testbench checks every output write, address and count at all four layers,
including layers overwritten later, across all six course vectors. It also
checks repeat jobs, invalid configuration and recovery from resets during
convolution and pooling. Nominal jobs currently take 24,997 testbench cycles,
including controller overhead and the FC stub; this is not full inference
performance. The FC engine remains a stub, so full result checking (`BRINGUP=0`)
is not expected to pass yet.
