# ECE180 Lab 2 — Build a CNN Processing Element

**1 hour, in class · Verilator · You write almost all of the code**

Lab 1 had you fill in blanks. This one does not. You get one file — a top module with comments describing three submodules — and you write those modules, wire them together, and then write a testbench to prove they work.

That is the real job. Nobody hands you a file with `// <-- fill in` on the line where the bug is.

---

## What you are building

A convolution layer computes, for every output pixel:

```
out = ReLU( Σ activation[i] × weight[i] )
```

For a 3×3 filter that is 9 multiplies and 8 adds. For a real layer it is millions. But look at the *shape* of the work: it is the same tiny operation — multiply, add to a running total — repeated forever.

So an accelerator doesn't build a giant adder tree. It builds one small **multiply-accumulate** unit, called a **processing element (PE)**, and streams data through it one pair per cycle:

```
cycle 0:   acc = 0   + a0×w0
cycle 1:   acc = acc + a1×w1
cycle 2:   acc = acc + a2×w2
cycle 3:   acc = acc + a3×w3      ← acc is now the dot product
then:      out = ReLU(acc)
```

Real accelerators tile hundreds of PEs into a grid — a *systolic array* — and stream activations across while weights flow down. Every one of those cells is what you are about to build.

### The block diagram

```
                +-------------------------------------+
  act_i --------|                                     |
  wgt_i --------|             mac_unit                |
          +-----|  (combinational: acc_i + act×wgt)   |
          |     +------------------+------------------+
          |                        | mac_result
          |                        v
          |     +-------------------------------------+
          |     |            accumulator              |
          |     |  (REGISTER: holds the running total)|
          |     +------------------+------------------+
          |                        | acc_q
          +------------------------+          ← feedback
                                   |
                                   +---------> sum_o
                                   |
                +------------------v------------------+
                |              relu_unit              |
                |      (combinational: max(x, 0))     |
                +------------------+------------------+
                                   |
                                   +---------> relu_o
```

Two clouds, one box, and a feedback path from the register's output back to the MAC's input.

That feedback is Lab 1's **combinational read, sequential write** pattern: read the current total straight out of the register with no extra flop, add to it, write the result back on the next edge. It looks like an illegal loop written as code. It isn't — the loop passes through a register, so there is no combinational cycle.

---

## Setup (2 minutes)

```bash
cd lab2
make check      # should compile and report CHECK FAIL (14 errors) — correct for now
```

`make check` runs an instructor testbench against your RTL. It fails right now because nothing is written. That's your progress bar.

Need Verilator 5.0+: `sudo apt-get install verilator` / `brew install verilator`.

| Command | |
|---|---|
| `make check` | run the instructor testbench — *is my RTL right?* |
| `make tb` | run **your** testbench — Part 3 |
| `make lint` | syntax check only, ~1 second. Use this constantly. |
| `make wave` | run your testbench, dump `build/tb/pe.vcd` |
| `make clean` | |

Everything in `rtl/` compiles automatically. Drop new files in; no Makefile edits.

### Plan for the hour

| | | min |
|---|---|---|
| Part 1 | Write the three modules | 20 |
| Part 2 | Wire them up in `pe_top`, get `make check` passing | 15 |
| Part 3 | Write your own testbench | 20 |
| | Slack / questions | 5 |

If you fall behind, **Part 3 is the part not to skip.** Writing a testbench is the skill you will use every single day; wiring three modules you will pick up by osmosis.

---

## Part 1 — Write the three modules (20 min)

Open `rtl/pe_top.sv`. The full specification for each module — port list, behaviour, hints — is in the comments there. This section is the overview; the file is the spec.

Create each as its own file in `rtl/`. **One module per file, file named after the module** — this is near-universal convention and tools assume it.

### `rtl/mac_unit.sv` — combinational

```
result_o = acc_i + (act_i × wgt_i)
```

No clock, no reset. One `assign` is enough. If you typed `posedge`, re-read the block diagram — this is a cloud, not a box.

### `rtl/accumulator.sv` — sequential

The only clocked module in the design. Priority order:

```
!rst_ni  →  q <= 0
clear_i  →  q <= 0        (starting a new output pixel)
en_i     →  q <= d_i
else     →  hold
```

"Else hold" means writing nothing. In a clocked block that is correct and is **not** a latch — it is a flop with an enable. (In `always_comb` the same omission *would* be a latch. Same syntax, opposite meaning, depending on which block it's in.)

### `rtl/relu_unit.sv` — combinational

```
y_o = max(x_i, 0)
```

One mux controlled by the sign bit. This is why ReLU beat smooth activation functions in accelerators: one mux versus an exponential.

### The one thing that will bite you: `signed`

CNN weights and activations are **signed**. A weight of −3 is normal, and ReLU would be pointless if nothing were ever negative.

Every data signal in this design must be `logic signed`. Drop the keyword anywhere in the chain and the arithmetic silently goes unsigned: −1 becomes 255, products come out enormous, and ReLU never fires because nothing is ever negative. **Nothing warns you.**

If `make check` shows wildly-too-large positive numbers, check this first.

> Run `make lint` after each file. It takes a second and catches typos before they turn into a wall of errors at the end.

---

## Part 2 — Wire them together (15 min)

Back in `rtl/pe_top.sv`, at the bottom. You need two internal signals:

- `acc_q` — the accumulator's output, the running total
- `mac_result` — the MAC's output

and three instantiations:

| instance | reads | drives |
|---|---|---|
| `mac_unit` | `act_i`, `wgt_i`, `acc_q` | `mac_result` |
| `accumulator` | `mac_result`, `valid_i` as enable | `acc_q` |
| `relu_unit` | `acc_q` | `relu_o` |

and `sum_o = acc_q`.

### Instantiation syntax

```systemverilog
mac_unit #(                   // 1. the module's name
    .DATA_W (DATA_W),         // 2. parameters, in #( )
    .ACC_W  (ACC_W)
) u_mac (                     // 3. YOUR name for this copy
    .act_i    (act_i),        // 4. ports: .their_name (your_signal)
    .wgt_i    (wgt_i),
    .acc_i    (acc_q),
    .result_o (mac_result)
);
```

Read line 4 as *"the submodule's port `act_i` connects to my signal `act_i`."* The two names are unrelated — identical here only because it reads nicely. On `.acc_i (acc_q)` they differ.

**Always connect by name.** Verilog also allows connecting by position, which works perfectly right up until someone adds a port in the middle and every instantiation downstream silently miswires.

> **Timing, so your expectations are right.** The accumulator updates *on* the clock edge, so a pair presented during cycle N appears in `sum_o` during cycle N+1.

When this works:

```
CHECK PASS  -- MAC, accumulator, ReLU, clear and valid all correct
```

### If it doesn't

| Symptom | Likely cause |
|---|---|
| `Cannot find file containing module: mac_unit` | file not in `rtl/`, or filename ≠ module name |
| `Pin not found` / `PINMISSING` | port name typo, or a port left unconnected |
| sum is always 0 | `en_i` not wired to `valid_i`, or `clear_i` stuck high |
| sum is huge and never negative | a missing `signed` somewhere |
| sum accumulates during idle cycles | accumulator ignoring `en_i` |
| second pixel includes the first | `clear_i` not handled |

`make wave` and look at `acc_q`. Watching it step `0 → 5 → 17 → 38 → 70` tells you more in five seconds than twenty `$display`s.

---

## Part 3 — Write a testbench (20 min)

**Don't skip this.** `make check` told you *whether* your design works. It didn't teach you how to find that out for yourself, and on every project after this one there is no instructor testbench.

A testbench is not hardware. It's a program whose job is to lie to your design convincingly: generate a clock, wiggle the inputs, check the outputs against what you predicted. None of it is synthesized, so `initial`, `#` delays, `$display` and loops — all illegal in RTL — are fine here.

Open `tb/tb_pe.sv`. Every testbench has the same five parts, marked A–E:

| | |
|---|---|
| **A** | signals — one per DUT port |
| **B** | clock — `always #5 clk_i = ~clk_i;` |
| **C** | instantiate the DUT — same syntax as Part 2 |
| **D** | helper tasks — `do_reset`, `do_clear`, `send`, `check` |
| **E** | the test itself |

A–D are written for you. Read them, then write tests in E.

### Two rules worth internalising now

**Drive on the falling edge, check after the rising edge.** Your design samples inputs on the *rising* edge. Change an input at that same instant and whether the old or new value gets captured is a coin flip. Driving on `negedge` gives half a cycle of margin on both sides. Every helper task in the file does this.

**Use `!==`, not `!=`.** The `!==` operator also catches X and Z. With `!=`, a comparison against X returns X, which is falsy, so the check silently passes — an uninitialised output sails right through.

### Your tests

Test 1 is written out as a worked example: `1,2,3,4 · 5,6,7,8 = 70`. Run it:

```bash
make tb
```

```
  ok   test1 sum                = 70
  ok   test1 relu               = 70

tb_pe: PASS
```

**Now notice something.** That says PASS, and it has tested almost nothing. It would still pass if you'd forgotten `signed` everywhere and if `relu_unit` were a plain wire — because every number in it is positive. A green testbench proves only that the cases you thought of work.

That is the entire lesson of Part 3. Three more tests to write, each one catching a bug test 1 can't see:

- **Test 2 — negative result.** `2×(−4) + 3×(−5) = −23`, so ReLU must output 0. Catches both the missing-`signed` bug and a no-op ReLU.
- **Test 3 — does `clear_i` work?** Run a dot product, clear, confirm the sum is 0, run a different one and confirm no contamination. A broken `clear_i` passes every test that only computes one output pixel — and then every pixel after the first is wrong.
- **Test 4 — does `valid_i` gate?** Put junk on `act_i`/`wgt_i` with `valid_i` low for a few cycles and confirm the total doesn't move. Real accelerators have pipeline bubbles constantly.

Each is 4–6 lines using the helpers. The TODO comments in the file spell out the steps.

> Your `tb_pe.sv` won't catch everything `make check` does, and that's fine. The point is that you can now write one.

---

## Checklist

- [ ] Why an accelerator uses one small MAC repeatedly instead of a big adder tree
- [ ] Which parts of a PE are combinational and which are sequential, and why
- [ ] How the accumulator feedback loop is legal (it passes through a register)
- [ ] Why `signed` matters here, and what breaks silently without it
- [ ] How to instantiate a module, and why to connect ports by name
- [ ] The five parts of a testbench
- [ ] Why you drive on the falling edge and check after the rising edge
- [ ] Why `!==` beats `!=` in a check
- [ ] That a passing testbench only proves the cases you thought of

## If you finish early

- **Add a `done_o` output.** Take a parameter `N` (filter size), count valid cycles, pulse `done_o` when the Nth arrives. That's the PE's piece of a real control path — a fourth module and one more instantiation.
- **Saturate instead of wrapping.** Right now a huge accumulation wraps silently. Real accelerators clamp at the maximum. Where would you put that, and what does it cost?
- **Quantize the output.** Accelerators carry a wide accumulator and narrow back to int8 at the end. Add an output stage that shifts right by a parameter and truncates to 8 bits. What's lost?
- **Two PEs side by side.** Instantiate `pe_top` twice in a new top module, feed both the same activation with different weights, and you've computed two output channels at once. That's the first step toward a systolic array — and it costs you one more instantiation, which is the whole point of building it as modules.
