// ============================================================================
// tb_pe.sv -- YOUR testbench. This is Part 3 of the lab; you finish this file.
//
// A testbench is not hardware. It is a program whose job is to lie to your
// design convincingly: generate a clock, wiggle the inputs, and check that
// the outputs are what you predicted. Nothing in this file is synthesized,
// so you can use `initial`, `#` delays, `$display`, loops, and other things
// that are illegal in RTL.
//
// Every testbench has the same five parts. They are marked PART A..E below.
// ============================================================================
module tb_pe;

  // --------------------------------------------------------------------------
  // PART A -- signals to connect to the design
  //
  // One variable per DUT port. Inputs you will drive; outputs you will read.
  // --------------------------------------------------------------------------
  localparam int unsigned DATA_W = 8;
  localparam int unsigned ACC_W  = 32;

  logic                     clk_i = 0;   // start at a known value, not X
  logic                     rst_ni;
  logic                     clear_i;
  logic                     valid_i;
  logic signed [DATA_W-1:0] act_i;
  logic signed [DATA_W-1:0] wgt_i;
  logic signed [ACC_W-1:0]  sum_o;
  logic signed [ACC_W-1:0]  relu_o;

  int errors = 0;   // count problems; print a verdict at the end

  // --------------------------------------------------------------------------
  // PART B -- the clock
  //
  // Flip it forever. `#5` waits 5 time units, so this is a 10-unit period.
  // The exact number does not matter in a functional simulation -- what
  // matters is that edges keep arriving.
  // --------------------------------------------------------------------------
  always #5 clk_i = ~clk_i;

  // --------------------------------------------------------------------------
  // PART C -- instantiate the design under test (the "DUT")
  //
  // Exactly the same syntax you used inside pe_top to instantiate mac_unit.
  // A testbench is just another module that instantiates things.
  // --------------------------------------------------------------------------
  pe_top #(
      .DATA_W (DATA_W),
      .ACC_W  (ACC_W)
  ) dut (
      .clk_i   (clk_i),
      .rst_ni  (rst_ni),
      .clear_i (clear_i),
      .valid_i (valid_i),
      .act_i   (act_i),
      .wgt_i   (wgt_i),
      .sum_o   (sum_o),
      .relu_o  (relu_o)
  );

  // --------------------------------------------------------------------------
  // PART D -- helper tasks
  //
  // Write the fiddly driving code ONCE, then call it. A testbench without
  // helpers becomes an unreadable wall of @(posedge) within ten minutes.
  //
  // WHY EVERYTHING HAPPENS ON @(negedge clk_i):
  //   The design samples its inputs on the RISING edge. If you change an
  //   input at the same instant the design samples it, whether the old or
  //   new value gets captured is a coin flip. So the testbench drives on the
  //   FALLING edge -- half a cycle of margin on either side. Drive on negedge,
  //   check after posedge. Follow that rule and race conditions mostly stop
  //   happening to you.
  // --------------------------------------------------------------------------

  // Hold reset for a couple of cycles, then release it.
  task automatic do_reset();
    rst_ni  = 1'b0;
    clear_i = 1'b0;
    valid_i = 1'b0;
    act_i   = '0;
    wgt_i   = '0;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni = 1'b1;
  endtask

  // Zero the accumulator: assert clear for exactly one clock edge.
  task automatic do_clear();
    @(negedge clk_i);
    clear_i = 1'b1;
    @(posedge clk_i);
    @(negedge clk_i);
    clear_i = 1'b0;
  endtask

  // Present one (activation, weight) pair for exactly one clock edge.
  task automatic send(input logic signed [DATA_W-1:0] a,
                      input logic signed [DATA_W-1:0] w);
    @(negedge clk_i);
    valid_i = 1'b1;
    act_i   = a;
    wgt_i   = w;
    @(posedge clk_i);
    @(negedge clk_i);
    valid_i = 1'b0;
  endtask

  // Compare one value against what you expected, and complain if it differs.
  //
  // Use `!==` and not `!=` in a testbench. `!==` also catches X and Z, which
  // is exactly what you want: an uninitialised output is a bug, but `!=`
  // against an X returns X, which is falsy, so the check silently passes.
  task automatic check(input string name,
                       input logic signed [ACC_W-1:0] got,
                       input logic signed [ACC_W-1:0] exp);
    if (got !== exp) begin
      $display("  FAIL %-24s got=%0d  expected=%0d", name, got, exp);
      errors++;
    end else begin
      $display("  ok   %-24s = %0d", name, got);
    end
  endtask

  // --------------------------------------------------------------------------
  // PART E -- the actual test
  //
  // One worked example is written out for you. Then it is your turn.
  // --------------------------------------------------------------------------
  initial begin
    $display("=== tb_pe ===");

    do_reset();

    // ========================================================================
    // TEST 1 -- a 4-element dot product.  WORKED EXAMPLE, read it carefully.
    //
    //     activations:  1,  2,  3,  4
    //     weights:      5,  6,  7,  8
    //     expected:  1*5 + 2*6 + 3*7 + 4*8 = 5 + 12 + 21 + 32 = 70
    // ========================================================================
    do_clear();

    send(8'sd1, 8'sd5);
    send(8'sd2, 8'sd6);
    send(8'sd3, 8'sd7);
    send(8'sd4, 8'sd8);

    // The accumulator updates ON the clock edge, so after the last `send`
    // the value is already settled. Read it now.
    check("test1 sum",  sum_o,  70);
    check("test1 relu", relu_o, 70);   // positive, so ReLU passes it through


    // ========================================================================
    // TEST 2 -- YOUR TURN: make the result NEGATIVE and check ReLU clamps it.
    //
    // This is the test that actually earns its keep. Test 1 would still pass
    // if you had forgotten `signed` everywhere and if relu_unit were a plain
    // wire. Only a negative result can tell those bugs apart.
    //
    // Suggested vectors:
    //     activations:  2,  3
    //     weights:     -4, -5
    //     sum  = 2*(-4) + 3*(-5) = -8 + (-15) = -23
    //     relu = 0
    //
    // TODO:
    //   1. do_clear();
    //   2. two send() calls with the vectors above
    //      (write negative literals as  -8'sd4  or just  -4 )
    //   3. check("test2 sum",  sum_o,  -23);
    //   4. check("test2 relu", relu_o,   0);
    // ========================================================================



    // ========================================================================
    // TEST 3 -- YOUR TURN: does clear_i actually work?
    //
    // If clear_i were broken, every test would still pass as long as you only
    // ever ran one dot product. The bug only appears on the SECOND output
    // pixel, when leftovers from the first are still sitting in the register.
    // This is a very common real bug and it is worth one test.
    //
    // TODO:
    //   1. do_clear();
    //   2. send some pairs (any values) and check the sum
    //   3. do_clear() again
    //   4. check that sum_o is now 0 -- NOT the old total
    //   5. run a different dot product and confirm the new answer is right
    //      and has no contamination from step 2
    // ========================================================================



    // ========================================================================
    // TEST 4 -- YOUR TURN (if you have time): does valid_i gate correctly?
    //
    // Idle cycles must not change the total. If your accumulator ignores
    // en_i, garbage accumulates whenever the pipeline has a bubble -- and
    // real accelerators have bubbles constantly.
    //
    // TODO:
    //   1. do_clear(); send one pair; remember the sum
    //   2. hold valid_i low for a few cycles:
    //          @(negedge clk_i); act_i = 99; wgt_i = 99;   // junk on the bus
    //          repeat (3) @(posedge clk_i);
    //   3. check sum_o is UNCHANGED -- the junk must not have accumulated
    // ========================================================================



    // ------------------------------------------------------------------------
    // Verdict. Always print one. A testbench that scrolls past without a
    // clear PASS/FAIL line is a testbench nobody reads.
    // ------------------------------------------------------------------------
    $display("");
    if (errors == 0) $display("tb_pe: PASS");
    else             $display("tb_pe: FAIL  (%0d errors)", errors);
    $finish;
  end

  // --------------------------------------------------------------------------
  // Waveform dump: `make wave` then open build/tb/pe.vcd in GTKWave or Surfer.
  // Seeing acc_q step 0 -> 5 -> 17 -> 38 -> 70 is worth more than any
  // $display you will ever write.
  // --------------------------------------------------------------------------
  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("build/tb/pe.vcd");
      $dumpvars(0, tb_pe);
    end
  end

  // Safety net: if the design hangs, say so instead of running forever.
  initial begin
    #100000;
    $display("tb_pe: TIMEOUT -- simulation never reached $finish.");
    $fatal(1);
  end

endmodule
