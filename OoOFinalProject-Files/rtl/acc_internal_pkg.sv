// Types and helpers shared by the accelerator's internal modules only.
// Nothing here is part of the cross-team contract.

package acc_internal_pkg;

    import accelerator_cnn_pkg::*;

    // Which layer currently owns the memory ports. The top level muxes every
    // memory port on this, so exactly one engine is active at a time.
    typedef enum logic [2:0] {
        L_NONE  = 3'd0,
        L_CONV1 = 3'd1,
        L_POOL1 = 3'd2,
        L_CONV2 = 3'd3,
        L_POOL2 = 3'd4,
        L_FC    = 3'd5
    } layer_e;

    // One PE per output channel (both convolutions have 3 output channels).
    localparam int unsigned NUM_PE = C1_OC;

    // Engine byte-address width: covers IMG (2048) and ACT_A (2048).
    localparam int unsigned BYTE_ADDR_W = 11;

    // Conv requantization, verified against every golden vector:
    // arithmetic shift, then ReLU and saturate to uint8 in one clamp.
    // The caller starts the accumulator at the bias.
    function automatic act_t requant(input acc_t acc, input logic [4:0] shift);
        acc_t shifted;
        shifted = acc >>> shift;
        if (shifted < 0)        return 8'd0;
        else if (shifted > 255) return 8'd255;
        else                    return shifted[7:0];
    endfunction

endpackage
