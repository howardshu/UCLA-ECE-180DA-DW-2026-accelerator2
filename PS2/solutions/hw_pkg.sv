// ============================================================================
// hw_pkg.sv -- shared types for the ECE180 Verilog homework
//
// Unlike the lab, this package is COMPLETE. You do not need to edit it.
// Read it, though -- Problem 2 is much easier once you have.
// ============================================================================
package hw_pkg;

  // --------------------------------------------------------------------------
  // Problem 2: register file sizing
  // --------------------------------------------------------------------------
  parameter int unsigned XLEN     = 8;   // data width
  parameter int unsigned NUM_REGS = 8;   // 8 architectural registers
  parameter int unsigned REG_BITS = 3;   // $clog2(NUM_REGS)

  typedef logic [XLEN-1:0]     xdata_t;  // a register's worth of data
  typedef logic [REG_BITS-1:0] regid_t;  // a register index

  // --------------------------------------------------------------------------
  // The write port, as one bundle.
  //
  // This is the same idea as `req_t` in the lab: the three signals that always
  // travel together become one value. Note `en` lives INSIDE the struct --
  // a write port without its enable is not a meaningful thing to pass around,
  // so keeping them together makes the wrong code harder to write.
  //
  // Layout, most significant field first:
  //
  //        [11]    [10:8]    [7:0]
  //      +------+---------+---------+
  //      |  en  |   addr  |   data  |
  //      +------+---------+---------+
  // --------------------------------------------------------------------------
  typedef struct packed {
    logic   en;
    regid_t addr;
    xdata_t data;
  } wr_port_t;

endpackage
