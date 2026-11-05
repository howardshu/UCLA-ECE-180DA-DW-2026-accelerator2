Implement an initial three-PE CNN accelerator for my UCLA ECE180DA project. Inspect the existing repository and make working, tested changes. Follow the staged plan below, completing the initial implementation milestone before expanding scope.

### Sources and constraints

Read the repository’s AGENTS.md and these references:

- Accelerator specification: `/Users/howardshu/Downloads/OoO AcceleratorDescription.docx.pdf`
- CDR presentation: `/Users/howardshu/Downloads/diagrams — formatting fixed.pptx`
- Existing repository, if still located here: `/Users/howardshu/Documents/SENIOR/fall/ece180da/UCLA-ECE-180DA-DW-2026-accelerator2`

Locate the actual implementation directory before editing. Treat files under `sources/` as read-only. Inspect the current Common interfaces and existing PE/testbench code before introducing replacements.

The specification takes precedence over earlier proposed designs. Do not implement the previously suggested generic convolution descriptor, fixed 3×3 kernels, or shared-memory DMA loading architecture.

### Target network

One job should execute one complete inference:

1. Input: `28×28×1`, uint8.
2. Conv1: three `5×5×1` filters, stride 1, valid convolution, bias, requantization, ReLU. Output `24×24×3`.
3. Pool1: 2×2 max pooling, stride 2. Output `12×12×3`.
4. Conv2: three `5×5×3` filters, stride 1, valid convolution, bias, requantization, ReLU. Output `8×8×3`.
5. Pool2: 2×2 max pooling, stride 2. Output `4×4×3`.
6. Flatten to 48 elements.
7. FC: ten length-48 dot products plus biases, producing ten int32 logits.
8. Signed argmax producing digit 0–9.

The external memories are:

- IMG: 2,048 entries × 8 bits, containing two 1,024-byte image slots.
- WGT: 1,024 entries × 8 bits, containing 780 int8 weights.
- PARAM: 32 entries × 32 bits.

PARAM layout:

- 0: magic `0x434E4E01`
- 1: version `1`
- 2–3: `shift1`, `shift2`
- 4–6: Conv1 biases
- 7–9: Conv2 biases
- 10–19: FC biases
- 20–31: reserved

Consult the actual specification for additional requirements.

### Architecture decision: three PEs initially

Use three PEs in parallel across output channels, computing one spatial position at a time.

- Conv1: broadcast one activation and provide three filter weights; 25 MAC updates per output position.
- Conv2: same organization, with 75 MAC updates per output position.
- FC: compute output neurons in groups of 3, 3, 3, and 1, disabling unused lanes.

Six PEs remain under consideration pending professor feedback. Do not implement a second spatial group now. Keep the PE-array boundary and controller organization suitable for later adding a second three-PE spatial group, without building unused complexity.

### Phase 1: inspect and establish the arithmetic contract

Report which modules and interfaces already exist, which tests pass, and which requirements remain unresolved.

Confirm or identify missing definitions for:

- Intermediate activation width and signedness.
- Requantization shifts, rounding, saturation, and zero points.
- Tensor, filter, and flatten ordering.
- External memory read timing and the actual `acc_load_if`.
- CSR configuration meanings and result return path.

Do not present assumptions as specification requirements. Isolate provisional numerical/addressing conventions in named helpers or configuration definitions and document them. Continue independent PE and control work while identifying questions requiring team agreement.

### Phase 2: implement and verify the PE and three-lane array

Reuse or fix existing PE code where practical, including parameter forwarding.

Recommended initial datapath, assuming intermediate activations are 8 bits:

- Activation input: signed 9 bits.
- Weight input: signed 8 bits.
- Product: signed 17 bits.
- Bias, accumulator, and sum output: signed 32 bits.
- Control signals: 1-bit unsigned.

Zero-extend uint8 image pixels into the signed activation input. Sign-extend signed int8 intermediate values if that is the agreed format.

Use a separate bias-initialization cycle, followed by enabled MAC updates. Define reset/init/MAC priority explicitly. When disabled, accumulators hold.

Keep quantization outside the basic MAC PE. Preserve signed FC logits and bypass convolution-only postprocessing.

Test:

- Pixels above 127.
- Negative and extreme weights.
- Nonzero biases.
- Stalls and initialization priority.
- Exactly 25, 75, and 48 MAC updates.
- Consecutive independent dot products.
- Three lanes with distinct weights and biases.

### Phase 3: implement the convolution kernel and fused pooling

Build a controller that computes all three channels of one pooled output.

For pooled location `(py, px)`, compute these convolution positions sequentially:

```text
(2py,   2px)
(2py,   2px+1)
(2py+1, 2px)
(2py+1, 2px+1)
```

Each position produces three channel results.

For each position:

1. Initialize the three accumulators with their biases.
2. Read operands and perform the full reduction.
3. Capture the completed sums after the final MAC update.
4. Apply the agreed requantization and ReLU.
5. Update three pooling maxima.

After four positions, write three pooled outputs. Initialize maxima from the first valid position rather than relying on a special reset value.

Use three local convolution weight banks, each holding up to 75 int8 weights. Broadcast one activation to the three PEs.

Make operand latency explicit. A conservative read-issue/read-consume/MAC schedule is acceptable initially. Never advance reduction counters or MAC enables without valid operands.

Test the complete Conv1/Pool1 result against a software reference. Structure the kernel so it can subsequently support Conv2’s three-channel input and 75-term reduction.

### Initial implementation milestone

Complete phases 1–3 first:

- Working three-PE datapath.
- Working convolution/pooling controller.
- Software reference and self-checking simulations.
- Full Conv1/Pool1 comparison using synthetic data.
- Documented provisional assumptions and remaining integration questions.

Use testbench memory models or a small internal adapter when the final external interface is unavailable. Do not invent or modify the shared Common contract silently.

Quantization-dependent comparisons must state the exact provisional policy used. Passing those tests must not be described as proof of compatibility with unreleased numerical rules.

### Later phases

After the initial milestone:

1. Complete Conv2/Pool2 and intermediate activation storage.
2. Implement FC lane masking, logits, and signed argmax.
3. Integrate external memories and CSR job control.
4. Validate complete repeated inferences and error behavior.
5. Synthesize and measure cycles, timing, and resource use.
6. Evaluate six PEs after professor feedback.

For CSR integration, capture configuration once per accepted job, execute once per activation, and hold completion until activation clears. Confirm result delivery before choosing a result CSR or IMG writeback. Do not assume IMG supports accelerator writes or software readback.

### Verification and reporting

Use meaningful self-checking tests and compare intermediate tensors, not only the predicted digit. Include operand delays, stalled output acceptance, back-to-back operations, and invalid configuration where applicable.

Avoid broad unrelated refactoring.

At completion, report:

- Modules implemented or changed.
- Tests run and their actual results.
- Implemented versus incomplete functionality.
- Provisional assumptions and unresolved team decisions.
- The next implementation step.

Proceed with the initial milestone rather than stopping after producing another plan.