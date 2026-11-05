// STAND-IN -- delete when the course repo provides cnn_mem_if.sv.
//
// Reconstructed from how common/cnn_ext_mem.sv uses it: three read-only ports,
// address out, data back. With cnn_ext_mem REGISTERED_READ=0 the data comes
// back the same cycle; with REGISTERED_READ=1 it comes back one cycle later.
// The modport name "accelerator" is a guess.

interface cnn_mem_if;

    import accelerator_cnn_pkg::*;

    logic [IMG_ADDR_W-1:0]   img_addr;
    logic [7:0]              img_rdata;
    logic [WGT_ADDR_W-1:0]   wgt_addr;
    logic [7:0]              wgt_rdata;
    logic [PARAM_ADDR_W-1:0] par_addr;
    logic [31:0]             par_rdata;


    // ----- Accelerator Side -----
    modport accelerator (
        output img_addr,
               wgt_addr,
               par_addr,

        input  img_rdata,
               wgt_rdata,
               par_rdata
    );


    // ----- External Memory Side -----
    modport memory (
        input  img_addr,
               wgt_addr,
               par_addr,

        output img_rdata,
               wgt_rdata,
               par_rdata
    );

endinterface
