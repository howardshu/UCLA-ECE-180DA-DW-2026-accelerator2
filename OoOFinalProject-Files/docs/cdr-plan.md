# CNN Accelerator: Post-PDR Findings and CDR Plan

CDR: **Thursday, November 5 (Week 6)**, in class. All members attend and explain their own contributions.

## 1. What changed since the PDR

The course repo (`OoOFinalProject-Files`) added the accelerator spec, `tb/tb_accelerator.sv`, six golden vectors, `common/cnn_ext_mem.sv`, and the network constants in `common/accelerator_pkg.sv`. These replace several PDR assumptions:

| PDR assumption | Actual contract |
|---|---|
| Transfer controller fetches tensors over `data_memory_if` | Not used. The accelerator reads external IMG/WGT/PARAM directly over `cnn_mem_if`; results stay in an internal RES memory, read through `acc_debug_if`. |
| `memory_location` / `length` undefined | `memory_location` = image byte offset in IMG (`0x000` or `0x400`); `length` must be 784, otherwise raise `error` **and** complete. |
| 4 PEs | Both convolutions have 3 output channels: 3 output-channel PEs. |
| Arithmetic undefined | uint8 activations, int8 weights, int32 accumulators/biases. |
| Top-level ports open | `accelerator_top(clk_i, rst_ni, csr, xmem, dbg, dbg_busy_o, dbg_cycles_o)`. |
| Buffer sizes open | ACT_A 2048 B, ACT_B 512 B, RES 16 words, with the buffer reuse below. |

## 2. Exact semantics (verified against every golden vector)

`model/cnn_ref.py` reproduces all six vectors exactly at every layer (`make model`).

- Activations are **HWC**: `act[(h*W + w)*C + c]`. The fc flatten order is the same.
- Conv weights are **`[oc][kh][kw][ic]`**: `wgt[base + ((o*5 + r)*5 + s)*C + c]`; conv1 base `0x000`, conv2 base `0x080`.
- FC weights are **`[o][i]`**: `wgt[0x180 + o*48 + i]`.
- Conv: `acc = bias[o] + Σ x·w`; `y = clamp(acc >>> shift, 0, 255)` (arithmetic shift, no rounding; ReLU and saturation are the same clamp). conv1 uses `shift1`, conv2 `shift2`.
- FC: `logit = bias + Σ p2·w`, int32, no shift, no ReLU.
- RES: words 0–9 logits, 10 argmax, 11 MAGIC (written last).
- Worst-case accumulator magnitude is about 2.4M (23 bits); `acc_t` (32 bits) is safe.

Use `python3 model/cnn_ref.py trace <vector> --layer conv1 --h H --w W --o O` to print every MAC of one output while debugging.

## 3. Architecture

```
            csr (activate, memory_location, length / done, error)
                |
         +------v-------+   layer, start/done    +-------------------+
         | acc_controller|----------------------->| acc_conv (3 PEs)  |
         | CHECK, PARAM  |   shifts, biases       | acc_pool          |
         | preload, seq  |                        | acc_fc + argmax   |
         +------+-------+                        +---------+---------+
                | PARAM                                    | (port mux by layer)
   xmem: IMG ---+------------------------------------------+
         WGT ------------------------------------------------+
                                    ACT_A (2048 B)  ACT_B (512 B)  RES (16 x 32)
                                          \             |             /
                                           +--- dbg (read-only) -----+
```

Dataflow (one engine at a time):

| Layer | Source | Destination | MACs | Est. cycles (3 PEs) |
|---|---|---|---|---|
| conv1 | IMG + offset | ACT_A (a1, 1728 B) | 43,200 | ~14,400 |
| pool1 | ACT_A | ACT_B (p1, 432 B) | – | ~1,728 |
| conv2 | ACT_B | ACT_A (a2, 192 B) | 14,400 | ~4,800 |
| pool2 | ACT_A | ACT_B (p2, 48 B) | – | ~192 |
| fc + argmax | ACT_B, WGT | RES[0..10] | 480 | ~480 |
| weight preload | WGT | conv reg file | – | 300 |

Total is roughly **22k cycles**. The bottleneck is that each external memory returns one byte per cycle.

Key decisions:

- **3 output-channel PEs, input broadcast.** One input byte per cycle feeds all three PEs.
- **Conv weights preloaded into registers** (75 or 225 B). WGT can supply only one byte per cycle, but each PE needs its own weight every cycle.
- **Uniform 1-cycle read latency.** The top level registers async external data, or passes synchronous data through, so engines behave identically with `cnn_ext_mem` `REGISTERED_READ` set to 0 or 1, and internal memories infer block RAM.
- **Controller owns PARAM.** It preloads words 0–19 once per job and hands shifts and biases to the engines.
- **Completion as a level.** `done` holds in `DONE` until `activate` drops, so a held `activate` cannot restart the job. RES MAGIC is cleared when a job is accepted and written as the last step.
- **Stretch goal:** a 5-row line buffer plus a 5×5 window reads each pixel once (conv1 about 800 cycles) at the cost of 75 multipliers.

## 4. Implementation status

| Module | Status |
|---|---|
| `model/cnn_ref.py` | Done; matches all vectors. Can generate new vectors (`gen`). |
| `rtl/accelerator_top.sv` | Done: ports, memories, port muxing, latency normalization, debug port. |
| `rtl/acc_controller.sv` | Done: handshake, config/PARAM checks, PARAM preload, sequencing, MAGIC. |
| `rtl/acc_ram.sv` | Done. |
| `rtl/acc_conv.sv` | **Stub.** Header gives the exact formulas and proposed schedule. |
| `rtl/acc_pool.sv` | **Stub.** |
| `rtl/acc_fc.sv` | **Stub.** |
| `tb/tb_team.sv` | Done: all vectors, layer checks, handshake, repeat, bad length/offset, mid-job reset, both memory modes. |

With the stub engines, `make sim` passes the handshake, bad-length and bad-offset checks and fails the result checks (expected). The mid-job reset test only becomes meaningful once the engines take longer than 500 cycles.

## 5. Open questions (post on Campuswire)

1. The course testbench references files that are not in the repo: `cnn_mem_if.sv`, `acc_debug_if.sv`, `cnn_golden_model`, `acc_check.svh`, `build.sh`, `acc_load_if.sv`, and package `accelerator_cnn_pkg` (the repo declares `accelerator_pkg`). Our stand-ins are in `rtl/stubs/`; the Makefile switches to the official files automatically once they appear.
2. The spec says IMG is "two-port". Do we get two read ports? `cnn_ext_mem` exposes one.
3. Error conditions beyond a bad length: an offset where the image would not fit? A wrong MAGIC or version? (We currently flag all three.)
4. Will grading use `REGISTERED_READ=1`? (We support both.)
5. How does the processor read the result: only through the debug interface, or through a memory-mapped path?
6. Argmax tie-break (we assume the first maximum).
7. Target FPGA, clock target, and performance expectations.

## 6. Plan to CDR

| Day | Control/integration | Datapath | Verification |
|---|---|---|---|
| Sat 10/31 – Sun 11/1 | Post the Campuswire questions; review the controller | `acc_conv` weight preload + 3-PE MAC | Unit test for requant/MAC against `cnn_ref.py` |
| Mon 11/2 | Swap in official interfaces if released | conv1 end to end | `make sim BRINGUP=1` passes |
| Tue 11/3 | Cycle-count reporting | `acc_pool`, conv2 | `BRINGUP=2`, `BRINGUP=3` pass |
| Wed 11/4 | CDR diagrams and walkthrough | `acc_fc` + argmax | Full `make sim` and `make sim-sync` pass |
| Thu 11/5 | **CDR** | | |

Minimum credible CDR: conv1 + pool1 verified layer by layer, and the controller passing every control test. Stretch: the full network passing in both memory modes.

CDR walkthrough: trace conv1 output `a1[(10*24 + 10)*3 + 0]` on `v0_box` (`cnn_ref.py trace`), from the IMG address through broadcast, MAC, requant, and the ACT_A write.
