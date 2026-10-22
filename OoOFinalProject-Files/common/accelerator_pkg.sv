// Custom CSR addresses used by the CSR unit and accelerator software.


package accelerator_pkg;

    // ----- Accelerator Configuration Registers -----
    // Three writable CSRs. This core does not implement privilege modes.
    localparam logic [11:0] CSR_ACC_ACTIVATE = 12'h7c0;
    localparam logic [11:0] CSR_ACC_MEMORY_LOCATION = 12'h7c1;
    localparam logic [11:0] CSR_ACC_LENGTH = 12'h7c2;

    // ACTIVATE Status Bits
    // Bit 0: requested/running. Hardware clears it when the job finishes.
    // Bit 1: sticky completion error, recorded by hardware and read-only to software.
    // An idle write uses bit 0 and clears error; other written bits are ignored.

endpackage
