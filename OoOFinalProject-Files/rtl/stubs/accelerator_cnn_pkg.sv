// STAND-IN -- delete when the course repo provides accelerator_cnn_pkg.
//
// tb_accelerator.sv and cnn_ext_mem.sv import accelerator_cnn_pkg, but the
// course common/ directory only declares accelerator_pkg (which already holds
// every CNN constant). This re-exports it under the name the testbench uses.

package accelerator_cnn_pkg;

    import accelerator_pkg::*;
    export accelerator_pkg::*;

endpackage
