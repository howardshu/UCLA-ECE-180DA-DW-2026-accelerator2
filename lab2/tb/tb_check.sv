// ============================================================================
// tb_check.sv -- the instructor's testbench. DO NOT EDIT.
//
// `make check` runs this. It is here so you can find out whether your RTL is
// correct independently of whether your own testbench is complete -- the two
// are separate skills and you should not have to debug both at once.
//
// Write your own tests in tb/tb_pe.sv first, then run this to confirm.
// ============================================================================
module tb_check;

  localparam int unsigned DATA_W = 8;
  localparam int unsigned ACC_W  = 32;

  logic                     clk_i = 0, rst_ni, clear_i, valid_i;
  logic signed [DATA_W-1:0] act_i, wgt_i;
  logic signed [ACC_W-1:0]  sum_o, relu_o;
  int                       errors = 0;

  always #5 clk_i = ~clk_i;

  pe_top #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (.*);

  task automatic do_reset();
    rst_ni = 0; clear_i = 0; valid_i = 0; act_i = '0; wgt_i = '0;
    repeat (2) @(posedge clk_i);
    @(negedge clk_i); rst_ni = 1;
  endtask

  task automatic do_clear();
    @(negedge clk_i); clear_i = 1;
    @(posedge clk_i);
    @(negedge clk_i); clear_i = 0;
  endtask

  task automatic send(input logic signed [DATA_W-1:0] a,
                      input logic signed [DATA_W-1:0] w);
    @(negedge clk_i); valid_i = 1; act_i = a; wgt_i = w;
    @(posedge clk_i);
    @(negedge clk_i); valid_i = 0;
  endtask

  task automatic idle(input int n);
    @(negedge clk_i); valid_i = 0; act_i = 8'sd99; wgt_i = -8'sd77;  // junk
    repeat (n) @(posedge clk_i);
    @(negedge clk_i);
  endtask

  task automatic chk(input string name,
                     input logic signed [ACC_W-1:0] got,
                     input logic signed [ACC_W-1:0] exp);
    if (got !== exp) begin
      $display("  FAIL %-34s got=%0d expected=%0d", name, got, exp);
      errors++;
    end
  endtask

  initial begin
    do_reset();

    // --- 1. reset leaves the accumulator at zero ----------------------------
    #1 chk("reset: sum is zero", sum_o, 0);
    chk("reset: relu is zero", relu_o, 0);

    // --- 2. the worked example: 1,2,3,4 . 5,6,7,8 = 70 ----------------------
    do_clear();
    send(8'sd1, 8'sd5);
    #1 chk("after 1 pair: partial sum", sum_o, 5);
    send(8'sd2, 8'sd6);
    #1 chk("after 2 pairs: partial sum", sum_o, 17);
    send(8'sd3, 8'sd7);
    send(8'sd4, 8'sd8);
    #1 chk("dot product 1.5+2.6+3.7+4.8", sum_o, 70);
    chk("relu of +70", relu_o, 70);

    // --- 3. negative result: ReLU must clamp --------------------------------
    do_clear();
    send( 8'sd2, -8'sd4);
    send( 8'sd3, -8'sd5);
    #1 chk("negative dot product", sum_o, -23);
    chk("relu of -23 clamps to 0", relu_o, 0);

    // --- 4. mixed signs, crossing zero on the way ---------------------------
    do_clear();
    send(-8'sd10, 8'sd10);   // -100
    send( 8'sd20, 8'sd10);   // +200 -> running total +100
    #1 chk("mixed signs", sum_o, 100);
    chk("relu of +100", relu_o, 100);

    // --- 5. clear_i really clears -------------------------------------------
    do_clear();
    #1 chk("clear zeroes the accumulator", sum_o, 0);
    send(8'sd7, 8'sd7);
    #1 chk("accumulate after clear", sum_o, 49);

    // --- 6. valid_i gates: junk on an idle bus must not accumulate ----------
    idle(4);
    #1 chk("idle cycles do not accumulate", sum_o, 49);

    // --- 7. full-scale operands: sign handling at the extremes --------------
    do_clear();
    send(-8'sd128, -8'sd128);          // +16384
    #1 chk("(-128)*(-128)", sum_o, 16384);
    send(-8'sd128,  8'sd127);          // -16256 -> +128
    #1 chk("(-128)*(+127) accumulated", sum_o, 128);

    // --- 8. a long accumulation, against a running model --------------------
    begin
      automatic longint model = 0;
      do_clear();
      #1 chk("cleared before long run", sum_o, 0);
      for (int i = 0; i < 64; i++) begin
        automatic logic signed [DATA_W-1:0] a = DATA_W'($urandom);
        automatic logic signed [DATA_W-1:0] w = DATA_W'($urandom);
        send(a, w);
        model += longint'(a) * longint'(w);
      end
      #1 chk("64-term random dot product", sum_o, ACC_W'(model));
      chk("relu of that result", relu_o, (model < 0) ? '0 : ACC_W'(model));
    end

    // --- 9. back-to-back output pixels, no contamination --------------------
    do_clear();
    send(8'sd3, 8'sd3);
    send(8'sd3, 8'sd3);
    #1 chk("pixel A", sum_o, 18);
    do_clear();
    send(8'sd1, 8'sd1);
    #1 chk("pixel B is not contaminated by pixel A", sum_o, 1);

    $display("");
    if (errors == 0)
      $display("CHECK PASS  -- MAC, accumulator, ReLU, clear and valid all correct");
    else
      $display("CHECK FAIL  (%0d errors)", errors);
    $finish;
  end

  initial begin
    if ($test$plusargs("trace")) begin
      $dumpfile("build/check/pe.vcd");
      $dumpvars(0, tb_check);
    end
  end

  initial begin
    #200000;
    $display("CHECK TIMEOUT -- simulation never reached $finish.");
    $fatal(1);
  end

endmodule
