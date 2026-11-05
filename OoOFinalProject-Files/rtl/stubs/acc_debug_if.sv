// STAND-IN -- replace when the course repo provides acc_debug_if.sv.
//
// tb_accelerator.sv reads results (RES) and activations (ACT_A/ACT_B) through
// this interface, but its signals are not published yet. This guess is a
// read-only port with one cycle of latency, so it maps onto the second port
// of a block RAM: drive sel/addr, rdata is valid after the next rising edge.
// Selecting MEM_IMG, MEM_WGT or MEM_PARAM reads zero (those are external).

interface acc_debug_if;

    import accelerator_cnn_pkg::*;

    mem_sel_e    sel;
    logic [10:0] addr;    // wide enough for ACT_A (2048 bytes)
    logic [31:0] rdata;   // ACT bytes are zero-extended


    // ----- Testbench Side -----
    modport tb (
        output sel,
               addr,

        input  rdata
    );


    // ----- Accelerator Side -----
    modport accelerator (
        input  sel,
               addr,

        output rdata
    );

endinterface
