# Accelerator Team 2: MNIST CNN Accelerator

Fixed-function accelerator for a small MNIST CNN, attached to the RV32 out-of-order core through `csr_accelerator_if`. The course files (`common/`, `tb/tb_accelerator.sv`, `tb/vectors/`) come from upstream [nader-sehat/UCLA-ECE-180DA-DW-2026](https://github.com/nader-sehat/UCLA-ECE-180DA-DW-2026/tree/main/OoOFinalProject-Files); everything else in this directory is ours.

The design, the verified arithmetic, open questions and the CDR schedule are in [docs/cdr-plan.md](docs/cdr-plan.md).

## Quick start

Requires Verilator 5 (`brew install verilator`) and Python 3. Run from `OoOFinalProject-Files/`.

```bash
make model           # reference model vs. golden vectors (all should be ok)
make sim             # our testbench, async external memory
make sim-sync        # same, cnn_ext_mem REGISTERED_READ=1
make sim BRINGUP=4   # verify conv1/pool1/conv2/pool2; FC remains a stub
make sim-pe          # single-PE arithmetic and control checks
make lint-pe         # strict standalone PE lint
```

## Layout

| Path | Contents |
|---|---|
| `rtl/accelerator_top.sv` | Top level: ports required by the course testbench, internal memories, port routing |
| `rtl/acc_controller.sv` | CSR handshake, config checks, PARAM preload, layer sequencing |
| `rtl/acc_conv.sv` | Three output-channel PEs, weight preload and convolution address generation |
| `rtl/acc_pool.sv` | Unsigned 2x2 stride-2 max pooling |
| `rtl/acc_fc.sv` | Fully connected layer (**stub**) |
| `rtl/pe/` | Bias-initialized MAC PE with shift, ReLU and saturation in one clamp |
| `rtl/acc_ram.sv` | Block-RAM-style memory with a debug read port |
| `rtl/acc_internal_pkg.sv` | Internal types and the requant function |
| `rtl/stubs/` | Stand-ins for course files the testbench needs but the repo does not ship yet |
| `tb/tb_team.sv` | Our testbench (mirrors the course `tb_accelerator.sv` checks) |
| `model/cnn_ref.py` | Bit-exact Python reference model: `check`, `gen`, `trace` |

## Engine contract

Every engine gets a one-cycle `start_i` pulse and pulses `done_o` when its last write is done. Every read port has exactly **one cycle of latency**: the address driven in cycle *t* returns data in cycle *t+1*. Configuration is stable for the whole job.
