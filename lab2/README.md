# ECE180 Lab 2 — CNN Processing Element

A 1-hour in-class lab. You write three SystemVerilog modules, wire them into a
multiply-accumulate processing element, and write a testbench for it.

**Start here: [`WORKBOOK.md`](WORKBOOK.md)**

## Quick start

```bash
verilator --version     # need 5.0+;  apt-get install verilator  /  brew install verilator
make check              # CHECK FAIL (14 errors) right now — that's your progress bar
```

## Layout

```
WORKBOOK.md      the lab — read this
Makefile
rtl/pe_top.sv    the only file you're given: ports + specs for 3 submodules
rtl/             ...you create mac_unit.sv, accumulator.sv, relu_unit.sv here
tb/tb_pe.sv      your testbench — you finish this in Part 3
tb/tb_check.sv   instructor testbench — do not edit
```

## Targets

| | |
|---|---|
| `make check` | instructor testbench — *is my RTL correct?* |
| `make tb` | your testbench |
| `make lint` | syntax check only, ~1s — use constantly |
| `make wave` | run your testbench, dump `build/tb/pe.vcd` |
| `make clean` | |

## The hour

| | | min |
|---|---|---|
| Part 1 | write `mac_unit`, `accumulator`, `relu_unit` | 20 |
| Part 2 | instantiate and wire them in `pe_top` | 15 |
| Part 3 | write your own testbench | 20 |

Behind schedule? Don't skip Part 3.
